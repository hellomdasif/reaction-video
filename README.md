# Reaction Video Composer

Shell-based workflow for generating vertical reaction videos with FFmpeg and Pillow.  
Automates background cropping, green-screen overlays, captions (Hindi/English/emoji), audio mixing, optional random inserts, and outros. Designed for n8n automation (`script.sh`) with a standalone testing harness (`test_script.sh`).

---

## Features

- **Green-screen overlay** with chroma key controls (`OVERLAY_CHROMA_KEY_*`).
- **Side-trim support** for overlays via auto-detection or manual overrides.
- **Caption generator** using Pillow with Devanagari + Latin fonts and emoji fallback (Twemoji CDN).
- **Dynamic FFmpeg graph** adding background crop, speed/brightness tweaks, optional random insert / outro segments.
- **Audio mixing** merges base audio, overlay audio (volume-controlled), random inserts, and outros with tempo correction.

---

## Requirements

| Dependency | Notes |
|------------|-------|
| macOS / Linux shell (`/bin/sh`) | Script is POSIX-compliant. |
| `ffmpeg` + `ffprobe` | Must support `chromakey`, `xfade`, `amix`, `libx264`, `aac`. |
| `python3` + `pip` | Caption renderer embeds Python. |
| Python packages | `Pillow` (install manually). |
| Fonts | Devanagari + emoji fonts included under `Noto_Sans_Devanagari/` and `Noto_Color_Emoji/`. |

Install Python deps (recommend virtualenv):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install pillow
```

---

## Repository Layout

```
Reaction_video/
├── script.sh          # Production script (templated for n8n variables)
├── test_script.sh     # Standalone test harness with local paths
├── overlay/           # Example overlays (e.g., kabir.mp4, asif.mp4)
├── input.mp4          # Sample background video
├── output/            # Rendered outputs, debug frames, captions
├── Noto_*             # Local font bundles (Devanagari + emoji)
└── OVERLAY_CONFIG.md  # Overlay configuration reference
```

`CLAUDE.md` documents architectural details for other tooling; leave it untouched when editing README.

---

## Quick Start (Test Harness)

1. Activate your virtual environment and install Pillow (see Requirements).
2. Set overlay/background assets in `test_script.sh` (defaults sample `input.mp4` + `overlay/kabir.mp4`).
3. Run:

   ```bash
   source .venv/bin/activate
   sh test_script.sh
   ```

4. Output file: `output/test_output.mp4`. Captions & temp files land in `output/`.

> Tip: For one-off runs with custom overlay trim values, override variables inline:
> ```bash
> source .venv/bin/activate
> OVERLAY_EDGE_TRIM_LEFT=320 OVERLAY_EDGE_TRIM_RIGHT=320 sh test_script.sh
> ```

---

## Auto & Manual Overlay Trimming

### Auto Detection (default)

`test_script.sh` supports automatic matting of black bars via:

```bash
OVERLAY_EDGE_TRIM_LEFT="auto"
OVERLAY_EDGE_TRIM_RIGHT="auto"
OVERLAY_AUTO_TRIM_THRESHOLD=25   # Treat columns brighter than threshold as content.
OVERLAY_AUTO_TRIM_MARGIN=6       # Extra pixels removed beyond detected edge.
```

- Increase `OVERLAY_AUTO_TRIM_THRESHOLD` (e.g., `60`) if dim borders are still visible.
- Raise `OVERLAY_AUTO_TRIM_MARGIN` to shave additional pixels after detection.

### Manual Override

Set numeric values to crop fixed columns before chroma keying:

```bash
OVERLAY_EDGE_TRIM=""
OVERLAY_EDGE_TRIM_LEFT=320   # px to remove from left edge
OVERLAY_EDGE_TRIM_RIGHT=320  # px to remove from right edge
```

Manual values override auto-detection. The script echoes applied trims for verification (`Overlay edge trim: left=320px right=320px`).

---

## Key Parameters (excerpt)

| Variable | Purpose |
|----------|---------|
| `OVERLAY_POSITION` | `top`, `bottom`, `center`, or `custom` (with `OVERLAY_CUSTOM_{X,Y}`). |
| `OVERLAY_CHROMA_KEY_SIMILARITY/BLEND` | Tune green-screen aggressiveness. |
| `CAPTION_TEXT` | Supports multiline Hindi + English + emoji. |
| `CAPTION_FONT_PATH` | Default Arial Bold; falls back to bundled Noto fonts. |
| `RANDOM_INSERT_FILE` | Optional mid-roll clip; set value to enable. |
| `OUTRO_FILE` | Optional outro crossfade. |
| `SPEED_FACTOR` | Alters playback speed + audio tempo chain. |

Full configuration documented inline within `test_script.sh` and `OVERLAY_CONFIG.md`.

---

## Production Workflow (n8n / `script.sh`)

`script.sh` mirrors the test harness but uses templated variables (`{{ $node[...] }}`) for n8n webhook payloads. To deploy:

- Copy runtime assets (fonts, overlays) to your server/workflow environment.
- Ensure FFmpeg + Python + Pillow are installed on the worker.
- Set environment variables or substitute template values before execution.

---

## Development Tips

- **Debug filters:** The script prints the full FFmpeg `filter_complex` before running. Copy it to experiment directly with `ffmpeg -filter_complex '...' -f null -`.
- **Captions:** If emojis fail to render locally, they fall back to Twemoji PNGs and inherit alpha transparency.
- **Testing new overlays:** Use the trimming overrides and adjust chroma key similarity (`0.10 – 0.18` usually works). Inspect intermediate files in `output/` for diagnostics.

---

## Version Control & Pushing Changes

1. Stage your updates (avoid committing large binaries such as `input.mp4`, `.venv/`, etc.):

   ```bash
   git add README.md test_script.sh script.sh
   ```

2. Commit with a descriptive message:

   ```bash
   git commit -m "docs: add reaction video README and overlay trimming guidance"
   ```

3. Push to the remote repository:

   ```bash
   git push
   ```

If large media/fonts should not be tracked, add them to `.gitignore` before committing.

---

## License

No explicit license specified. Add one if you intend to distribute the fonts or sample media.

