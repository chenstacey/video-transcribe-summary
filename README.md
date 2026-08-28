# video-transcribe-summary

Turn any online video/audio link into a structured Chinese document: timestamped transcript (translated when needed) + executive summary + key quotes, plus an optional WeChat-shareable long image (PNG infographic).

Works with: **Bilibili, YouTube, Apple Podcasts (RSS), 小宇宙 (Xiaoyuzhou), direct audio URLs, local files**.

No API keys needed — audio is downloaded locally and transcribed with Whisper:
- **macOS (Apple Silicon)**: [mlx-whisper](https://github.com/ml-explore/mlx-audio) (Metal-accelerated)
- **Linux / cloud / other**: [faster-whisper](https://github.com/SYSTRAN/faster-whisper) (CPU, CTranslate2) — auto-selected by `setup.sh` and `scripts/transcribe.py`

## Install (as a WorkBuddy skill)

The skill folder contains `SKILL.md` + `templates/` + `setup.sh`. Copy the whole folder into your WorkBuddy skills directory:

```bash
# local WorkBuddy: user-level skills
mkdir -p ~/.workbuddy/skills
git clone https://github.com/chenstacey/video-transcribe-summary.git \
  ~/.workbuddy/skills/video-transcribe-summary

# or for a cloud/other machine: clone anywhere (or unzip the transfer bundle), then run setup
cd ~/.workbuddy/skills/video-transcribe-summary
bash setup.sh     # detects OS/Python/ffmpeg/Chrome, creates venv, installs deps
```

Then reload WorkBuddy. Sending any video/audio URL with "转写 / transcribe / 总结 / summarize" triggers the skill.

### Offline transfer (no GitHub access, e.g. internal-network sandbox)

If the target machine cannot reach GitHub (e.g. `networkEnvironment: internal`), transfer the repo as a zip:

1. Download `video-transcribe-summary.zip` from any machine with GitHub access.
2. On the target machine: `unzip video-transcribe-summary.zip -d ~/.workbuddy/skills/` (archive root folder is `video-transcribe-summary/`).
3. Run `bash ~/.workbuddy/skills/video-transcribe-summary/setup.sh`.

**Caveat**: `setup.sh` (pip install yt-dlp / faster-whisper) and the Whisper model download both require outbound network. On a fully internal sandbox, test connectivity first:
`pip download faster-whisper --no-deps -d /tmp/test` — if that fails, only the file layout will work; transcription still needs network or a pre-downloaded model.

## Requirements

- **macOS (Apple Silicon)**: mlx-whisper (Metal-accelerated, default engine)
- **Linux / cloud / other**: faster-whisper (CPU, CTranslate2) — auto-selected by `setup.sh` / `scripts/transcribe.py`
- Python 3.10+, ffmpeg (for long-audio splitting), Chrome/Chromium/Edge (optional, only for the WeChat long-image step).
- ~2 GB free disk for the whisper-medium model cache (one-time download; requires outbound network to Hugging Face / mlx-community).

## How it works

1. **Metadata first**: Bilibili API (cid + CC subtitle check), YouTube via `yt-dlp --list-subs`, Apple Podcasts via iTunes API + RSS feed → direct mp3 enclosure, Xiaoyuzhou via episode-page scrape → direct m4a URL.
2. **Captions if available, else ASR**: usable CC/auto captions are downloaded (seconds); otherwise audio is downloaded and transcribed locally.
3. **Chunked transcription**: audio >~15 min is split into 580s chunks (avoids tool timeouts), each run through the auto-selected Whisper engine (medium), then merged with correct global timestamps.
4. **Chinese summary document**: Executive Summary + timestamped organized transcript + key quotes table.
5. **WeChat long image (PNG)**: optional 750px vertical infographic rendered from an HTML template via headless Chrome, bottom-trimmed with PIL.

## Output

| File | Purpose |
|------|---------|
| `[title].md` | Full Chinese document: summary + timestamped transcript + quotes |
| `[title]长图.png` | Mobile-friendly long image for WeChat sharing |

## Project layout

```
video-transcribe-summary/
├── SKILL.md                          # the skill definition (WorkBuddy reads this)
├── setup.sh                          # one-time env detection + deps install (macOS & Linux)
├── README.md
├── scripts/
│   └── transcribe.py                 # cross-platform Whisper CLI (mlx-whisper / faster-whisper)
└── templates/
    └── wechat_longimage_template.html # {{placeholder}} template for the PNG infographic
```

## Notes / caveats

- Bilibili's subtitle API often returns empty for hardcoded-subtitle videos → falls back to ASR automatically.
- Apple Podcasts `podcasts.apple.com` pages region-redirect WebFetch to a CN browse page; the skill resolves episodes via the iTunes API + RSS feed instead.
- Whisper can hallucinate on silence/music — always sanity-check the transcript before presenting.
- Performance on Apple M4/24GB: 5 min ≈ 30s, 30 min ≈ 5 min, 60 min ≈ 10 min (chunked, whisper-medium).
