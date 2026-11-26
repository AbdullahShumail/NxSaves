#!/usr/bin/env python3
"""NxSaves server: runs yt-dlp + ffmpeg for the NxSaves app.

iOS doesn't let apps start helper processes (ffmpeg, a JavaScript runtime) or update their own
code, and yt-dlp needs all three, so the iPhone app sends links to this server, which downloads,
merges and converts the media and then streams the finished file back to the phone. The Android
app runs yt-dlp on the phone but can use this server too.

    python nxsaves_server.py [--host 0.0.0.0] [--port 8765]

Environment variables:
    NXSAVES_TOKEN          access token (default: generated once and stored in <data>/token.txt)
    NXSAVES_DATA           data folder (default: ./data next to this file)
    NXSAVES_WORKERS        downloads that run at the same time (default 2)
    NXSAVES_JOB_TTL_HOURS  finished files are deleted after this long (default 6)
    NXSAVES_COOKIES        optional cookies.txt (Netscape format) for sites that need a login
    NXSAVES_FFMPEG         optional path to ffmpeg if it is not on PATH
"""

from __future__ import annotations

import argparse
import ipaddress
import logging
import mimetypes
import os
import re
import secrets
import shutil
import socket
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal, Optional
from urllib.parse import urlparse

import uvicorn
import yt_dlp
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, PlainTextResponse
from pydantic import BaseModel
from yt_dlp.utils import DownloadCancelled
from yt_dlp.version import __version__ as YTDLP_VERSION

SERVER_VERSION = "1.0.0"
log = logging.getLogger("nxsaves")

DATA_DIR = Path(os.environ.get("NXSAVES_DATA") or Path(__file__).resolve().parent / "data").resolve()
JOBS_DIR = DATA_DIR / "jobs"
CACHE_DIR = DATA_DIR / "cache"
WORKERS = max(1, int(os.environ.get("NXSAVES_WORKERS", "2")))
JOB_TTL = float(os.environ.get("NXSAVES_JOB_TTL_HOURS", "6")) * 3600
COOKIES = os.environ.get("NXSAVES_COOKIES") or None
FFMPEG = os.environ.get("NXSAVES_FFMPEG") or shutil.which("ffmpeg")


def load_token() -> str:
    token = os.environ.get("NXSAVES_TOKEN", "").strip()
    if token:
        return token
    path = DATA_DIR / "token.txt"
    if path.exists() and path.read_text().strip():
        return path.read_text().strip()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(24)
    path.write_text(token)
    return token


def detect_js_runtime() -> tuple[Optional[str], list[str]]:
    """YouTube needs a JavaScript runtime to solve its challenges. yt-dlp uses Deno automatically;
    Node, QuickJS and Bun have to be enabled explicitly."""
    if shutil.which("deno"):
        return "deno", []
    for name, exe in (("node", "node"), ("quickjs", "qjs"), ("bun", "bun")):
        if shutil.which(exe):
            return name, ["--js-runtimes", name]
    return None, []


TOKEN = load_token()
JS_RUNTIME, JS_ARGS = detect_js_runtime()


def common_args() -> list[str]:
    args = ["--cache-dir", str(CACHE_DIR), *JS_ARGS]
    if FFMPEG:
        args += ["--ffmpeg-location", FFMPEG]
    if COOKIES:
        args += ["--cookies", COOKIES]
    return args


# --- What the app asks for. Keep in sync with lib/src/core/ytdlp_args.dart -----------------------


class Spec(BaseModel):
    kind: Literal["video", "audio"] = "video"
    height: Optional[int] = None
    audioFormat: Literal["mp3", "m4a"] = "mp3"
    preferCompat: bool = True


def format_sort(spec: Spec) -> str:
    res = "res" if spec.height is None else f"res:{int(spec.height)}"
    return f"{res},vcodec:h264,fps,acodec:aac" if spec.preferCompat else f"{res},fps"


def spec_args(spec: Spec) -> list[str]:
    if spec.kind == "video":
        return ["-f", "bv*+ba/b", "-S", format_sort(spec), "--merge-output-format", "mp4"]
    return [
        "-f", "ba[ext=m4a]/ba/b" if spec.audioFormat == "m4a" else "ba/b",
        "-x", "--audio-format", spec.audioFormat, "--audio-quality", "0",
        "--embed-metadata", "--embed-thumbnail",
    ]


def download_args(spec: Spec, out_dir: Path) -> list[str]:
    return [
        "--no-playlist", "--no-mtime", "--windows-filenames",
        "--concurrent-fragments", "4", "--retries", "10", "--fragment-retries", "10",
        *common_args(),
        "-P", str(out_dir), "-o", "%(title,id).150B.%(ext)s",
        *spec_args(spec),
    ]


def check_url(url: str) -> str:
    url = url.strip()
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise HTTPException(400, "Only http(s) links are supported.")
    host = parsed.hostname.lower()
    if host == "localhost" or host.endswith(".local"):
        raise HTTPException(400, "Local network addresses are not allowed.")
    try:
        ip = ipaddress.ip_address(host)
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_unspecified:
            raise HTTPException(400, "Local network addresses are not allowed.")
    except ValueError:
        pass  # a hostname, not an IP literal
    return url


class CaptureLogger:
    """Receives yt-dlp's messages (instead of printing them), keeps the last error and, for
    downloads, tracks which part (video, then audio) is being fetched."""

    FORMATS_LINE = re.compile(r"^\[info\] .+: Downloading \d+ format\(s\): (.+)$")

    def __init__(self, job: Optional["Job"] = None) -> None:
        self.last_error: Optional[str] = None
        self.job = job

    def debug(self, msg: str) -> None:
        job = self.job
        if job is None:
            return
        match = self.FORMATS_LINE.match(msg)
        if match:
            job.parts = max(1, len(match.group(1).split("+")))
            job.part = -1
        elif msg.startswith("[download] Destination:") or (
                msg.startswith("[download]") and msg.endswith("has already been downloaded")):
            job.part = min(job.part + 1, job.parts - 1)

    def info(self, msg: str) -> None:
        pass

    def warning(self, msg: str) -> None:
        log.debug("yt-dlp: %s", msg)

    def error(self, msg: str) -> None:
        self.last_error = re.sub(r"\x1b\[[0-9;]*m", "", msg)
        log.info("yt-dlp: %s", self.last_error)


# --- Jobs ----------------------------------------------------------------------------------------

PP_LABELS = {
    "Merger": "Merging video and audio",
    "ExtractAudio": "Converting audio",
    "EmbedThumbnail": "Adding cover art",
    "Metadata": "Writing metadata",
    "ThumbnailsConvertor": "Preparing cover art",
    "VideoRemuxer": "Remuxing",
    "VideoConvertor": "Converting video",
}


@dataclass
class Job:
    id: str
    url: str
    spec: Spec
    title: str = ""
    status: str = "queued"  # queued | downloading | processing | ready | error | canceled
    stage: str = "Waiting for a free slot"
    progress: Optional[float] = None
    downloaded: Optional[int] = None
    total: Optional[int] = None
    speed: Optional[float] = None
    eta: Optional[int] = None
    filename: Optional[str] = None
    path: Optional[Path] = None
    size: Optional[int] = None
    error: Optional[str] = None
    part: int = -1
    parts: int = 1
    created: float = field(default_factory=time.time)
    updated: float = field(default_factory=time.time)
    cancel: threading.Event = field(default_factory=threading.Event)

    @property
    def dir(self) -> Path:
        return JOBS_DIR / self.id

    def set(self, **values: Any) -> None:
        for key, value in values.items():
            setattr(self, key, value)
        self.updated = time.time()

    def public(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "url": self.url,
            "title": self.title,
            "status": self.status,
            "stage": self.stage,
            "progress": self.progress,
            "downloaded": self.downloaded,
            "total": self.total,
            "speed": self.speed,
            "eta": self.eta,
            "filename": self.filename,
            "size": self.size,
            "error": self.error,
        }


jobs: dict[str, Job] = {}
jobs_lock = threading.Lock()
executor = ThreadPoolExecutor(max_workers=WORKERS, thread_name_prefix="job")


def progress_hook(job: Job):
    def hook(d: dict[str, Any]) -> None:
        if job.cancel.is_set():
            raise DownloadCancelled("Canceled")
        info = d.get("info_dict") or {}
        parts = job.parts
        part = max(0, job.part)
        total = d.get("total_bytes") or d.get("total_bytes_estimate")
        done = d.get("downloaded_bytes")
        if d.get("status") == "finished":
            fraction: Optional[float] = 1.0
        elif done is not None and total:
            fraction = min(1.0, done / total)
        else:
            fraction = None
        vcodec, acodec = info.get("vcodec"), info.get("acodec")
        if vcodec not in (None, "none") and acodec == "none":
            stage = "Downloading video"
        elif vcodec == "none" and acodec not in (None, "none"):
            stage = "Downloading audio"
        else:
            stage = "Downloading"
        if parts > 1:
            stage += f" ({part + 1}/{parts})"
        job.set(
            status="downloading",
            stage=stage,
            progress=None if fraction is None else (part + fraction) / parts,
            downloaded=int(done) if done is not None else None,
            total=int(total) if total else None,
            speed=d.get("speed"),
            eta=int(d["eta"]) if d.get("eta") is not None else None,
        )

    return hook


def postprocessor_hook(job: Job):
    def hook(d: dict[str, Any]) -> None:
        if job.cancel.is_set():
            raise DownloadCancelled("Canceled")
        if d.get("status") == "started":
            label = PP_LABELS.get(d.get("postprocessor") or "", "Finalizing")
            job.set(status="processing", stage=label, progress=None, speed=None, eta=None)

    return hook


SIDECAR_SUFFIXES = {".part", ".ytdl", ".temp", ".tmp", ".jpg", ".jpeg", ".png", ".webp", ".json",
                    ".vtt", ".srt", ".ass", ".lrc", ".description"}


def find_output(folder: Path) -> Optional[Path]:
    files = [f for f in folder.iterdir()
             if f.is_file() and f.suffix.lower() not in SIDECAR_SUFFIXES and ".part-Frag" not in f.name]
    return max(files, key=lambda f: f.stat().st_size) if files else None


def run_job(job: Job) -> None:
    if job.cancel.is_set():
        job.set(status="canceled", stage="Canceled")
        return
    job.dir.mkdir(parents=True, exist_ok=True)
    logger = CaptureLogger(job)
    try:
        opts = yt_dlp.parse_options(download_args(job.spec, job.dir)).ydl_opts
        opts.update(
            logger=logger,
            quiet=True,
            noprogress=True,
            progress_hooks=[progress_hook(job)],
            postprocessor_hooks=[postprocessor_hook(job)],
        )
        job.set(status="downloading", stage="Reading link")
        with yt_dlp.YoutubeDL(opts) as ydl:
            code = ydl.download([job.url])
        if job.cancel.is_set():
            raise DownloadCancelled("Canceled")
        output = find_output(job.dir)
        if code != 0 or output is None:
            raise RuntimeError(logger.last_error or "The download finished but no file was made.")
        job.set(status="ready", stage="Ready", progress=1.0, speed=None, eta=None,
                filename=output.name, path=output, size=output.stat().st_size)
        log.info("job %s ready: %s (%d bytes)", job.id, output.name, job.size)
    except DownloadCancelled:
        job.set(status="canceled", stage="Canceled", speed=None, eta=None)
        shutil.rmtree(job.dir, ignore_errors=True)
    except Exception as exc:  # noqa: BLE001 - every failure is reported to the app
        message = logger.last_error or str(exc)
        job.set(status="error", stage="Failed", error=message, speed=None, eta=None)
        log.warning("job %s failed: %s", job.id, message)


def cleanup_loop() -> None:
    while True:
        time.sleep(600)
        cutoff = time.time() - JOB_TTL
        with jobs_lock:
            expired = [j for j in jobs.values() if j.updated < cutoff and j.status not in ("queued", "downloading", "processing")]
            for job in expired:
                jobs.pop(job.id, None)
        for job in expired:
            shutil.rmtree(job.dir, ignore_errors=True)


# --- HTTP API ------------------------------------------------------------------------------------

app = FastAPI(title="NxSaves server", version=SERVER_VERSION, docs_url=None, redoc_url=None)


def require_token(authorization: str = Header(default="")) -> None:
    if not secrets.compare_digest(authorization.encode(), f"Bearer {TOKEN}".encode()):
        raise HTTPException(401, "Invalid or missing access token.")


class InfoRequest(BaseModel):
    url: str


class JobRequest(BaseModel):
    url: str
    spec: Spec = Spec()
    title: str = ""


INFO_KEYS = ("id", "title", "fulltitle", "uploader", "channel", "creator", "uploader_id", "thumbnail",
             "duration", "extractor", "extractor_key", "webpage_url", "original_url", "_type", "is_live",
             "live_status", "url", "ext", "width", "height", "vcodec", "acodec", "filesize", "filesize_approx", "tbr")
FORMAT_KEYS = ("format_id", "ext", "vcodec", "acodec", "width", "height", "fps", "filesize", "filesize_approx",
               "tbr", "abr", "protocol", "format_note", "dynamic_range")
ENTRY_KEYS = ("id", "url", "webpage_url", "title", "duration", "uploader", "channel", "thumbnail")


def trim_info(info: dict[str, Any]) -> dict[str, Any]:
    """Only what the app needs (full yt-dlp output can be megabytes of captions)."""
    out = {k: info[k] for k in INFO_KEYS if info.get(k) is not None}
    if not out.get("thumbnail") and info.get("thumbnails"):
        out["thumbnail"] = info["thumbnails"][-1].get("url")
    if isinstance(info.get("formats"), list):
        out["formats"] = [{k: f[k] for k in FORMAT_KEYS if f.get(k) is not None} for f in info["formats"]]
    if isinstance(info.get("entries"), list):
        entries = []
        for entry in info["entries"]:
            if not isinstance(entry, dict):
                continue
            item = {k: entry[k] for k in ENTRY_KEYS if entry.get(k) is not None}
            if "thumbnail" not in item and entry.get("thumbnails"):
                item["thumbnail"] = entry["thumbnails"][-1].get("url")
            entries.append(item)
        out["entries"] = entries
    return out


@app.get("/", response_class=PlainTextResponse, include_in_schema=False)
def root() -> str:
    return "NxSaves server is running. Add this address and your token in the NxSaves app.\n"


@app.get("/api/health", dependencies=[Depends(require_token)])
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "server": SERVER_VERSION,
        "ytdlp": YTDLP_VERSION,
        "ffmpeg": FFMPEG is not None,
        "jsRuntime": JS_RUNTIME,
        "cookies": COOKIES is not None,
    }


@app.post("/api/info", dependencies=[Depends(require_token)])
def info(request: InfoRequest) -> dict[str, Any]:
    url = check_url(request.url)
    logger = CaptureLogger()
    opts = yt_dlp.parse_options(["--no-playlist", "--flat-playlist", *common_args()]).ydl_opts
    opts.update(logger=logger, quiet=True, noprogress=True)
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            data = ydl.sanitize_info(ydl.extract_info(url, download=False))
    except yt_dlp.utils.DownloadError as exc:
        raise HTTPException(422, logger.last_error or str(exc)) from exc
    if not data:
        raise HTTPException(422, logger.last_error or "Couldn't find anything to download at this link.")
    return trim_info(data)


@app.post("/api/jobs", dependencies=[Depends(require_token)])
def create_job(request: JobRequest) -> dict[str, Any]:
    job = Job(id=uuid.uuid4().hex, url=check_url(request.url), spec=request.spec, title=request.title[:300])
    with jobs_lock:
        jobs[job.id] = job
    executor.submit(run_job, job)
    log.info("job %s queued: %s %s", job.id, job.spec.model_dump(), job.url)
    return job.public()


def get_job(job_id: str) -> Job:
    job = jobs.get(job_id)
    if job is None:
        raise HTTPException(404, "Job not found (it may have expired).")
    return job


@app.get("/api/jobs/{job_id}", dependencies=[Depends(require_token)])
def job_status(job_id: str) -> dict[str, Any]:
    return get_job(job_id).public()


@app.get("/api/jobs/{job_id}/file", dependencies=[Depends(require_token)])
def job_file(job_id: str) -> FileResponse:
    job = get_job(job_id)
    if job.status != "ready" or job.path is None or not job.path.exists():
        raise HTTPException(409, "The file is not ready.")
    job.set()  # keep it alive while it is being fetched
    media_type = mimetypes.guess_type(job.path.name)[0] or "application/octet-stream"
    return FileResponse(job.path, media_type=media_type, filename=job.filename)


@app.delete("/api/jobs/{job_id}", dependencies=[Depends(require_token)])
def delete_job(job_id: str) -> dict[str, Any]:
    job = jobs.get(job_id)
    if job is None:
        return {"ok": True}
    job.cancel.set()
    if job.status not in ("downloading", "processing"):
        with jobs_lock:
            jobs.pop(job_id, None)
        shutil.rmtree(job.dir, ignore_errors=True)
    # A running job removes its own files once it notices the cancel flag.
    return {"ok": True}


def local_addresses() -> list[str]:
    addresses = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    return sorted(a for a in addresses if not a.startswith("127."))


def main() -> None:
    parser = argparse.ArgumentParser(description="NxSaves server (yt-dlp + ffmpeg for the NxSaves app)")
    parser.add_argument("--host", default=os.environ.get("NXSAVES_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("NXSAVES_PORT", "8765")))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    shutil.rmtree(JOBS_DIR, ignore_errors=True)  # jobs don't survive restarts; drop leftovers
    JOBS_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=cleanup_loop, daemon=True).start()

    print(f"\n  NxSaves server {SERVER_VERSION} - yt-dlp {YTDLP_VERSION}")
    print(f"  ffmpeg:      {FFMPEG or 'NOT FOUND - install ffmpeg (merging/MP3 will fail)'}")
    print(f"  JS runtime:  {JS_RUNTIME or 'NOT FOUND - install Deno or Node.js (YouTube will be limited)'}")
    print(f"  Cookies:     {COOKIES or 'none'}")
    print(f"  Data folder: {DATA_DIR}")
    for address in local_addresses():
        print(f"  Address:     http://{address}:{args.port}")
    print(f"  Token:       {TOKEN}\n", flush=True)
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
