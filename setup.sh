#!/usr/bin/env bash
# ============================================================
# video-transcribe-summary — environment setup / path detection
# Run once per machine:  bash setup.sh
# Prints export lines you can paste into your shell profile,
# or just note the detected paths and use them in SKILL.md.
# ============================================================
set -u

echo "==> Detecting environment for video-transcribe-summary"
echo

# --- Python: prefer a venv that ALREADY has mlx_whisper+yt_dlp ---
PYTHON=""
for cand in \
  "$HOME/.workbuddy/binaries/python/envs/default/bin/python3" \
  "$HOME/.workbuddy/binaries/python/versions/3.13.12/bin/python3" \
  "$(command -v python3 2>/dev/null)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    if "$cand" -c "import mlx_whisper, yt_dlp" 2>/dev/null; then
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
  echo "==> Installing yt-dlp + mlx-whisper (first run downloads deps)"
  "$VENV/bin/pip" install -q --upgrade pip 2>/dev/null
  "$VENV/bin/pip" install -q yt-dlp mlx-whisper 2>&1 | tail -1
  PYTHON="$VENV/bin/python3"
fi
echo "PYTHON=$PYTHON"

# --- yt-dlp (prefer venv install, fall back to system) ---
YTDLP="$(dirname "$PYTHON")/yt-dlp"
if [ ! -x "$YTDLP" ]; then YTDLP="$(command -v yt-dlp 2>/dev/null || echo 'yt-dlp')"; fi
echo "YTDLP=$YTDLP"

# --- ffmpeg / ffprobe ---
FFMPEG="$(command -v ffmpeg 2>/dev/null || echo '/opt/homebrew/bin/ffmpeg')"
FFPROBE="$(command -v ffprobe 2>/dev/null || echo '/opt/homebrew/bin/ffprobe')"
echo "FFMPEG=$FFMPEG"
echo "FFPROBE=$FFPROBE"
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "!! ffmpeg not found — install with: brew install ffmpeg" >&2
fi

# --- Chrome (for long-image rendering) ---
CHROME=""
for cand in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
  "$(command -v google-chrome 2>/dev/null)" \
  "$(command -v chromium 2>/dev/null)"; do
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
echo "export PYTHON=\"$PYTHON\""
echo "export YTDLP=\"$YTDLP\""
echo "export FFMPEG=\"$FFMPEG\""
echo "export FFPROBE=\"$FFPROBE\""
if [ -n "$CHROME" ]; then echo "export CHROME=\"$CHROME\""; fi
echo "----------------------------------------------------------"
echo "Done."
