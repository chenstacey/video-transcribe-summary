#!/usr/bin/env python3
"""Cross-platform Whisper transcription for video-transcribe-summary.

Usage:
    transcribe.py <audio> <output.json> [lang_hint] [model]

Engine selection (automatic):
  - macOS on Apple Silicon (arm64)  -> mlx_whisper   (fast, GPU/ANE accelerated)
  - anything else (Linux x86/ARM…)  -> faster-whisper (CPU, CTranslate2, int8)

Output JSON is normalized to mlx_whisper's shape:
    {"segments": [{"start": float, "end": float, "text": str}, ...]}

so the timestamp-merge step in SKILL.md works identically on both engines.

Notes:
  - faster-whisper downloads models from Hugging Face on first run
    (e.g. medium -> ~1.5 GB under ~/.cache/huggingface).
  - If the machine has no internet at all, both engines fail at model
    download — report that clearly instead of retrying forever.
"""
import json
import platform
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    audio_path = sys.argv[1]
    output_path = sys.argv[2]
    lang = sys.argv[3] if len(sys.argv) > 3 else None  # e.g. "bs", "zh", "en", "ja"
    model = sys.argv[4] if len(sys.argv) > 4 else "medium"

    is_apple_silicon = platform.system() == "Darwin" and platform.machine() == "arm64"

    if is_apple_silicon:
        import mlx_whisper

        kwargs = {
            "path_or_hf_repo": f"mlx-community/whisper-{model}",
            "word_timestamps": False,
            "verbose": False,
        }
        if lang:
            kwargs["language"] = lang
        result = mlx_whisper.transcribe(audio_path, **kwargs)
        segments = [
            {
                "start": seg.get("start", 0.0),
                "end": seg.get("end", 0.0),
                "text": seg.get("text", "").strip(),
            }
            for seg in result.get("segments", [])
        ]
        detected_lang = result.get("language", "?")
    else:
        from faster_whisper import WhisperModel

        whisper = WhisperModel(model, device="cpu", compute_type="int8")
        seg_iter, info = whisper.transcribe(
            audio_path, language=lang, word_timestamps=False
        )
        segments = [
            {"start": round(s.start, 3), "end": round(s.end, 3), "text": s.text.strip()}
            for s in seg_iter
        ]
        detected_lang = info.language if info.language else "?"

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"segments": segments}, f, ensure_ascii=False, indent=2)

    # Human-readable preview (same format as the original mlx-only script)
    for seg in segments:
        m1, s1 = divmod(int(seg["start"]), 60)
        m2, s2 = divmod(int(seg["end"]), 60)
        print(f"[{m1:02d}:{s1:02d} - {m2:02d}:{s2:02d}] {seg['text']}")

    print(f"\nDetected language: {detected_lang}")
    print(f"Saved {len(segments)} segments -> {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
