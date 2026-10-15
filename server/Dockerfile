# NxSaves server image: Python + yt-dlp + ffmpeg + Deno (JavaScript runtime YouTube needs).
#   docker build -t nxsaves-server server/
#   docker run -d --name nxsaves -p 8765:8765 -v nxsaves-data:/data --restart unless-stopped nxsaves-server
#   docker logs nxsaves        # shows the access token
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl unzip \
    && curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh \
    && apt-get purge -y curl unzip && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY nxsaves_server.py .

ENV NXSAVES_DATA=/data
VOLUME /data
EXPOSE 8765

# Update yt-dlp on every start, then run the server.
CMD pip install --no-cache-dir --quiet --upgrade "yt-dlp[default,curl-cffi]" || true; \
    exec python nxsaves_server.py --host 0.0.0.0 --port 8765
