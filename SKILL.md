---
name: video-transcribe-summary
description: Transcribe and summarize online videos (Bilibili, YouTube, Apple Podcasts, Xiaoyuzhou 小宇宙, podcasts, etc.) into a structured Chinese document with timestamped transcript, key points, and direct quotes, plus a WeChat-shareable long image (PNG infographic). Use when the user sends a video link (B站/bilibili/youtube/podcast URL) and asks to "transcribe", "转写", "总结", "summarize", or "extract content" from it. Downloads audio locally and runs mlx-whisper for speech-to-text on Apple Silicon — no API keys needed.
agent_created: true
---

# Video Transcribe & Summary

Turn any online video/audio link into a structured Chinese document: timestamped transcript (translated when needed) + executive summary + key quotes.

## Trigger

User sends a video/audio URL and asks for any of:
- 转写 / transcribe / transcript
- 总结 / summarize / summary
- 提取内容 / extract content
- 字幕 / subtitles
- "帮我看看这个视频讲了什么"

Supported sources: Bilibili, YouTube, Apple Podcasts, 小宇宙 (Xiaoyuzhou), podcast pages, direct audio URLs, local files.

## Prerequisites (one-time setup)

Run the bundled detector once per machine — it finds a Python env that already has the ASR engine + `yt_dlp` (mlx-whisper on macOS Apple Silicon, faster-whisper on Linux), creates a venv and installs them if missing, and prints the exact paths to use:

```bash
bash setup.sh          # from this skill's directory
```

It prints `export` lines for `PYTHON`, `YTDLP`, `FFMPEG`, `FFPROBE`, `CHROME`, `ASR_ENGINE`. Put them in your shell profile (or just substitute them inline below). All commands in this skill use these variables — never hardcode machine-specific paths.

Quick manual equivalent:
```bash
# Create venv if missing
python3 -m venv ~/.workbuddy/venvs/video-transcribe-summary 2>/dev/null
# Install tools (idempotent) — engine depends on OS:
#   macOS Apple Silicon: mlx-whisper | Linux/other: faster-whisper
~/.workbuddy/venvs/video-transcribe-summary/bin/pip install -q yt-dlp mlx-whisper 2>&1 | tail -1
# Verify ffmpeg (system, should already exist)
which ffmpeg || echo "INSTALL: brew install ffmpeg  (Linux: apt-get install -y ffmpeg)"
```

Key binaries (use the variables from `setup.sh`):
- **Python**: `$PYTHON` (e.g. `~/.workbuddy/binaries/python/envs/default/bin/python3` on this Mac)
- **yt-dlp**: `$YTDLP`
- **ffmpeg**: `$FFMPEG` / `$FFPROBE`
- **Chrome**: `$CHROME` (for the long-image step; skip that step if not found)

## Workflow

### Step 1 — Fetch video metadata

Get title, description, duration, and subtitle availability BEFORE downloading audio. This informs the transcription strategy.

**Bilibili** (get cid first, then check subtitles):
```bash
# Get cid + metadata
curl -s "https://api.bilibili.com/x/web-interface/view?bvid=<BVID>" \
  -H "User-Agent: Mozilla/5.0" | python3 -c "
import sys,json; d=json.load(sys.stdin)['data']
print('cid:', d.get('cid')); print('duration:', d.get('duration'))
print('title:', d.get('title')); print('desc:', d.get('desc'))
"

# Check for CC subtitles (often empty for hardcoded-sub videos)
curl -s "https://api.bilibili.com/x/player/v2?bvid=<BVID>&cid=<CID>" \
  -H "User-Agent: Mozilla/5.0" | python3 -c "
import sys,json; d=json.load(sys.stdin)['data']['subtitle']
print('subtitles:', d.get('subtitles',[]))
"
```

**Podcasts (Apple Podcasts / RSS)** — WebFetch on podcasts.apple.com gets region-redirected to a CN browse page and NEVER returns the episode. Use the iTunes API + RSS feed path instead:

```bash
# URL format: podcasts.apple.com/<region>/podcast/<slug>/id<SHOW_ID>?i=<EPISODE_ID>
# 1) Get show info + feed URL via iTunes lookup (use SHOW_ID, not episode id)
curl -s "https://itunes.apple.com/lookup?id=<SHOW_ID>&entity=podcastEpisode&limit=200" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('results', []):
    if r.get('wrapperType') == 'track':
        print('EP:', r.get('trackId'), '|', r.get('trackName'), '|', r.get('trackTimeMillis',0)//1000, 'sec')
        print('  Audio:', r.get('episodeUrl'))
    else:
        print('SHOW:', r.get('collectionName'))
        print('  FeedURL:', r.get('feedUrl'))
"

# 2) If the episode isn't in the lookup results, parse the RSS feed directly
curl -s "<feedUrl>" -H "User-Agent: Mozilla/5.0" > /tmp/feed.xml
python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('/tmp/feed.xml')
for item in tree.getroot().iter('item'):
    title = item.findtext('title') or ''
    if '<KEYWORD FROM EPISODE TITLE>' in title:
        print('Title:', title)
        print('Duration:', item.findtext('{http://www.itunes.com/dtds/podcast-1.0.dtd}duration'))
        for enc in item.iter('enclosure'):
            print('Audio:', enc.get('url'))
        break
"
```

The `<enclosure url=...>` is a direct mp3 link (often via podtrac/pdst.fm redirect chains) — `curl -sL` follows it fine. No yt-dlp, no cookies needed.

Also check the episode description in the RSS `<description>` or iTunes API — podcast episodes sometimes have full show notes with structure/segments that help with summarization.

**小宇宙 (Xiaoyuzhou)** — URL format: `https://www.xiaoyuzhoufm.com/episode/<EPISODE_ID>`. The episode page HTML embeds the direct audio URL (`media.xyzcdn.net/...m4a`) — no yt-dlp, no API needed. Fetch the page and grep it:

```bash
curl -s "https://www.xiaoyuzhoufm.com/episode/<EPISODE_ID>" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
  > "$TMPDIR/xyz.html"

# Extract direct m4a URL + title + duration from the embedded JSON/HTML
grep -o 'https://media.xyzcdn.net/[^"]*\.m4a' "$TMPDIR/xyz.html" | head -1
grep -o '<title>[^<]*</title>' "$TMPDIR/xyz.html"
```

The first `media.xyzcdn.net` match is the full episode audio (`.m4a`). Also grab the shownotes text from the page (in the `shownotes` JSON field) — it often contains episode structure and guest bios useful for summarization. Feed URL (if needed): `https://www.xiaoyuzhoufm.com/podcasts/<PODCAST_ID>/rss`.

**YouTube / other sites**: Use `yt-dlp --list-subs <URL>` to check for available caption tracks. If a usable caption track exists, download it directly with `yt-dlp --write-subs --write-auto-subs --sub-langs <lang> --skip-download <URL>` and skip transcription entirely.

**Decision tree:**
1. Usable CC/auto captions exist? → Download captions, skip ASR. Done in seconds.
2. No captions (hardcoded subtitles, or none at all)? → Download audio, run ASR.

### Step 2 — Download audio

```bash
TMPDIR=$(mktemp -d /tmp/vid_transcribe.XXXXXX)

# Bilibili: yt-dlp works without cookies for most videos
"$YTDLP" -x \
  --audio-format mp3 --audio-quality 0 \
  -o "$TMPDIR/audio.%(ext)s" "<URL>"

# If Bilibili returns 412 (rare): add --cookies-from-browser chrome

# Podcasts: use the direct enclosure mp3 URL from Step 1 (no yt-dlp needed)
curl -sL "<enclosure_url>" -o "$TMPDIR/episode.mp3" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

# 小宇宙: use the direct m4a URL scraped from the episode page in Step 1
curl -sL "<xyzcdn_m4a_url>" -o "$TMPDIR/episode.m4a" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
# ffmpeg segmenting in Step 3 handles .m4a input the same as .mp3 — just adjust the filename.
```

For very long videos (>30 min), consider `--download-sections "*00:00:00-00:30:00"` to trim, or ask the user which segment they want.

### Step 3 — Transcribe (mlx-whisper on macOS / faster-whisper on Linux)

**CRITICAL — Split audio for long videos.** A single Whisper run on >15 min of audio will hit the Bash timeout (SIGKILL exit 137). Split into ≤10 min chunks:

```bash
# Get duration first
DURATION=$("$FFPROBE" -v quiet -show_entries format=duration -of csv=p=0 "$TMPDIR/audio.mp3")
echo "Duration: ${DURATION}s"

# Split into fixed ~9.5-min chunks (works for any length: 2, 4, 7 chunks...)
# Chunk i starts at i*580 seconds — remember the offset when merging timestamps.
"$FFMPEG" -y -v quiet -i "$TMPDIR/audio.mp3" -f segment -segment_time 580 -c copy "$TMPDIR/part%d.mp3"
ls "$TMPDIR"/part*.mp3
```

**Transcription script** — bundled in the skill at `scripts/transcribe.py`. It auto-selects the engine:
- macOS (Apple Silicon) → `mlx_whisper` (Metal-accelerated)
- Linux / other → `faster-whisper` (CPU, CTranslate2, int8) — **required for cloud/Linux environments**

Copy it into the working dir and run per chunk (same CLI as before):

```bash
cp "<skill_dir>/scripts/transcribe.py" "$TMPDIR/transcribe.py"
# usage: transcribe.py <audio> <output.json> [lang_hint] [model]
```

Run each chunk separately (parallel is fine if memory allows, but sequential is safer):

```bash
"$PYTHON" \
  "$TMPDIR/transcribe.py" "$TMPDIR/part0.mp3" "$TMPDIR/t0.json" "<lang_hint>" 2>&1

"$PYTHON" \
  "$TMPDIR/transcribe.py" "$TMPDIR/part1.mp3" "$TMPDIR/t1.json" "<lang_hint>" 2>&1

# ... repeat for each chunk, then merge with global timestamps:
"$PYTHON" -c "
import json
segs = []
i = 0
while True:
    try:
        with open(f'$TMPDIR/t{i}.json') as f: d = json.load(f)
    except FileNotFoundError:
        break
    off = i * 580
    for s in d.get('segments', []):
        segs.append({'start': s['start'] + off, 'end': s['end'] + off, 'text': s['text'].strip()})
    i += 1
with open('$TMPDIR/merged.json', 'w') as f:
    json.dump(segs, f, ensure_ascii=False, indent=2)
print('Total segments:', len(segs), '| ends at', segs[-1]['end'] if segs else 0, 'sec')
"
```

### Language hints

- Let Whisper auto-detect if you don't know the language (omit `--language`).
- Whisper uses ISO 639-1 codes: `zh` (Chinese), `en` (English), `ja` (Japanese), `bs`/`hr`/`sr` (Bosnian/Croatian/Serbian — mutually intelligible, any works), `ko`, `es`, `fr`, `de`, etc.
- Whisper's auto-detect can misidentify similar languages (e.g. Bosnian vs Croatian vs Serbian). This is fine — they're mutually intelligible and the transcription quality is identical.
- For mixed-language content (e.g. interview in Serbian with English terms), use the dominant language as hint.

### Step 4 — Compile and translate

The raw transcription is in the original language. Compile all JSON segments in order, then:

1. **Read the full transcript** and understand the content structure.
2. **Translate to Chinese** (user's primary language) — organize into a readable interview/conversation format with speaker labels where applicable.
3. **Add timestamps** — group related segments into thematic sections with approximate timestamps.
4. **Do NOT translate word-for-word** — clean up filler words, false starts, and repetition to make it readable while preserving meaning and tone.

### Step 5 — Generate the summary document

Write a Markdown file to the workspace with this structure:

```markdown
# [Video Title]

> **来源**: [URL]
> **原始出处**: [original source if known, e.g. YouTube link from Bilibili description]
> **时长**: [duration] | **语言**: [detected language]
> **转写方式**: Whisper medium（macOS: mlx-whisper / Linux: faster-whisper）+ 中文整理翻译

---

## 一、总结（Executive Summary）

[2-3 paragraph high-level summary of what the video covers]

### 核心观点
- [Key point 1 with bold emphasis on the insight]
- [Key point 2...]
- [Key point 3...]

---

## 二、完整实录（中文整理版）

**[00:00–03:00] Section Title**

> **Speaker A**: [translated content]
>
> **Speaker B**: [translated content]

[Continue through all sections with timestamps]

---

## 三、关键金句（Direct Quotes）

| 时间 | 原文 | 中文 |
|------|------|------|
| 02:15 | "[original language quote]" | [Chinese translation] |

---

*注：[notes on transcription method, language, any caveats]*
```

### Step 6 — Generate WeChat long image (PNG infographic)

After the Markdown document, generate a mobile-friendly vertical PNG summarizing the Executive Summary. Users share these directly in WeChat.

**Template**: `$SKILL_DIR/templates/wechat_longimage_template.html` (the directory containing this SKILL.md, e.g. `~/.workbuddy/skills/video-transcribe-summary/`)

1. Copy the template, replace `{{PLACEHOLDERS}}`: header (tag/title/subtitle/meta), 4-8 cards (one per key point — each needs a title, 2-3 sentence condensed body, and a direct quote), footer (closing quote + attribution + source line).
2. Card color classes rotate through `c-teal / c-amber / c-blue / c-coral / c-purple / c-green`. Keep card body text SHORT — it's a summary card, not the full transcript.
3. Render with headless Chrome, then trim bottom whitespace with PIL:

```bash
# Screenshot (IMPORTANT: --headless=new + --no-sandbox required; old --headless
# fails with "GPU process isn't usable")
"$CHROME" \
  --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
  --hide-scrollbars --window-size=750,4200 \
  --screenshot="$TMPDIR/longimage_raw.png" \
  "file://$TMPDIR/longimage.html"

# Trim bottom whitespace (Pillow is preinstalled in the venv)
"$PYTHON" -c "
from PIL import Image
img = Image.open('$TMPDIR/longimage_raw.png').convert('RGB')
w, h = img.size
px = img.load()
last = 0
for y in range(h - 1, -1, -1):
    if any(not (px[x, y][0] > 248 and px[x, y][1] > 248 and px[x, y][2] > 248)
           for x in range(0, w, 5)):
        last = y
        break
img.crop((0, 0, w, min(h, last + 41))).save(
    '$OUTPUT.png', optimize=True)
"
```

4. Save final PNG to the workspace as `[title]长图.png` and present it together with the Markdown file.

**Design specs** (do not change — tuned for WeChat):
- Width 750px (renders at 2x on phones; text sizes are already 2x-scaled: title 48px, body 25px)
- Vertical stacked cards, left color badge + right content, quote in light callout block
- Max ~8 cards; if more key points, merge related ones

### Step 7 — Present and clean up

1. Save the Markdown file AND the long image PNG to the current workspace: `<workspace>/[title].md` + `<workspace>/[title]长图.png`
2. Call `present_files` with BOTH files in one call.
3. The `$TMPDIR` audio/JSON/HTML files are disposable — leave them; they'll be cleaned by the OS.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| yt-dlp Bilibili 412 error | Add `--cookies-from-browser chrome` (user must be logged into Bilibili in Chrome) |
| Whisper SIGKILL (exit 137) | Audio too long — split into ≤10 min chunks, transcribe separately |
| Model download slow first time | 512MB one-time download. Subsequent runs use cache. This is expected. |
| Whisper misidentifies language | Pass `language` hint explicitly. For BCS languages, `bs` works for all three. |
| Empty Bilibili subtitle API | Normal for hardcoded-subtitle videos. Proceed to audio download + ASR. |
| Apple Podcasts WebFetch returns CN browse page | Expected — region redirect. Use iTunes API lookup + RSS feed path (Step 1). |
| Episode not in iTunes lookup results (only recent episodes returned) | Parse the show's RSS feed directly and grep for the episode title keyword. |
| Podcast enclosure URL returns HTML instead of mp3 | Use `curl -sL` (follow redirects through podtrac/pdst.fm/arttrk chains) and a browser User-Agent. |
| 小宇宙 page has no `media.xyzcdn.net` URL | Page may need JS rendering — retry with a browser User-Agent; or try the RSS feed `https://www.xiaoyuzhoufm.com/podcasts/<PODCAST_ID>/rss` and grep the episode `<enclosure>`. |
| Chrome `--headless` fails "GPU process isn't usable" | Use `--headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage` instead |
| Screenshot image too tall / bottom whitespace | Render at 750x4200 then PIL-trim bottom white rows (script in Step 6) |
| Long image text too small on phone | Never shrink font sizes — 750px wide is 2x phone width; sizes in template are already correct |
| ffprobe not found | Use `ffmpeg -i file 2>&1 | grep Duration` instead |
| Video has multiple parts (B站分集) | Use `--part N` or specify the URL with `?p=N` |

## Performance expectations (Apple M4, 24GB)

| Audio length | Transcription time (medium model) |
|--------------|-----------------------------------|
| 5 min | ~30s |
| 10 min | ~60-90s |
| 18 min (split) | ~2.5 min total (2 chunks) |
| 30 min (split) | ~5 min total (3-4 chunks) |
| 60 min (split) | ~10 min total (6-7 chunks) |

## Model selection

Pass the model name as the 4th CLI arg to `scripts/transcribe.py` (default `medium`).

- **whisper-medium** (default): Best balance of speed/accuracy.
- **whisper-large-v3**: Higher accuracy, slower. For critical accuracy needs.
- **whisper-small**: Faster, less accurate. Use for quick drafts.

Engine-specific model names (auto-handled by the script):
- macOS mlx-whisper: `mlx-community/whisper-<model>` (e.g. `whisper-medium`)
- Linux faster-whisper: plain name (`medium`, `small`, `large-v3`) — CPU int8, downloads from Hugging Face on first run

> **Cloud/Linux environments**: faster-whisper needs outbound network to Hugging Face for the model download. If the machine has no external internet (e.g. internal sandbox), transcription cannot run regardless — report this early and suggest downloading the model elsewhere.

## Notes

- The Bilibili subtitle API (`/x/player/v2`) frequently returns empty `subtitles` arrays, especially for videos with hardcoded (burned-in) Chinese subtitles. This is normal — proceed to audio download.
- Bilibili video descriptions often contain the original YouTube link. Check the description first — if the YouTube original has CC captions, transcribing from YouTube may be easier.
- For videos with background music or noise, Whisper-medium handles it reasonably well, but accuracy drops on overlapping speech.
- Always verify the transcription makes sense contextually before presenting — Whisper can hallucinate on silence or music.
