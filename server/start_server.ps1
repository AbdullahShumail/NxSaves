# Starts the NxSaves server on Windows. First run creates a Python virtual environment; every run
# updates yt-dlp (sites change often, updates keep downloads working).
#
# Usage:  powershell -ExecutionPolicy Bypass -File server\start_server.ps1 [-Port 8765]
param([int]$Port = 8765)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$venvPython = '.venv\Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    $python = Get-Command py -ErrorAction SilentlyContinue
    if ($python) { & py -3 -m venv .venv } else { & python -m venv .venv }
    if (-not (Test-Path $venvPython)) { throw 'Could not create a virtual environment. Install Python 3.10+ from python.org.' }
}

& $venvPython -m pip install --quiet --upgrade pip
& $venvPython -m pip install --quiet --upgrade -r requirements.txt

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warning 'ffmpeg was not found on PATH. Install it (winget install Gyan.FFmpeg) or set NXSAVES_FFMPEG.'
}
if (-not ((Get-Command deno -ErrorAction SilentlyContinue) -or (Get-Command node -ErrorAction SilentlyContinue))) {
    Write-Warning 'No JavaScript runtime found. Install Deno (winget install DenoLand.Deno) for full YouTube support.'
}

& $venvPython nxsaves_server.py --port $Port
