#!/usr/bin/env sh
# Starts the NxSaves server on macOS / Linux. First run creates a virtual environment; every run
# updates yt-dlp. Needs Python 3.10+, ffmpeg and (for YouTube) Deno or Node.js on PATH.
set -e
cd "$(dirname "$0")"
[ -x .venv/bin/python ] || python3 -m venv .venv
.venv/bin/python -m pip install --quiet --upgrade pip
.venv/bin/python -m pip install --quiet --upgrade -r requirements.txt
command -v ffmpeg >/dev/null || echo "WARNING: ffmpeg not found - install it (brew install ffmpeg / apt install ffmpeg)"
command -v deno >/dev/null || command -v node >/dev/null || echo "WARNING: no JS runtime - install Deno for full YouTube support"
exec .venv/bin/python nxsaves_server.py "$@"
