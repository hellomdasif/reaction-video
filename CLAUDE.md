# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a video composition script designed for automated reaction video generation, typically run within an n8n workflow environment. The script creates vertical (9:16) Instagram-friendly videos by composing:
- A main background video (cropped and optionally mirrored)
- An overlay reaction video (positioned at top)
- Text captions with multi-script support (Hindi/Devanagari, Latin, emojis via Twemoji CDN)
- Optional random insert clips
- Optional outro with crossfade transitions
- Advanced audio mixing (main audio + overlay audio with volume control)

## Core Architecture

### Single Shell Script Design
The entire application is a monolithic POSIX-compliant shell script ([script.sh:1](script.sh#L1)) that orchestrates:
1. **Configuration parsing** - Template variables from n8n webhook ([script.sh:10-66](script.sh#L10-L66))
2. **Python caption generation** - Embedded Python code for image rendering ([script.sh:189-454](script.sh#L189-L454))
3. **FFmpeg pipeline construction** - Dynamic filter_complex assembly ([script.sh:576-769](script.sh#L576-L769))
4. **Audio processing** - Multi-stage audio mixing with tempo adjustment ([script.sh:630-716](script.sh#L630-L716))

### Key Technical Patterns

**Dynamic Filter Construction** ([script.sh:593-603](script.sh#L593-L603))
The script builds FFmpeg filter_complex incrementally using the `append_filter()` function. This allows conditional addition of:
- Base composition (background + overlay + caption)
- Random insert segments with crossfades
- Outro transitions
- Brightness adjustments

**Audio Tempo Chain** ([script.sh:604-628](script.sh#L604-L628))
Speed adjustments are handled by breaking factors > 2.0 or < 0.5 into multiple `atempo` filters (FFmpeg limitation: atempo must be 0.5-2.0). A Python snippet calculates the chain dynamically.

**Multi-Script Caption Rendering** ([script.sh:306-327](script.sh#L306-L327))
Character-level script detection routes rendering to appropriate fonts:
- Hindi/Devanagari: Uses Noto Sans Devanagari
- Emojis: Fetched as images from Twemoji CDN
- Latin: User-specified font or system defaults

**Audio Mixing Strategy** ([script.sh:634-659](script.sh#L634-L659))
When overlay audio is enabled:
1. Main audio gets tempo adjustment (if SPEED_FACTOR != 1.0)
2. Overlay audio gets volume adjustment (1-100% scale)
3. Both mixed with `amix` filter with dropout_transition
4. Result becomes base for random insert audio processing

## Configuration Variables

**Video Processing**
- `SPEED_FACTOR`: Applies to main video + audio (default: 0.9)
- `TARGET_FPS`: Force 30fps for Instagram compatibility
- `BRIGHTNESS`: -1.0 to 1.0 adjustment on final output
- `TRIM_DURATION`: Limit video length in seconds (accounts for speed factor)

**Cropping** ([script.sh:29-38](script.sh#L29-L38))
Independent top/bottom cropping with percentage-based values:
- `CROP_TOP_PERCENT`: Remove from top (default: 20%)
- `CROP_BOTTOM_PERCENT`: Remove from bottom (default: 22%)
- Implemented as single FFmpeg crop filter ([script.sh:540](script.sh#L540))

**Audio Mixing** ([script.sh:26-27](script.sh#L26-L27))
- `OVERLAY_AUDIO_ENABLE`: Preserve overlay video's audio track
- `OVERLAY_AUDIO_VOLUME`: 1-100 scale (converted to 0.01-1.0 for FFmpeg)

**Caption System** ([script.sh:52-62](script.sh#L52-L62))
- `CAPTION_TEXT`: Supports newlines, Hindi, emojis
- `CAPTION_FONT_PATH`: Custom font path (defaults to system fonts)
- `TEXT_BG_ENABLE`: Rounded rectangle backgrounds with opacity
- Position controls: `CAPTION_POS_X_PERCENT`, `CAPTION_POS_Y_PERCENT`

**Advanced Features**
- `OVERLAY_2`: Secondary overlay with crossfade transition
- `RANDOM_INSERT_FILE`: Insert random clip at calculated position ([script.sh:662-716](script.sh#L662-L716))
- `OUTRO_FILE`: End video with crossfade ([script.sh:719-754](script.sh#L719-L754))

## Dependencies

**Required System Tools**
- `ffmpeg` / `ffprobe`: Video processing (must support libx264, aac, xfade filter)
- `python3`: Caption image generation
- POSIX shell (`/bin/sh`): Script execution

**Python Dependencies**
- `PIL` (Pillow): Image manipulation and text rendering
- `urllib.request`: Fetching Twemoji images from CDN

**Font Requirements**
For multi-language support, install:
- Hindi: `fonts-noto-devanagari` or macOS Devanagari Sangam MN
- Latin: Arial Bold, DejaVu Sans Bold, or Liberation Sans Bold
- Emojis: Rendered via Twemoji CDN (no local fonts needed)

## Common Operations

**Testing the Script**
The script expects n8n template variables. For testing, replace template strings with actual values:
```bash
# Edit these lines (10-11, 56, 65):
INPUT_URL="/path/to/background_video.mp4"
OVERLAY_FILE="/path/to/overlay_video.mp4"
CAPTION_TEXT="Your caption text here"
OUT_FILE="/path/to/output/result.mp4"
```

**Running the Script**
```bash
sh script.sh
```
Progress is output to stderr, final filename to stdout.

**Debugging Filter Complex**
The script prints the full filter_complex before execution ([script.sh:809-812](script.sh#L809-L812)). To debug:
1. Run script and capture stderr
2. Extract filter_complex from debug output
3. Test isolated with: `ffmpeg -filter_complex "..." -f null -`

**Audio Troubleshooting**
Check if overlay has audio:
```bash
ffprobe -v error -select_streams a:0 -show_entries stream=codec_type overlay.mp4
```
The script auto-detects and warns if overlay audio is missing ([script.sh:114-118](script.sh#L114-L118)).

## Critical Implementation Details

**Speed Factor Math** ([script.sh:465-485](script.sh#L465-L485))
- `INPUT_READ_DURATION`: Amount of video to read from source files (scaled by speed factor)
- `EFFECTIVE_DURATION`: Final output duration after speed adjustment
- Formula: `EFFECTIVE_DURATION = INPUT_READ_DURATION / SPEED_FACTOR`

**Input Index Management** ([script.sh:553-574](script.sh#L553-L574))
FFmpeg input indices must be tracked carefully as they shift based on enabled features:
- Input 0: Main background video (always present)
- Input 1: Overlay video (always present)
- Input 2: Caption PNG (if CAPTION_ENABLE=true)
- Input N: Random insert (if provided)
- Input N+1: Outro (if provided)

**Rotation Handling** ([script.sh:488-493](script.sh#L488-L493))
Checks stream metadata for rotation tag (90/270 degrees) and applies transpose filter before other processing.

**Temporary File Cleanup** ([script.sh:819-821](script.sh#L819-L821))
On success, removes:
- Caption PNG (if generated)
- Merged overlay temp file (if OVERLAY_2 used)
- Other intermediate files

## Workflow Integration

This script is designed for n8n workflow automation:
- **Webhook input**: Receives video paths and configuration via POST body
- **Template variables**: Mustache-style templates (`{{ $node["Webhook"].json.body.filename }}`)
- **Output convention**: Always outputs to `root_dir/folder/output/filename`

When modifying for standalone use, replace all template variables with environment variables or CLI arguments.
