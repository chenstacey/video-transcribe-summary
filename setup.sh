#!/usr/bin/env bash
# ============================================================
# video-transcribe-summary — environment setup / path detection
# Run once per machine:  bash setup.sh
#
# Cross-platform: macOS (Apple Silicon) uses mlx-whisper;
# Linux / other machines fall back to faster-whisper (CPU).
# Prints export lines you can paste into your shell profile,
# or just note the detected paths and use them in SKILL.md.
# ============================================================
set -u

echo "==> Detecting environment for video-transcribe-summary"
echo

OS="$(uname -s)"
ARCH="$(uname -m)"

# ASR engine: mlx-whisper only runs on macOS arm64; elsewhere use faster-whisper
if [ "$OS" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
  ASR_PKG="mlx-whisper"
  ASR_IMPORT="mlx_whisper"
  ASR_NAME="mlx-whisper (Metal)"
else
  ASR_PKG="faster-whisper"
  ASR_IMPORT="faster_whisper"
  ASR_NAME="faster-whisper (CPU)"
fi
echo "==> ASR engine: $ASR_NAME"

# --- Python: prefer a venv that ALREADY has the ASR engine + yt_dlp ---
PYTHON=""
for cand in \
  "$HOME/.workbuddy/binaries/python/envs/default/bin/python3" \
  "$HOME/.workbuddy/binaries/python/versions/3.13.12/bin/python3" \
  "$(command -v python3 2>/dev/null)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    if "$cand" -c "import $ASR_IMPORT, yt_dlp" 2>/dev/null; then
      PYTHON="$cand"; break
    fi
  fi
done

# Fallback: create a dedicated venv and install deps
if [ -z "$PYTHON" ]; then
  BASE=""
  for cand in \
    "$HOME/.workbuddy/binaries/python/versions/3.13.12/bin/python3" \
    "$(command -v python3 2>/dev/null)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then BASE="$cand"; break; fi
  done
  [ -z "$BASE" ] && { echo "!! python3 not found. Install Python 3.10+ first." >&2; exit 1; }

  VENV="$HOME/.workbuddy/venvs/video-transcribe-summary"
  if [ ! -x "$VENV/bin/python3" ]; then
    echo "==> Creating venv at $VENV"
    "$BASE" -m venv "$VENV"
  fi
  echo "==> Installing yt-dlp + $ASR_PKG (first run downloads deps)"
  "$VENV/bin/pip" install -q --upgrade pip 2>/dev/null
  "$VENV/bin/pip" install -q yt-dlp "$ASR_PKG" 2>&1 | tail -1
  PYTHON="$VENV/bin/python3"
fi
echo "PYTHON=$PYTHON"

# --- yt-dlp (prefer venv install, fall back to system) ---
YTDLP="$(dirname "$PYTHON")/yt-dlp"
if [ ! -x "$YTDLP" ]; then YTDLP="$(command -v yt-dlp 2>/dev/null || echo 'yt-dlp')"; fi
echo "YTDLP=$YTDLP"

# --- ffmpeg / ffprobe ---
FFMPEG="$(command -v ffmpeg 2>/dev/null || echo 'ffmpeg')"
FFPROBE="$(command -v ffprobe 2>/dev/null || echo 'ffprobe')"
echo "FFMPEG=$FFMPEG"
echo "FFPROBE=$FFPROBE"
if ! command -v ffmpeg >/dev/null 2>&1; then
  if [ "$OS" = "Darwin" ]; then
    echo "!! ffmpeg not found — install with: brew install ffmpeg" >&2
  else
    echo "!! ffmpeg not found — install with: sudo apt-get install -y ffmpeg  (or your distro equivalent)" >&2
  fi
fi

# --- Chrome (for long-image rendering) ---
CHROME=""
for cand in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
  "$(command -v google-chrome 2>/dev/null)" \
  "$(command -v chromium 2>/dev/null)" \
  "$(command -v chromium-browser 2>/dev/null)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then CHROME="$cand"; break; fi
done
if [ -z "$CHROME" ]; then
  echo "CHROME=(not found — WeChat long image step will be skipped)"
else
  echo "CHROME=$CHROME"
fi

echo
echo "==> Add these to your shell profile (or use them inline):"
echo "----------------------------------------------------------"
echo "export ASR_ENGINE=\"$ASR_NAME\""
echo "export PYTHON=\"$PYTHON\""
echo "export YTDLP=\"$YTDLP\""
echo "export FFMPEG=\"$FFMPEG\""
echo "export FFPROBE=\"$FFPROBE\""
if [ -n "$CHROME" ]; then echo "export CHROME=\"$CHROME\""; fi
echo "----------------------------------------------------------"

echo
echo "==> First transcription will download the whisper model"
echo "    (medium ≈ 1.5 GB, cached afterwards). Requires outbound"
echo "    network to Hugging Face / mlx-community."
echo "Done."
