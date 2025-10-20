#!/bin/sh
set -eu

# Test version of the video composition script
# Uses local test files instead of n8n webhook variables
#
# OVERLAY CONFIGURATION EXAMPLES:
#
# Example 1: Green screen overlay at bottom
#   OVERLAY_POSITION="bottom"
#   OVERLAY_CHROMA_KEY_ENABLE=true
#   OVERLAY_CHROMA_KEY_COLOR="green"
#   OVERLAY_OPACITY=100
#
# Example 2: Small overlay at custom position
#   OVERLAY_POSITION="custom"
#   OVERLAY_CUSTOM_X=50
#   OVERLAY_CUSTOM_Y=1400
#   OVERLAY_SCALE_PERCENT=50
#   OVERLAY_OPACITY=80
#
# Example 3: Centered semi-transparent overlay
#   OVERLAY_POSITION="center"
#   OVERLAY_OPACITY=70
#   OVERLAY_WIDTH=800
#   OVERLAY_HEIGHT=600
#
# Supported formats: MP4, MOV, AVI, GIF (animated GIF supported)

# ---------------- CONFIG ----------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT_URL="${SCRIPT_DIR}/input.mp4"
OVERLAY_FILE="${SCRIPT_DIR}/overlay/kabir.mp4"  # Using MP4 with green screen
OVERLAY_2=""
OVERLAY_2_LENGTH_SECONDS=""
OVERLAY_2_START_SEC="0"
OVERLAY_TRANSITION_DURATION="0.6"

TRIM_DURATION="180"  # Reduced to 10 seconds for quick testing
OUTRO_FILE=""
OUTRO_TRANSITION_DURATION="0.5"

# RANDOM INSERT with AUDIO support (leave empty to disable)
RANDOM_INSERT_FILE=""
RANDOM_INSERT_TRANSITION="0.2"

# NEW: Overlay audio settings
OVERLAY_AUDIO_ENABLE=true        # Enable overlay audio preservation
OVERLAY_AUDIO_VOLUME=80          # Volume level 1-100 (100 = original, 50 = half)

# ========== OVERLAY POSITIONING & SIZING ==========
# Position: "top", "bottom", "center", "custom"
OVERLAY_POSITION="bottom"
# For custom position: X and Y coordinates (0-1920 for Y, 0-1080 for X)
OVERLAY_CUSTOM_X=0
OVERLAY_CUSTOM_Y=1200
# Overlay size settings
OVERLAY_WIDTH="100%"               # Width in pixels (max 1080 for full width)
OVERLAY_HEIGHT="50%"             # Height in pixels (leave empty for auto based on aspect ratio)
OVERLAY_SCALE_PERCENT=100        # Scale as percentage (100 = original size, 50 = half size)
OVERLAY_LOOP_ENABLE=true         # Repeat overlay when shorter than main

# Overlay effects
OVERLAY_OPACITY=100              # Opacity 0-100 (100 = fully opaque, 0 = transparent)
OVERLAY_CHROMA_KEY_ENABLE=true   # Enable green screen removal
OVERLAY_CHROMA_KEY_COLOR="green" # Using "green" keyword for chromakey filter
OVERLAY_CHROMA_KEY_SIMILARITY=0.12 # 0.0-1.0, tuned to keep subject visible
OVERLAY_CHROMA_KEY_BLEND=0.05     # 0.0-1.0, mild blend to soften edges
# Optional manual edge trims (pixels). Set to >0 to remove borders after chroma key.
OVERLAY_EDGE_TRIM="LEFT/RIGHT"             # deprecated: use LEFT/RIGHT below
OVERLAY_EDGE_TRIM_LEFT=""    # Pixels to crop from left edge or "auto"
OVERLAY_EDGE_TRIM_RIGHT=""   # Pixels to crop from right edge or "auto"
OVERLAY_AUTO_TRIM_THRESHOLD=25   # Brightness threshold for auto edge trim (0-255)
OVERLAY_AUTO_TRIM_MARGIN=6       # Extra pixels to trim beyond detected edge (safety buffer)
OVERLAY_SPEED_FACTOR="4.0"        # Overlay-only speed multiplier (1.0 = original)

# ========== END OVERLAY SETTINGS ==========

CANVAS_WIDTH=1080
CANVAS_HEIGHT=1920

# Crop settings: enable independent top/bottom cropping
CROP_ENABLE=true
CROP_TOP_ENABLE=true
CROP_TOP_PERCENT=15
CROP_BOTTOM_ENABLE=true
CROP_BOTTOM_PERCENT=30

MAIN_POSITION="top"           # Position main background: top, bottom, center, or custom
MAIN_CUSTOM_Y=0                # Used when MAIN_POSITION="custom"

# Default crop values
DEFAULT_CROP_TOP_PERCENT=10
DEFAULT_CROP_BOTTOM_PERCENT=20

# Mirror/flip main video horizontally
MIRROR_ENABLE=false

# Speed factor (applies to composed main video + main audio)
SPEED_FACTOR="2"

# Brightness adjustment for final output (-1.0 .. 1.0)
BRIGHTNESS="0.1"

# Force Instagram-friendly fps
TARGET_FPS=30

CAPTION_ENABLE=false
CAPTION_FONT_PATH="/System/Library/Fonts/Supplemental/Arial Bold.ttf"  # macOS default
CAPTION_POS_X_PERCENT=50
CAPTION_POS_Y_PERCENT=35
CAPTION_TEXT="यह एक टेस्ट है 🎬
Test Caption"  # Hindi + emoji test
CAPTION_FONT_SIZE=45
CAPTION_FONT_COLOR="white"
TEXT_BG_ENABLE=true
TEXT_BG_COLOR="black"
TEXT_BG_OPACITY=150
TEXT_BG_PADDING=25

# ---------------- OUTPUT (FIXED) ----------------
OUT_FILE="${SCRIPT_DIR}/output/test_output.mp4"
mkdir -p "$(dirname "$OUT_FILE")"

OUT_DIR="$(dirname "$OUT_FILE")"
CAPTION_PNG="${OUT_DIR}/caption_image.png"
MERGED_OVERLAY_TMP="${OUT_DIR}/overlay_merged_$(date +%s)_$$.mp4"
COMPOSED_MAIN_TMP="${OUT_DIR}/main_composed_$(date +%s)_$$.mp4"

FFMPEG_TIMEOUT="5m"
# --------------- end config --------------

echo "=== Start: enhanced video composition with overlay audio support ===" >&2

# Validate overlay audio volume
if [ "$OVERLAY_AUDIO_ENABLE" = "true" ]; then
  if [ -z "${OVERLAY_AUDIO_VOLUME:-}" ] || [ "$OVERLAY_AUDIO_VOLUME" -lt 1 ] || [ "$OVERLAY_AUDIO_VOLUME" -gt 100 ]; then
    echo "WARN: Invalid OVERLAY_AUDIO_VOLUME ($OVERLAY_AUDIO_VOLUME), using 100" >&2
    OVERLAY_AUDIO_VOLUME=100
  fi
  # Convert 1-100 scale to 0.01-1.0 for FFmpeg volume filter
  OVERLAY_VOLUME_FLOAT=$(awk -v v="$OVERLAY_AUDIO_VOLUME" 'BEGIN{ printf("%.2f", v/100.0) }')
  echo "Overlay audio: ENABLED at ${OVERLAY_AUDIO_VOLUME}% volume (${OVERLAY_VOLUME_FLOAT})" >&2
else
  echo "Overlay audio: DISABLED" >&2
fi

# Resolve INPUT_FILE from INPUT_URL
INPUT_FILE="$INPUT_URL"

echo "Main background: $INPUT_FILE" >&2
echo "Overlay primary: $OVERLAY_FILE" >&2
[ -n "$OVERLAY_2" ] && echo "Overlay secondary: $OVERLAY_2" >&2
[ -n "$OUTRO_FILE" ] && echo "Outro file: $OUTRO_FILE" >&2
[ -n "$RANDOM_INSERT_FILE" ] && echo "Random insert file: $RANDOM_INSERT_FILE" >&2
[ -n "$TRIM_DURATION" ] && echo "Trim duration: $TRIM_DURATION seconds" >&2
echo "SPEED_FACTOR: $SPEED_FACTOR, BRIGHTNESS: $BRIGHTNESS, TARGET_FPS: $TARGET_FPS" >&2

# Helper functions
probe_duration() { ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null || printf ""; }
probe_resolution() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$1" 2>/dev/null || printf ""; }
probe_framerate() { ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$1" 2>/dev/null || printf ""; }
has_audio() { ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of default=nw=1:nk=1 "$1" 2>/dev/null | grep -q "audio" && echo "yes" || echo "no"; }

# Validate files
if [ ! -f "$INPUT_FILE" ]; then echo "ERR: main input missing: $INPUT_FILE" >&2; exit 1; fi
if [ ! -f "$OVERLAY_FILE" ]; then echo "ERR: overlay primary missing: $OVERLAY_FILE" >&2; exit 1; fi
if [ -n "$OVERLAY_2" ] && [ ! -f "$OVERLAY_2" ]; then echo "ERR: overlay secondary missing: $OVERLAY_2" >&2; exit 1; fi

# Check if overlay has audio
OVERLAY_HAS_AUDIO=$(has_audio "$OVERLAY_FILE")
if [ "$OVERLAY_AUDIO_ENABLE" = "true" ] && [ "$OVERLAY_HAS_AUDIO" = "no" ]; then
  echo "WARN: Overlay audio enabled but overlay file has no audio stream. Disabling overlay audio." >&2
  OVERLAY_AUDIO_ENABLE=false
fi

if [ -n "$OUTRO_FILE" ] && [ ! -f "$OUTRO_FILE" ]; then
  echo "WARN: outro path provided but file not found: $OUTRO_FILE — skipping outro." >&2
  OUTRO_FILE=""
fi

if [ -n "$RANDOM_INSERT_FILE" ] && [ ! -f "$RANDOM_INSERT_FILE" ]; then
  echo "ERR: random insert file missing: $RANDOM_INSERT_FILE" >&2; exit 1;
fi

if [ -z "${OUTRO_FILE:-}" ]; then
  OUTRO_FILE=""
  OUTRO_INDEX=""
  echo "No valid outro — outro processing disabled." >&2
fi

# Probe overlay durations
OV1_DUR=$(probe_duration "$OVERLAY_FILE"); OV1_DUR=${OV1_DUR:-0}; OV1_DUR=$(awk -v v="$OV1_DUR" 'BEGIN{printf("%.3f", v+0)}')
echo "Overlay1 duration: $OV1_DUR" >&2
if [ -n "$OVERLAY_2" ]; then
  OV2_DUR=$(probe_duration "$OVERLAY_2"); OV2_DUR=${OV2_DUR:-0}; OV2_DUR=$(awk -v v="$OV2_DUR" 'BEGIN{printf("%.3f", v+0)}')
  echo "Overlay2 duration: $OV2_DUR" >&2
fi

# Determine overlay resolution and FPS
IN_RES=$(probe_resolution "$OVERLAY_FILE" || true)
if [ -n "$IN_RES" ]; then
  O_W=$(printf "%s" "$IN_RES" | awk -Fx '{print $1}')
  O_H=$(printf "%s" "$IN_RES" | awk -Fx '{print $2}')
else
  O_W=720; O_H=1280
fi
FPS_RAW=$(probe_framerate "$OVERLAY_FILE" || true)
echo "Overlay native resolution: ${O_W}x${O_H} native-fps:${FPS_RAW} -> using TARGET_FPS=${TARGET_FPS}" >&2
if [ "$OVERLAY_LOOP_ENABLE" = "true" ]; then
  echo "Overlay looping: enabled" >&2
else
  echo "Overlay looping: disabled" >&2
fi

# Auto-detect edge trims if requested
if { [ "${OVERLAY_EDGE_TRIM_LEFT}" = "auto" ] || [ "${OVERLAY_EDGE_TRIM_RIGHT}" = "auto" ]; }; then
  echo "Auto-detecting overlay side trims..." >&2
  export OVERLAY_FILE OVERLAY_FINAL_WIDTH OVERLAY_AUTO_TRIM_THRESHOLD OVERLAY_AUTO_TRIM_MARGIN OV1_DUR
  AUTO_TRIMS=$(python3 - <<'PY'
import os
import subprocess
import tempfile
from PIL import Image

overlay = os.environ["OVERLAY_FILE"]
width = int(os.environ.get("OVERLAY_FINAL_WIDTH", "0") or "0")
threshold = int(os.environ.get("OVERLAY_AUTO_TRIM_THRESHOLD", "25"))
margin = int(os.environ.get("OVERLAY_AUTO_TRIM_MARGIN", "0") or "0")
duration = float(os.environ.get("OV1_DUR", "0") or "0")

if width <= 0:
    print("0,0")
    raise SystemExit

def analyze_frame(path):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    def column_avg(x):
        total = 0
        for y in range(h):
            r, g, b = img.getpixel((x, y))
            total += r + g + b
        return total / (3 * h)
    left = 0
    while left < w:
        if column_avg(left) > threshold:
            break
        left += 1
    right = 0
    while right < (w - left):
        if column_avg(w - 1 - right) > threshold:
            break
        right += 1
    img.close()
    return left, right

def extract_frame(time_pos):
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name
    cmd = [
        "ffmpeg", "-v", "error", "-y",
        "-ss", f"{max(time_pos, 0):.3f}",
        "-i", overlay,
        "-vf", f"scale={width}:-1",
        "-frames:v", "1",
        tmp_path
    ]
    subprocess.run(cmd, check=True)
    return tmp_path

sample_times = [0.0]
if duration > 1.0:
    sample_times.append(duration * 0.5)
    sample_times.append(max(duration - 0.5, 0.0))

max_left = 0
max_right = 0
temp_paths = []

try:
    for t in sample_times:
        path = extract_frame(t)
        temp_paths.append(path)
        left, right = analyze_frame(path)
        if left > max_left:
            max_left = left
        if right > max_right:
            max_right = right
finally:
    for p in temp_paths:
        if p and os.path.exists(p):
            os.unlink(p)

left = max_left + margin
right = max_right + margin

with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
    tmp_path = tmp.name
cmd = [
    "ffmpeg", "-v", "error", "-y",
    "-i", overlay,
    "-vf", f"scale={width}:-1",
    "-frames:v", "1",
    tmp_path
]
subprocess.run(cmd, check=True)
img = Image.open(tmp_path)
w = img.width
img.close()
os.unlink(tmp_path)

if left + right >= w:
    keep = max(w - 2, 1)
    ratio = left / (left + right) if (left + right) else 0.5
    left = int(keep * ratio)
    right = keep - left

print(f"{left},{right}")
PY
)
  AUTO_LEFT=$(printf "%s" "$AUTO_TRIMS" | cut -d',' -f1)
  AUTO_RIGHT=$(printf "%s" "$AUTO_TRIMS" | cut -d',' -f2)
  echo "Auto trim detected: left=${AUTO_LEFT}px right=${AUTO_RIGHT}px" >&2
  [ "${OVERLAY_EDGE_TRIM_LEFT}" = "auto" ] && OVERLAY_EDGE_TRIM_LEFT="$AUTO_LEFT"
  [ "${OVERLAY_EDGE_TRIM_RIGHT}" = "auto" ] && OVERLAY_EDGE_TRIM_RIGHT="$AUTO_RIGHT"
fi

# Build overlay effects filter chain
OVERLAY_PRE_EFFECTS=""
OVERLAY_EFFECTS=""

# Chroma key (green screen removal)
if [ "$OVERLAY_CHROMA_KEY_ENABLE" = "true" ]; then
  echo "Chroma key enabled: removing ${OVERLAY_CHROMA_KEY_COLOR}" >&2
  # Use chromakey filter for better green screen removal
OVERLAY_EFFECTS="${OVERLAY_EFFECTS}format=yuva420p,chromakey=${OVERLAY_CHROMA_KEY_COLOR}:${OVERLAY_CHROMA_KEY_SIMILARITY}:${OVERLAY_CHROMA_KEY_BLEND},"
fi

# Optional edge trim to remove matte seams
OVERLAY_TRIM_LEFT="${OVERLAY_EDGE_TRIM_LEFT:-}"
OVERLAY_TRIM_RIGHT="${OVERLAY_EDGE_TRIM_RIGHT:-}"

# Backward compatibility if legacy OVERLAY_EDGE_TRIM is set
if [ -n "${OVERLAY_EDGE_TRIM:-}" ]; then
  case "$OVERLAY_EDGE_TRIM" in
    ''|*[!0-9]*)
      echo "WARN: OVERLAY_EDGE_TRIM is not a number (${OVERLAY_EDGE_TRIM}) — ignoring legacy setting." >&2
      ;;
    *)
      OVERLAY_TRIM_LEFT="$OVERLAY_EDGE_TRIM"
      OVERLAY_TRIM_RIGHT="$OVERLAY_EDGE_TRIM"
      ;;
  esac
fi

validate_trim() {
  local value="$1"
  case "$value" in
    ''|*[!0-9]*)
      echo ""
      ;;
    *)
      echo "$value"
      ;;
  esac
}

OVERLAY_TRIM_LEFT=$(validate_trim "$OVERLAY_TRIM_LEFT")
OVERLAY_TRIM_RIGHT=$(validate_trim "$OVERLAY_TRIM_RIGHT")

if [ -n "$OVERLAY_TRIM_LEFT" ] || [ -n "$OVERLAY_TRIM_RIGHT" ]; then
  LEFT_VAL=${OVERLAY_TRIM_LEFT:-0}
  RIGHT_VAL=${OVERLAY_TRIM_RIGHT:-0}
  if [ "$LEFT_VAL" -gt 0 ] || [ "$RIGHT_VAL" -gt 0 ]; then
    echo "Overlay edge trim: left=${LEFT_VAL}px right=${RIGHT_VAL}px" >&2
    OVERLAY_PRE_EFFECTS="${OVERLAY_PRE_EFFECTS}crop=in_w-${LEFT_VAL}-${RIGHT_VAL}:in_h:${LEFT_VAL}:0,"
  fi
fi

# Opacity/transparency
if [ "$OVERLAY_OPACITY" -lt 100 ]; then
  OPACITY_VALUE=$(awk -v o="$OVERLAY_OPACITY" 'BEGIN{printf("%.2f", o/100.0)}')
  echo "Overlay opacity: ${OVERLAY_OPACITY}% (${OPACITY_VALUE})" >&2
  OVERLAY_EFFECTS="${OVERLAY_EFFECTS}format=yuva420p,colorchannelmixer=aa=${OPACITY_VALUE},"
fi

echo "Overlay effects chain: ${OVERLAY_EFFECTS:-none}" >&2
# ========== END overlay calculations ==========

# Merge overlays if needed (VIDEO + AUDIO)
if [ -z "$OVERLAY_2" ]; then
  echo "No overlay2 provided — using overlay primary as-is." >&2
  MERGED_OVERLAY="$OVERLAY_FILE"
else
  if [ -n "$OVERLAY_2_LENGTH_SECONDS" ]; then
    OVERLAY_2_LENGTH_SECONDS=$(awk -v v="$OVERLAY_2_LENGTH_SECONDS" 'BEGIN{printf("%.3f", v+0)}')
    FIRST_END_SEC=$(awk -v d="$OV1_DUR" -v s="$OVERLAY_2_LENGTH_SECONDS" 'BEGIN{printf("%.3f", d - s)}')
  else
    FIRST_END_SEC=$(awk -v d="$OV1_DUR" 'BEGIN{printf("%.3f", d*0.70)}')
  fi

  TRANS=$(awk -v v="$OVERLAY_TRANSITION_DURATION" 'BEGIN{printf("%.3f", v+0)}')
  OFFSET=$(awk -v f="$FIRST_END_SEC" -v t="$TRANS" 'BEGIN{printf("%.3f", f - t)}')

  # Merge video AND audio
  ffmpeg -y -hide_banner -loglevel error \
    -i "$OVERLAY_FILE" -i "$OVERLAY_2" \
    -filter_complex "\
[0:v]trim=start=0:end=${FIRST_END_SEC},setpts=PTS-STARTPTS,scale=${O_W}:${O_H},fps=${TARGET_FPS},setsar=1,format=yuv420p[v0]; \
[1:v]trim=start=${OVERLAY_2_START_SEC},setpts=PTS-STARTPTS,scale=${O_W}:${O_H},fps=${TARGET_FPS},setsar=1,format=yuv420p[v1]; \
[v0][v1]xfade=transition=fade:duration=${TRANS}:offset=${OFFSET}[vxf]; \
[0:a]atrim=start=0:end=${FIRST_END_SEC},asetpts=PTS-STARTPTS[a0]; \
[1:a]atrim=start=${OVERLAY_2_START_SEC},asetpts=PTS-STARTPTS[a1]; \
[a0][a1]acrossfade=d=${TRANS}:o=${OFFSET}[axf]" \
    -map "[vxf]" -map "[axf]" -c:v libx264 -crf 18 -preset veryfast -c:a aac -b:a 192k -movflags +faststart \
    "$MERGED_OVERLAY_TMP"

  MERGED_OVERLAY="$MERGED_OVERLAY_TMP"
fi

# Generate caption if enabled
if [ "$CAPTION_ENABLE" = "true" ]; then
  rm -f "${CAPTION_PNG}" || true
  export CAPTION_PNG CAPTION_TEXT CAPTION_FONT_PATH CAPTION_FONT_SIZE CAPTION_FONT_COLOR CAPTION_POS_X_PERCENT CAPTION_POS_Y_PERCENT TEXT_BG_ENABLE TEXT_BG_COLOR TEXT_BG_OPACITY TEXT_BG_PADDING SCRIPT_DIR
  python3 - <<'PY' 1>&2
import os
import re
import sys
from PIL import Image, ImageDraw, ImageFont
import urllib.request
import io

SCRIPT_DIR = os.environ.get("SCRIPT_DIR", "")

# Emoji rendering using Twemoji PNG images
def get_emoji_image(emoji_char, size):
    """Download and return emoji image from Twemoji CDN"""
    try:
        # Get Unicode codepoint(s) for the emoji
        codepoints = '-'.join(f'{ord(c):x}' for c in emoji_char)
        # Twemoji CDN URL (72x72 PNG)
        url = f'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/{codepoints}.png'

        with urllib.request.urlopen(url, timeout=3) as response:
            img_data = response.read()
            emoji_img = Image.open(io.BytesIO(img_data)).convert("RGBA")
            # Resize to match font size
            emoji_img = emoji_img.resize((size, size), Image.Resampling.LANCZOS)
            return emoji_img
    except Exception as e:
        print(f"Could not fetch emoji {emoji_char} ({codepoints}): {e}", file=sys.stderr, flush=True)
        return None

out_path = os.environ["CAPTION_PNG"]
text = os.environ.get("CAPTION_TEXT", "")
font_path = os.environ.get("CAPTION_FONT_PATH", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
try:
    font_size = int(os.environ.get("CAPTION_FONT_SIZE", "64"))
except Exception:
    font_size = 64
font_color = os.environ.get("CAPTION_FONT_COLOR", "white")
try:
    pos_x_pct = int(os.environ.get("CAPTION_POS_X_PERCENT", "50"))
except Exception:
    pos_x_pct = 50
try:
    pos_y_pct = int(os.environ.get("CAPTION_POS_Y_PERCENT", "50"))
except Exception:
    pos_y_pct = 50
bg_enable = os.environ.get("TEXT_BG_ENABLE", "true").lower() == 'true'
try:
    bg_opacity = int(os.environ.get("TEXT_BG_OPACITY", "150"))
except Exception:
    bg_opacity = 150
try:
    bg_padding = int(os.environ.get("TEXT_BG_PADDING", "20"))
except Exception:
    bg_padding = 20

canvas_w, canvas_h = 1080, 1920

# Font loading with multi-script support
def load_font(path, size):
    """Try to load a font, return None if failed"""
    try:
        font = ImageFont.truetype(path, size)
        # Test if font can actually render (some emoji fonts need SVG support)
        test_draw = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
        try:
            test_draw.textbbox((0, 0), "A", font=font)
            return font
        except (OSError, RuntimeError):
            # Font loaded but can't render (likely SVG-based emoji font)
            print(f"WARNING: {path} requires SVG support, skipping", flush=True)
            return None
    except Exception:
        return None

# Define font candidates for different scripts
hindi_font_paths = [
    os.path.join(SCRIPT_DIR, "Noto_Sans_Devanagari", "static", "NotoSansDevanagari-Bold.ttf"),
    os.path.join(SCRIPT_DIR, "Noto_Sans_Devanagari", "NotoSansDevanagari-VariableFont_wdth,wght.ttf"),
    "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansDevanagari.ttf",
    "/System/Library/Fonts/Devanagari Sangam MN.ttc",
    "/usr/share/fonts/truetype/lohit-devanagari/Lohit-Devanagari.ttf",
    "/usr/share/fonts/truetype/fonts-noto-devanagari/NotoSansDevanagari-Bold.ttf"
]

latin_font_paths = [
    font_path,  # User-specified font
    os.path.join(SCRIPT_DIR, "Noto_Sans_Devanagari", "static", "NotoSansDevanagari-Regular.ttf"),
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
]

emoji_font_paths = [
    os.path.join(SCRIPT_DIR, "Noto_Color_Emoji", "NotoColorEmoji-Regular.ttf"),
    "/System/Library/Fonts/Apple Color Emoji.ttc"
]

# Load fonts
latin_font = None
for p in latin_font_paths:
    if os.path.isfile(p):
        latin_font = load_font(p, font_size)
        if latin_font:
            break

hindi_font = None
for p in hindi_font_paths:
    if os.path.isfile(p):
        hindi_font = load_font(p, font_size)
        if hindi_font:
            print(f"Loaded Hindi font: {p}", flush=True)
            break

def supports_color_glyphs(font):
    """Detect if a font actually renders emoji glyphs with non-zero alpha."""
    if font is None:
        return False
    test_img = Image.new("RGBA", (font_size * 2, font_size * 2), (0, 0, 0, 0))
    test_draw = ImageDraw.Draw(test_img)
    # Use a representative emoji that should exist in most sets
    test_draw.text((0, 0), "😀", font=font, fill=(255, 255, 255, 255))
    return any(pixel[3] > 0 for pixel in test_img.getdata())

emoji_font = None
for p in emoji_font_paths:
    if os.path.isfile(p):
        candidate = load_font(p, font_size)
        if candidate and supports_color_glyphs(candidate):
            emoji_font = candidate
            print(f"Loaded emoji font: {p}", flush=True)
            break
        elif candidate:
            print(f"WARNING: {p} loaded but produced empty glyphs — falling back", flush=True)

if emoji_font is None:
    print("Emoji font not available — will fetch Twemoji PNGs", flush=True)

print("Emoji rendering: prefer local emoji font, fallback to Twemoji CDN", flush=True)

# Fallback to default if no fonts loaded
if latin_font is None:
    latin_font = ImageFont.load_default()

# Use Hindi font as fallback if available, otherwise use latin
primary_font = hindi_font if hindi_font else latin_font

text = text or " "
lines = text.splitlines() if "\n" in text else [text]

# Detect script type for each character
def get_char_type(char):
    """Detect if character is Hindi (Devanagari), emoji, or latin"""
    code = ord(char)
    # Devanagari Unicode range: 0x0900-0x097F
    if 0x0900 <= code <= 0x097F:
        return 'hindi'
    # Emoji ranges (expanded for better coverage)
    elif (0x1F300 <= code <= 0x1FAFF or  # Misc symbols, pictographs, and extended
          0x2600 <= code <= 0x26FF or    # Misc symbols
          0x2700 <= code <= 0x27BF or    # Dingbats
          0xFE00 <= code <= 0xFE0F or    # Variation selectors
          0x1F000 <= code <= 0x1F0FF or  # Mahjong tiles
          0x1F100 <= code <= 0x1F1FF or  # Enclosed alphanumeric supplement
          0x1F200 <= code <= 0x1F2FF or  # Enclosed ideographic supplement
          0x2300 <= code <= 0x23FF or    # Miscellaneous Technical
          0x25A0 <= code <= 0x25FF or    # Geometric Shapes
          0x2B00 <= code <= 0x2BFF or    # Miscellaneous Symbols and Arrows
          0x1F900 <= code <= 0x1F9FF):   # Supplemental Symbols and Pictographs
        return 'emoji'
    else:
        return 'latin'

# Render text with proper font switching
def render_multiline_text(canvas, lines, start_y, font_color):
    """Render text with automatic font switching for Hindi and emoji"""
    draw = ImageDraw.Draw(canvas)
    cur_y = start_y
    line_spacing = int(font_size * 0.3)

    for line in lines:
        # Calculate line width for centering
        line_width = 0
        segments = []
        current_segment = ""
        current_type = None

        # Split line into segments by script type
        for char in line:
            char_type = get_char_type(char)
            if char_type != current_type:
                if current_segment:
                    segments.append((current_segment, current_type))
                current_segment = char
                current_type = char_type
            else:
                current_segment += char

        if current_segment:
            segments.append((current_segment, current_type))

        # Calculate total line width
        for segment, seg_type in segments:
            if seg_type == 'hindi' and hindi_font:
                bbox = draw.textbbox((0, 0), segment, font=hindi_font)
                line_width += bbox[2] - bbox[0]
            elif seg_type == 'emoji':
                if emoji_font:
                    bbox = draw.textbbox((0, 0), segment, font=emoji_font)
                    line_width += bbox[2] - bbox[0]
                else:
                    line_width += int(font_size * 1.2) * len(segment)
            else:
                bbox = draw.textbbox((0, 0), segment, font=latin_font)
                line_width += bbox[2] - bbox[0]

        # Calculate starting x position (centered)
        x = (canvas_w * pos_x_pct / 100.0) - (line_width / 2.0)

        # Draw each segment with appropriate font
        for segment, seg_type in segments:
            if seg_type == 'hindi' and hindi_font:
                draw.text((x, cur_y), segment, font=hindi_font, fill=font_color)
                bbox = draw.textbbox((x, cur_y), segment, font=hindi_font)
                x += bbox[2] - bbox[0]
            elif seg_type == 'emoji':
                # Render emojis as downloaded images
                if emoji_font:
                    draw.text((x, cur_y), segment, font=emoji_font, fill=font_color)
                    bbox = draw.textbbox((x, cur_y), segment, font=emoji_font)
                    x += bbox[2] - bbox[0]
                else:
                    for emoji_char in segment:
                        emoji_img = get_emoji_image(emoji_char, int(font_size * 1.2))
                        if emoji_img:
                            # Paste emoji image with transparency
                            y_offset = int(cur_y - font_size * 0.1)  # Slight vertical adjustment
                            canvas.paste(emoji_img, (int(x), y_offset), emoji_img if emoji_img.mode == 'RGBA' else None)
                            x += int(font_size * 1.2)
                        else:
                            # Fallback: skip emoji with space
                            x += int(font_size * 0.6)
            else:
                draw.text((x, cur_y), segment, font=latin_font, fill=font_color)
                bbox = draw.textbbox((x, cur_y), segment, font=latin_font)
                x += bbox[2] - bbox[0]

        cur_y += font_size + line_spacing

    return cur_y

# Calculate bounding boxes for background
canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
temp_draw = ImageDraw.Draw(canvas)
line_spacing = int(font_size * 0.3)

line_bboxes = []
max_w = 0

for line in lines:
    # Calculate width using multi-font approach
    line_width = 0
    segments = []
    current_segment = ""
    current_type = None

    for char in line:
        char_type = get_char_type(char)
        if char_type != current_type:
            if current_segment:
                segments.append((current_segment, current_type))
            current_segment = char
            current_type = char_type
        else:
            current_segment += char

    if current_segment:
        segments.append((current_segment, current_type))

    for segment, seg_type in segments:
        if seg_type == 'hindi' and hindi_font:
            bbox = temp_draw.textbbox((0, 0), segment, font=hindi_font)
            line_width += bbox[2] - bbox[0]
        elif seg_type == 'emoji':
            if emoji_font:
                bbox = temp_draw.textbbox((0, 0), segment, font=emoji_font)
                line_width += bbox[2] - bbox[0]
            else:
                line_width += int(font_size * 1.2) * len(segment)
        else:
            bbox = temp_draw.textbbox((0, 0), segment, font=latin_font)
            line_width += bbox[2] - bbox[0]

    line_bboxes.append((line, line_width, font_size))
    if line_width > max_w:
        max_w = line_width

total_h = sum(h for _, _, h in line_bboxes) + (len(lines) - 1) * line_spacing

y = (canvas_h * pos_y_pct / 100.0) - (total_h / 2.0)

# Draw rounded backgrounds
if bg_enable:
    bg_layer = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg_layer)

    cur_y = y
    for ln, w, h in line_bboxes:
        line_x = (canvas_w * pos_x_pct / 100.0) - (w / 2.0)
        left = int(line_x - bg_padding)
        top = int(cur_y - bg_padding)
        right = int(line_x + w + bg_padding)
        bottom = int(cur_y + h + bg_padding)

        radius = min(int(h * 0.5), bg_padding)
        bg_draw.rounded_rectangle([left, top, right, bottom], radius=radius, fill=(0, 0, 0, bg_opacity))
        cur_y += h + line_spacing

    canvas = Image.alpha_composite(canvas, bg_layer)

# Draw text with multi-font support and Twemoji image rendering
render_multiline_text(canvas, lines, y, font_color)

os.makedirs(os.path.dirname(out_path), exist_ok=True)
canvas.save(out_path)
print(f"Caption saved: {out_path}", flush=True)
PY
  if [ ! -f "$CAPTION_PNG" ]; then echo "ERR: caption generation failed." >&2; exit 1; fi
fi

# [Rest of the script continues exactly as original script.sh from line 458 onwards]
# Due to length, I'm including the reference to continue from the original
# The processing logic remains identical

# Probe main duration
MAIN_VID_DURATION=$(probe_duration "$INPUT_FILE" || printf "")
MAIN_VID_DURATION=${MAIN_VID_DURATION:-10}
MAIN_VID_DURATION=$(awk -v v="$MAIN_VID_DURATION" 'BEGIN{ if(v==0) v=10; printf("%.3f", v+0)}')
echo "Main video duration (original): $MAIN_VID_DURATION" >&2

# Calculate proper INPUT_READ_DURATION based on SPEED_FACTOR
SPEED_FACTOR_N=$(awk -v s="$SPEED_FACTOR" 'BEGIN{ if(s<=0) s=1.0; printf("%.6f", s+0) }')
OVERLAY_SPEED_FACTOR_N=$(awk -v s="$OVERLAY_SPEED_FACTOR" 'BEGIN{ if(s<=0) s=1.0; printf("%.6f", s+0) }')

# Apply trim with speed factor consideration
INPUT_READ_DURATION=""
if [ -n "$TRIM_DURATION" ]; then
    INPUT_READ_DURATION=$(awk -v t="$TRIM_DURATION" -v s="$SPEED_FACTOR_N" 'BEGIN{ printf("%.3f", t*s) }')
    if [ "$(awk -v i="$INPUT_READ_DURATION" -v m="$MAIN_VID_DURATION" 'BEGIN{ if(i>m) print 1; else print 0 }')" = "1" ]; then
        echo "WARNING: Requested duration exceeds available. Adjusting..." >&2
        INPUT_READ_DURATION="$MAIN_VID_DURATION"
        EFFECTIVE_DURATION=$(awk -v i="$INPUT_READ_DURATION" -v s="$SPEED_FACTOR_N" 'BEGIN{ printf("%.3f", i/s) }')
    else
        EFFECTIVE_DURATION="$TRIM_DURATION"
    fi
else
    INPUT_READ_DURATION="$MAIN_VID_DURATION"
    EFFECTIVE_DURATION=$(awk -v m="$MAIN_VID_DURATION" -v s="$SPEED_FACTOR_N" 'BEGIN{ printf("%.3f", m/s) }')
fi

echo "SPEED_FACTOR: $SPEED_FACTOR_N" >&2
echo "OVERLAY_SPEED_FACTOR: $OVERLAY_SPEED_FACTOR_N" >&2
echo "INPUT_READ_DURATION: $INPUT_READ_DURATION (amount to read from files)" >&2
echo "EFFECTIVE_DURATION: $EFFECTIVE_DURATION (output duration after speed change)" >&2

OVERLAY_READ_DURATION=$(awk -v d="$INPUT_READ_DURATION" -v s="$OVERLAY_SPEED_FACTOR_N" 'BEGIN{ printf("%.3f", d*s) }')
echo "OVERLAY_READ_DURATION: $OVERLAY_READ_DURATION (source duration before overlay speed adjustment)" >&2

# Rotation and crop filters
ROTATE_TAG=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of default=nw=1:nk=1 "$INPUT_FILE" 2>/dev/null || printf "0")
ROTATION_FILTER=""
case "$ROTATE_TAG" in
  90) ROTATION_FILTER="transpose=1," ;;
  270) ROTATION_FILTER="transpose=2," ;;
esac

# Build crop filter
CROP_FILTER=""
if [ "$CROP_ENABLE" = "true" ]; then
  CROP_TOP_PCT=0
  CROP_BOTTOM_PCT=0

  if [ "$CROP_TOP_ENABLE" = "true" ]; then
    if [ -z "${CROP_TOP_PERCENT:-}" ]; then
      CROP_TOP_PCT=$DEFAULT_CROP_TOP_PERCENT
      echo "CROP_TOP_PERCENT not set, using default: ${DEFAULT_CROP_TOP_PERCENT}%" >&2
    else
      case "$CROP_TOP_PERCENT" in
        ''|*[!0-9]*)
          CROP_TOP_PCT=$DEFAULT_CROP_TOP_PERCENT
          echo "CROP_TOP_PERCENT invalid, using default: ${DEFAULT_CROP_TOP_PERCENT}%" >&2
          ;;
        *)
          CROP_TOP_PCT=$CROP_TOP_PERCENT
          ;;
      esac
    fi
  fi

  if [ "$CROP_BOTTOM_ENABLE" = "true" ]; then
    if [ -z "${CROP_BOTTOM_PERCENT:-}" ]; then
      CROP_BOTTOM_PCT=$DEFAULT_CROP_BOTTOM_PERCENT
      echo "CROP_BOTTOM_PERCENT not set, using default: ${DEFAULT_CROP_BOTTOM_PERCENT}%" >&2
    else
      case "$CROP_BOTTOM_PERCENT" in
        ''|*[!0-9]*)
          CROP_BOTTOM_PCT=$DEFAULT_CROP_BOTTOM_PERCENT
          echo "CROP_BOTTOM_PERCENT invalid, using default: ${DEFAULT_CROP_BOTTOM_PERCENT}%" >&2
          ;;
        *)
          CROP_BOTTOM_PCT=$CROP_BOTTOM_PERCENT
          ;;
      esac
    fi
  fi

  TOTAL_CROP_PCT=$((CROP_TOP_PCT + CROP_BOTTOM_PCT))

  if [ "$TOTAL_CROP_PCT" -gt 0 ] && [ "$TOTAL_CROP_PCT" -lt 100 ]; then
    KEEP_PCT=$((100 - TOTAL_CROP_PCT))
    echo "Crop settings: Top=${CROP_TOP_PCT}%, Bottom=${CROP_BOTTOM_PCT}%, Keeping=${KEEP_PCT}%" >&2
    CROP_FILTER="crop=in_w:in_h*${KEEP_PCT}/100:0:in_h*${CROP_TOP_PCT}/100,"
  elif [ "$TOTAL_CROP_PCT" -ge 100 ]; then
    echo "WARNING: Total crop percentage >= 100%, disabling crop" >&2
    CROP_FILTER=""
  fi
fi

# Determine available canvas space for overlay
MAIN_RES=$(probe_resolution "$INPUT_FILE" || true)
if [ -n "$MAIN_RES" ]; then
  MAIN_SRC_W=$(printf "%s" "$MAIN_RES" | awk -Fx '{print $1}')
  MAIN_SRC_H=$(printf "%s" "$MAIN_RES" | awk -Fx '{print $2}')
else
  MAIN_SRC_W=1920; MAIN_SRC_H=1080
fi

MAIN_KEEP_PCT=100
if [ "$CROP_ENABLE" = "true" ]; then
  MAIN_KEEP_PCT=$((100 - ${CROP_TOP_PCT:-0} - ${CROP_BOTTOM_PCT:-0}))
  if [ "$MAIN_KEEP_PCT" -le 0 ]; then MAIN_KEEP_PCT=100; fi
fi

MAIN_POST_HEIGHT=$(awk -v h="$MAIN_SRC_H" -v pct="$MAIN_KEEP_PCT" 'BEGIN{ printf("%.6f", h*pct/100.0) }')
MAIN_SCALED_HEIGHT=$(awk -v cw="$CANVAS_WIDTH" -v mh="$MAIN_POST_HEIGHT" -v mw="$MAIN_SRC_W" 'BEGIN{ if(mw<=0) printf("%.6f", 0); else printf("%.6f", cw*mh/mw) }')
AVAILABLE_HEIGHT=$(awk -v ch="$CANVAS_HEIGHT" -v mh="$MAIN_SCALED_HEIGHT" 'BEGIN{ v=ch-mh; if (v<0.0) v=ch*0.35; if (v<50) v=ch*0.35; if (v<1) v=1; printf("%.6f", v) }')
AVAILABLE_HEIGHT_INT=$(awk -v v="$AVAILABLE_HEIGHT" 'BEGIN{ if(v<1) v=1; printf("%d", v) }')

# Overlay aspect after trimming
TRIM_LEFT_VAL=${OVERLAY_TRIM_LEFT:-0}
TRIM_RIGHT_VAL=${OVERLAY_TRIM_RIGHT:-0}
OVERLAY_TRIMMED_WIDTH=$(awk -v w="$O_W" -v l="$TRIM_LEFT_VAL" -v r="$TRIM_RIGHT_VAL" 'BEGIN{ val=w-l-r; if (val<1) val=1; printf("%.6f", val) }')
OVERLAY_TRIMMED_HEIGHT=$(awk -v h="$O_H" 'BEGIN{ if(h<1) h=1; printf("%.6f", h) }')
OVERLAY_ASPECT=$(awk -v w="$OVERLAY_TRIMMED_WIDTH" -v h="$OVERLAY_TRIMMED_HEIGHT" 'BEGIN{ if(h<=0) printf("1.0"); else printf("%.6f", w/h) }')

# Resolve user-provided overlay dimensions (pixels, percent, or auto)
OVERLAY_WIDTH_EXPLICIT=0
RAW_OVERLAY_WIDTH="$OVERLAY_WIDTH"
case "$RAW_OVERLAY_WIDTH" in
  ""|auto|AUTO|Auto)
    RAW_OVERLAY_WIDTH=""
    ;;
  *%)
    PCT=${RAW_OVERLAY_WIDTH%%%}
    if [ -n "$PCT" ]; then
      RAW_OVERLAY_WIDTH=$(awk -v base="$CANVAS_WIDTH" -v pct="$PCT" 'BEGIN{ printf("%.6f", base*pct/100.0) }')
      OVERLAY_WIDTH_EXPLICIT=1
    else
      RAW_OVERLAY_WIDTH=""
    fi
    ;;
  *)
    RAW_OVERLAY_WIDTH=$(awk -v v="$RAW_OVERLAY_WIDTH" 'BEGIN{ printf("%.6f", v+0) }')
    OVERLAY_WIDTH_EXPLICIT=1
    ;;
esac

OVERLAY_HEIGHT_EXPLICIT=0
RAW_OVERLAY_HEIGHT="$OVERLAY_HEIGHT"
case "$RAW_OVERLAY_HEIGHT" in
  ""|auto|AUTO|Auto)
    RAW_OVERLAY_HEIGHT=""
    ;;
  *%)
    PCT=${RAW_OVERLAY_HEIGHT%%%}
    if [ -n "$PCT" ]; then
      RAW_OVERLAY_HEIGHT=$(awk -v base="$CANVAS_HEIGHT" -v pct="$PCT" 'BEGIN{ printf("%.6f", base*pct/100.0) }')
      OVERLAY_HEIGHT_EXPLICIT=1
    else
      RAW_OVERLAY_HEIGHT=""
    fi
    ;;
  *)
    RAW_OVERLAY_HEIGHT=$(awk -v v="$RAW_OVERLAY_HEIGHT" 'BEGIN{ printf("%.6f", v+0) }')
    OVERLAY_HEIGHT_EXPLICIT=1
    ;;
esac

WIDTH_BASE="$RAW_OVERLAY_WIDTH"
HEIGHT_BASE="$RAW_OVERLAY_HEIGHT"

if [ -z "$WIDTH_BASE" ] && [ -z "$HEIGHT_BASE" ]; then
  HEIGHT_BASE=$AVAILABLE_HEIGHT_INT
  if [ -z "$HEIGHT_BASE" ] || [ "$HEIGHT_BASE" -le 0 ]; then
    HEIGHT_BASE=$(awk -v ch="$CANVAS_HEIGHT" 'BEGIN{ printf("%.6f", ch*0.35) }')
  fi
  WIDTH_BASE=$(awk -v h="$HEIGHT_BASE" -v aspect="$OVERLAY_ASPECT" 'BEGIN{ printf("%.6f", h*aspect) }')
elif [ -z "$HEIGHT_BASE" ]; then
  HEIGHT_BASE=$(awk -v w="$WIDTH_BASE" -v aspect="$OVERLAY_ASPECT" 'BEGIN{ if(aspect<=0) aspect=1; printf("%.6f", w/aspect) }')
elif [ -z "$WIDTH_BASE" ]; then
  WIDTH_BASE=$(awk -v h="$HEIGHT_BASE" -v aspect="$OVERLAY_ASPECT" 'BEGIN{ printf("%.6f", h*aspect) }')
fi

OVERLAY_FINAL_WIDTH=$(awk -v w="$WIDTH_BASE" -v s="$OVERLAY_SCALE_PERCENT" 'BEGIN{ printf("%.6f", w*s/100.0) }')
OVERLAY_FINAL_HEIGHT=$(awk -v h="$HEIGHT_BASE" -v s="$OVERLAY_SCALE_PERCENT" 'BEGIN{ printf("%.6f", h*s/100.0) }')

OVERLAY_ALLOW_OVERFLOW=$(awk -v s="$OVERLAY_SCALE_PERCENT" 'BEGIN{ if(s=="") s=100; if(s+0>100) print 1; else print 0 }')
OVERLAY_FINAL_WIDTH_INT=$(awk -v w="$OVERLAY_FINAL_WIDTH" 'BEGIN{ if(w<1) w=1; printf("%d", w) }')
OVERLAY_FINAL_HEIGHT_INT=$(awk -v h="$OVERLAY_FINAL_HEIGHT" 'BEGIN{ if(h<1) h=1; printf("%d", h) }')

if [ "$OVERLAY_FINAL_WIDTH_INT" -gt "$CANVAS_WIDTH" ]; then
  if [ "$OVERLAY_WIDTH_EXPLICIT" -eq 0 ]; then
    OVERLAY_FINAL_WIDTH_INT=$CANVAS_WIDTH
    OVERLAY_FINAL_HEIGHT_INT=$(awk -v w="$OVERLAY_FINAL_WIDTH_INT" -v aspect="$OVERLAY_ASPECT" 'BEGIN{ if(aspect<=0) aspect=1; val=w/aspect; if(val<1) val=1; printf("%d", val) }')
  else
    echo "WARN: overlay width (${OVERLAY_FINAL_WIDTH_INT}px) exceeds canvas width; overlay may spill horizontally." >&2
  fi
fi

if [ "$OVERLAY_ALLOW_OVERFLOW" -eq 0 ] && [ "$OVERLAY_HEIGHT_EXPLICIT" -eq 0 ]; then
  if [ "$AVAILABLE_HEIGHT_INT" -gt 0 ] && [ "$OVERLAY_FINAL_HEIGHT_INT" -gt "$AVAILABLE_HEIGHT_INT" ]; then
    OVERLAY_FINAL_HEIGHT_INT=$AVAILABLE_HEIGHT_INT
    OVERLAY_FINAL_WIDTH_INT=$(awk -v h="$OVERLAY_FINAL_HEIGHT_INT" -v aspect="$OVERLAY_ASPECT" 'BEGIN{ val=h*aspect; if(val<1) val=1; printf("%d", val) }')
    if [ "$OVERLAY_FINAL_WIDTH_INT" -gt "$CANVAS_WIDTH" ]; then
      OVERLAY_FINAL_WIDTH_INT=$CANVAS_WIDTH
    fi
  fi
fi

if [ "$OVERLAY_FINAL_HEIGHT_INT" -gt "$CANVAS_HEIGHT" ]; then
  OVERLAY_FINAL_HEIGHT_INT=$CANVAS_HEIGHT
  if [ "$OVERLAY_HEIGHT_EXPLICIT" -eq 0 ]; then
    OVERLAY_FINAL_WIDTH_INT=$(awk -v h="$OVERLAY_FINAL_HEIGHT_INT" -v aspect="$OVERLAY_ASPECT" 'BEGIN{ val=h*aspect; if(val<1) val=1; printf("%d", val) }')
    if [ "$OVERLAY_FINAL_WIDTH_INT" -gt "$CANVAS_WIDTH" ]; then
      OVERLAY_FINAL_WIDTH_INT=$CANVAS_WIDTH
    fi
  fi
fi

if [ "$OVERLAY_FINAL_WIDTH_INT" -lt 1 ]; then OVERLAY_FINAL_WIDTH_INT=1; fi
if [ "$OVERLAY_FINAL_HEIGHT_INT" -lt 1 ]; then OVERLAY_FINAL_HEIGHT_INT=1; fi

OVERLAY_SIZE_FILTER="scale=${OVERLAY_FINAL_WIDTH_INT}:${OVERLAY_FINAL_HEIGHT_INT}"

# Calculate position based on OVERLAY_POSITION setting
case "$OVERLAY_POSITION" in
  top)
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="0"
    ;;
  bottom)
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="H-h"
    ;;
  center)
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="(H-h)/2"
    ;;
  custom)
    OVERLAY_X="$OVERLAY_CUSTOM_X"
    OVERLAY_Y="$OVERLAY_CUSTOM_Y"
    ;;
  *)
    echo "WARN: Invalid OVERLAY_POSITION, using bottom" >&2
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="H-h"
    ;;
esac

echo "Overlay positioning: ${OVERLAY_POSITION} at X=${OVERLAY_X}, Y=${OVERLAY_Y}, size=${OVERLAY_FINAL_WIDTH_INT}x${OVERLAY_FINAL_HEIGHT_INT}" >&2

# Calculate position based on OVERLAY_POSITION setting
case "$OVERLAY_POSITION" in
  top)
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="0"
    ;;
  bottom)
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="H-h"
    ;;
  center)
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="(H-h)/2"
    ;;
  custom)
    OVERLAY_X="$OVERLAY_CUSTOM_X"
    OVERLAY_Y="$OVERLAY_CUSTOM_Y"
    ;;
  *)
    echo "WARN: Invalid OVERLAY_POSITION, using bottom" >&2
    OVERLAY_X="(W-w)/2"
    OVERLAY_Y="H-h"
    ;;
esac

echo "Overlay positioning: ${OVERLAY_POSITION} at X=${OVERLAY_X}, Y=${OVERLAY_Y}, size=${OVERLAY_FINAL_WIDTH_INT}x${OVERLAY_FINAL_HEIGHT_INT}" >&2

# Main video vertical position
case "$MAIN_POSITION" in
  top)
    MAIN_Y="0"
    ;;
  bottom)
    MAIN_Y="H-h"
    ;;
  center)
    MAIN_Y="(H-h)/2"
    ;;
  custom)
    MAIN_Y="$MAIN_CUSTOM_Y"
    ;;
  *)
    echo "WARN: Invalid MAIN_POSITION, using top" >&2
    MAIN_Y="0"
    ;;
esac

echo "Main positioning: ${MAIN_POSITION} at Y=${MAIN_Y}" >&2

# Mirror filter
MIRROR_FILTER=""
if [ "$MIRROR_ENABLE" = "true" ]; then
  MIRROR_FILTER="hflip,"
fi

# Calculate input indices
INPUT_INDEX=0
OVERLAY_INDEX=1
CAPTION_INDEX=""
RANDOM_INSERT_INDEX=""
OUTRO_INDEX=""

if [ "$CAPTION_ENABLE" = "true" ]; then
  CAPTION_INDEX=2
  NEXT_INDEX=3
else
  NEXT_INDEX=2
fi

if [ -n "$RANDOM_INSERT_FILE" ]; then
  RANDOM_INSERT_INDEX=$NEXT_INDEX
  NEXT_INDEX=$((NEXT_INDEX + 1))
fi

if [ -n "$OUTRO_FILE" ]; then
  OUTRO_INDEX=$NEXT_INDEX
fi

# Build main composition base - with configurable overlay positioning
if [ "$CAPTION_ENABLE" = "true" ]; then
  BASE_FILTER="color=c=black:s=1080x1920:d=${EFFECTIVE_DURATION}[canvas]; \
[${INPUT_INDEX}:v]trim=duration=${INPUT_READ_DURATION},setpts=PTS-STARTPTS,${ROTATION_FILTER}${CROP_FILTER}scale=1080:-1,${MIRROR_FILTER}format=yuva420p[main_video]; \
[${OVERLAY_INDEX}:v]trim=duration=${OVERLAY_READ_DURATION},setpts=PTS-STARTPTS,${OVERLAY_PRE_EFFECTS}${OVERLAY_SIZE_FILTER},${OVERLAY_EFFECTS}fps=${TARGET_FPS},setpts=PTS/${OVERLAY_SPEED_FACTOR_N},tpad=stop_mode=clone:stop_duration=${INPUT_READ_DURATION},format=yuva420p[overlay_video]; \
[canvas][main_video]overlay=(W-w)/2:${MAIN_Y}[bg_with_main]; \
[bg_with_main][overlay_video]overlay=${OVERLAY_X}:${OVERLAY_Y}:format=auto:alpha=straight:eof_action=repeat[layout_complete]; \
[layout_complete][${CAPTION_INDEX}:v]overlay=0:0,setsar=1,format=yuv420p,fps=${TARGET_FPS},setpts=PTS/${SPEED_FACTOR_N}[composed_main]"
else
  BASE_FILTER="color=c=black:s=1080x1920:d=${EFFECTIVE_DURATION}[canvas]; \
[${INPUT_INDEX}:v]trim=duration=${INPUT_READ_DURATION},setpts=PTS-STARTPTS,${ROTATION_FILTER}${CROP_FILTER}scale=1080:-1,${MIRROR_FILTER}format=yuva420p[main_video]; \
[${OVERLAY_INDEX}:v]trim=duration=${OVERLAY_READ_DURATION},setpts=PTS-STARTPTS,${OVERLAY_PRE_EFFECTS}${OVERLAY_SIZE_FILTER},${OVERLAY_EFFECTS}fps=${TARGET_FPS},setpts=PTS/${OVERLAY_SPEED_FACTOR_N},tpad=stop_mode=clone:stop_duration=${INPUT_READ_DURATION},format=yuva420p[overlay_video]; \
[canvas][main_video]overlay=(W-w)/2:${MAIN_Y}[bg_with_main]; \
[bg_with_main][overlay_video]overlay=${OVERLAY_X}:${OVERLAY_Y}:format=auto:alpha=straight:eof_action=repeat,setsar=1,format=yuv420p,fps=${TARGET_FPS},setpts=PTS/${SPEED_FACTOR_N}[composed_main]"
fi

# Assemble filter complex incrementally
FILTER_LINES=""
append_filter() {
  if [ -z "$FILTER_LINES" ]; then
    FILTER_LINES="$1"
  else
    FILTER_LINES="${FILTER_LINES}; ${1}"
  fi
}

append_filter "$BASE_FILTER"

# Build the audio tempo chain for main audio
AUDIO_TEMPO_CHAIN=""
if [ "$SPEED_FACTOR_N" != "1.000000" ]; then
  export SPEED_FACTOR_N
  AUDIO_TEMPO_CHAIN=$(python3 - <<'PY'
import os
s = float(os.environ.get('SPEED_FACTOR_N','1'))
if s <= 0:
    print("atempo=1.0")
else:
    factors = []
    tmp = s
    while tmp > 2.0000001:
        factors.append(2.0)
        tmp = tmp / 2.0
    while tmp < 0.5 - 1e-12:
        factors.append(0.5)
        tmp = tmp / 0.5
    factors.append(round(tmp, 6))
    out = ",".join(f"atempo={f:.6f}" for f in factors)
    print(out)
PY
)
  echo "AUDIO_TEMPO_CHAIN: $AUDIO_TEMPO_CHAIN" >&2
fi

OVERLAY_ATEMPO_CHAIN=""
if [ "$OVERLAY_SPEED_FACTOR_N" != "1.000000" ]; then
  export OVERLAY_SPEED_FACTOR_N
  OVERLAY_ATEMPO_CHAIN=$(python3 - <<'PY'
import os
s = float(os.environ.get('OVERLAY_SPEED_FACTOR_N','1'))
if s <= 0:
    print("atempo=1.0")
else:
    factors = []
    tmp = s
    while tmp > 2.0000001:
        factors.append(2.0)
        tmp = tmp / 2.0
    while tmp < 0.5 - 1e-12:
        factors.append(0.5)
        tmp = tmp / 0.5
    factors.append(round(tmp, 6))
    out = ",".join(f"atempo={f:.6f}" for f in factors)
    print(out)
PY
)
  echo "OVERLAY_ATEMPO_CHAIN: $OVERLAY_ATEMPO_CHAIN" >&2
fi

OVERLAY_AUDIO_RATE_FILTER="asetpts=PTS-STARTPTS"
if [ -n "$OVERLAY_ATEMPO_CHAIN" ]; then
  OVERLAY_AUDIO_RATE_FILTER="$OVERLAY_AUDIO_RATE_FILTER,$OVERLAY_ATEMPO_CHAIN"
fi

# ========== AUDIO HANDLING ==========
AUDIO_FILTER=""
AUDIO_MAP="0:a?"

# NEW: Mix main audio with overlay audio FIRST (before random insert)
if [ "$OVERLAY_AUDIO_ENABLE" = "true" ]; then
  echo "=== Mixing main audio with overlay audio at ${OVERLAY_AUDIO_VOLUME}% ===" >&2

  # Build base mixed audio (main + overlay) - use amerge with proper volume normalization
  if [ -n "$AUDIO_TEMPO_CHAIN" ]; then
    BASE_AUDIO_MIX="[0:a]atrim=duration=${INPUT_READ_DURATION},asetpts=PTS-STARTPTS,${AUDIO_TEMPO_CHAIN}[main_tempo]; \
[${OVERLAY_INDEX}:a]atrim=duration=${OVERLAY_READ_DURATION},${OVERLAY_AUDIO_RATE_FILTER},apad=pad_dur=${INPUT_READ_DURATION},volume=${OVERLAY_VOLUME_FLOAT}[overlay_vol]; \
[main_tempo][overlay_vol]amix=inputs=2:duration=longest:dropout_transition=2,volume=2[base_mixed]"
  else
    BASE_AUDIO_MIX="[0:a]atrim=duration=${INPUT_READ_DURATION},asetpts=PTS-STARTPTS[main_a]; \
[${OVERLAY_INDEX}:a]atrim=duration=${OVERLAY_READ_DURATION},${OVERLAY_AUDIO_RATE_FILTER},apad=pad_dur=${INPUT_READ_DURATION},volume=${OVERLAY_VOLUME_FLOAT}[overlay_vol]; \
[main_a][overlay_vol]amix=inputs=2:duration=longest:dropout_transition=2,volume=2[base_mixed]"
  fi

  AUDIO_FILTER="$BASE_AUDIO_MIX"
  MIXED_AUDIO_LABEL="[base_mixed]"
else
  # No overlay audio - just use main audio
  if [ -n "$AUDIO_TEMPO_CHAIN" ]; then
    AUDIO_FILTER="[0:a]atrim=duration=${INPUT_READ_DURATION},asetpts=PTS-STARTPTS,${AUDIO_TEMPO_CHAIN}[base_mixed]"
    MIXED_AUDIO_LABEL="[base_mixed]"
  else
    MIXED_AUDIO_LABEL="0:a"
  fi
fi

# ========== RANDOM INSERT (video + audio) ==========
if [ -n "$RANDOM_INSERT_FILE" ]; then
  INSERT_DURATION=$(probe_duration "$RANDOM_INSERT_FILE" || printf "2")
  INSERT_DURATION=$(awk -v v="$INSERT_DURATION" 'BEGIN{ printf("%.3f", v+0)}')
  echo "Random insert duration: $INSERT_DURATION seconds" >&2

  export EFFECTIVE_DURATION INSERT_DURATION
  RANDOM_POS=$(python3 - <<'PY'
import os, struct
efd = float(os.environ.get('EFFECTIVE_DURATION','0'))
idur = float(os.environ.get('INSERT_DURATION','0'))
minpos = 3.0
maxpos = efd - idur - 1.0
if maxpos < minpos:
    maxpos = minpos
r = struct.unpack(">I", os.urandom(4))[0] / 4294967295.0
v = minpos + r * (maxpos - minpos)
print(f"{v:.3f}")
PY
)
  echo "Random insert at: ${RANDOM_POS}s" >&2

  BEFORE_INSERT=$(awk -v p="$RANDOM_POS" 'BEGIN{ printf("%.3f", p) }')
  NEW_DURATION=$(awk -v e="$EFFECTIVE_DURATION" -v i="$INSERT_DURATION" 'BEGIN{ printf("%.3f", e+i) }')

  # VIDEO insert
  VIDEO_INSERT_BLOCK="[composed_main]fps=${TARGET_FPS},split=2[main1][main2]; \
[main1]trim=start=0:end=${BEFORE_INSERT},setpts=PTS-STARTPTS[seg1]; \
[main2]trim=start=${BEFORE_INSERT},setpts=PTS-STARTPTS[seg3]; \
[${RANDOM_INSERT_INDEX}:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=${TARGET_FPS},setpts=PTS-STARTPTS[insert_scaled]; \
[seg1][insert_scaled][seg3]concat=n=3:v=1:a=0[concat_v]; \
[concat_v]fps=${TARGET_FPS}[final_v]"

  append_filter "$VIDEO_INSERT_BLOCK"

  # AUDIO insert - split the mixed audio
  if [ -n "$AUDIO_FILTER" ]; then
    AUDIO_FILTER="${AUDIO_FILTER}; \
${MIXED_AUDIO_LABEL}asplit=2[mix1][mix2]; \
[mix1]atrim=start=0:end=${BEFORE_INSERT},asetpts=PTS-STARTPTS[a1]; \
[mix2]atrim=start=${BEFORE_INSERT},asetpts=PTS-STARTPTS[a3]; \
[${RANDOM_INSERT_INDEX}:a]asetpts=PTS-STARTPTS[insert_audio]; \
[a1][insert_audio][a3]concat=n=3:v=0:a=1[final_audio]"
  fi

  EFFECTIVE_DURATION="$NEW_DURATION"
  AUDIO_MAP="[final_audio]"
else
  # No random insert - use the base mixed audio
  if [ -n "$AUDIO_FILTER" ]; then
    AUDIO_FILTER="${AUDIO_FILTER}; ${MIXED_AUDIO_LABEL}acopy[final_audio]"
    AUDIO_MAP="[final_audio]"
  else
    AUDIO_MAP="${MIXED_AUDIO_LABEL}"
  fi
fi

# ========== OUTRO (video + audio) ==========
if [ -n "$OUTRO_FILE" ] && [ -n "$OUTRO_INDEX" ]; then
  OUTRO_START=$(awk -v d="$EFFECTIVE_DURATION" -v t="$OUTRO_TRANSITION_DURATION" 'BEGIN{ printf("%.3f", d-t) }')

  # VIDEO outro
  if [ -n "$RANDOM_INSERT_FILE" ]; then
    OUTRO_VIDEO_BLOCK="[${OUTRO_INDEX}:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1,setpts=PTS-STARTPTS[outro_scaled]; \
[final_v]fps=${TARGET_FPS},setsar=1,setpts=PTS-STARTPTS[main_normalized]; \
[main_normalized]fps=${TARGET_FPS}[main_normalized_fps]; \
[outro_scaled]fps=${TARGET_FPS}[outro_scaled_fps]; \
[main_normalized_fps][outro_scaled_fps]xfade=transition=fade:duration=${OUTRO_TRANSITION_DURATION}:offset=${OUTRO_START}[final_v]"
    append_filter "$OUTRO_VIDEO_BLOCK"
  else
    OUTRO_VIDEO_BLOCK="[${OUTRO_INDEX}:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1,setpts=PTS-STARTPTS[outro_scaled]; \
[composed_main]fps=${TARGET_FPS},setsar=1,setpts=PTS-STARTPTS[main_normalized]; \
[main_normalized]fps=${TARGET_FPS}[main_normalized_fps]; \
[outro_scaled]fps=${TARGET_FPS}[outro_scaled_fps]; \
[main_normalized_fps][outro_scaled_fps]xfade=transition=fade:duration=${OUTRO_TRANSITION_DURATION}:offset=${OUTRO_START}[final_v]"
    append_filter "$OUTRO_VIDEO_BLOCK"
  fi

  # AUDIO outro
  if [ -n "$AUDIO_FILTER" ]; then
    AUDIO_FILTER="${AUDIO_FILTER}; \
[${OUTRO_INDEX}:a]asetpts=PTS-STARTPTS[outro_a]; \
[final_audio][outro_a]concat=n=2:v=0:a=1[final_audio]"
  fi

  OUTPUT_LABEL="[final_v]"
else
  if [ -n "$RANDOM_INSERT_FILE" ]; then
    OUTPUT_LABEL="[final_v]"
  else
    append_filter "[composed_main]fps=${TARGET_FPS}[final_v]"
    OUTPUT_LABEL="[final_v]"
  fi
fi

# Final brightness application
if [ "$(awk -v b="$BRIGHTNESS" 'BEGIN{ if (b==0) print "0"; else print "1" }')" = "1" ]; then
  append_filter "[final_v]eq=brightness=${BRIGHTNESS}[final_v_out]"
  FINAL_OUTPUT_LABEL="[final_v_out]"
else
  FINAL_OUTPUT_LABEL="${OUTPUT_LABEL}"
fi

# Combine all filters
if [ -n "$AUDIO_FILTER" ]; then
  COMPLETE_FILTER="${FILTER_LINES}; ${AUDIO_FILTER}"
else
  COMPLETE_FILTER="${FILTER_LINES}"
fi

# Build input args
INPUT_ARGS=""
OVERLAY_LOOP_PREFIX=""
if [ "$OVERLAY_LOOP_ENABLE" = "true" ]; then
  OVERLAY_LOOP_PREFIX="-stream_loop -1 "
fi
if [ -n "$TRIM_DURATION" ]; then
  INPUT_ARGS="-t ${INPUT_READ_DURATION} -i \"$INPUT_FILE\" ${OVERLAY_LOOP_PREFIX}-t ${OVERLAY_READ_DURATION} -i \"$MERGED_OVERLAY\""
else
  INPUT_ARGS="-i \"$INPUT_FILE\" ${OVERLAY_LOOP_PREFIX}-i \"$MERGED_OVERLAY\""
fi

if [ "$CAPTION_ENABLE" = "true" ]; then
  INPUT_ARGS="$INPUT_ARGS -i \"$CAPTION_PNG\""
fi

if [ -n "$RANDOM_INSERT_FILE" ]; then
  INPUT_ARGS="$INPUT_ARGS -i \"$RANDOM_INSERT_FILE\""
fi

if [ -n "$OUTRO_FILE" ]; then
  INPUT_ARGS="$INPUT_ARGS -i \"$OUTRO_FILE\""
fi

# Build final ffmpeg command
CMD="ffmpeg -hide_banner -y -progress pipe:2 -loglevel warning $INPUT_ARGS -filter_complex \"${COMPLETE_FILTER}\" -map \"${FINAL_OUTPUT_LABEL}\""

if [ -n "$AUDIO_FILTER" ]; then
  CMD="$CMD -map \"${AUDIO_MAP}\""
else
  CMD="$CMD -map ${AUDIO_MAP}"
fi

CMD="$CMD -c:v libx264 -crf 23 -preset veryfast -c:a aac -b:a 192k -r ${TARGET_FPS} -aspect 9:16"

if [ -n "$TRIM_DURATION" ] && [ -z "$OUTRO_FILE" ]; then
  CMD="$CMD -t ${EFFECTIVE_DURATION}"
fi

CMD="$CMD \"$OUT_FILE\""

# Debug output
echo "=== DEBUG: filter_complex ===" >&2
echo "$COMPLETE_FILTER" >&2
echo "=== DEBUG: ffmpeg cmd ===" >&2
echo "$CMD" >&2

# Execute
echo "Executing final render with overlay audio support..." >&2
echo "Progress will be shown below:" >&2

if sh -c "$CMD" < /dev/null; then
  [ "$CAPTION_ENABLE" = "true" ] && rm -f "$CAPTION_PNG" || true
  [ -n "$MERGED_OVERLAY_TMP" ] && [ -f "$MERGED_OVERLAY_TMP" ] && rm -f "$MERGED_OVERLAY_TMP" || true
  [ -n "$COMPOSED_MAIN_TMP" ] && [ -f "$COMPOSED_MAIN_TMP" ] && rm -f "$COMPOSED_MAIN_TMP" || true
  echo "Success! Output file: $OUT_FILE" >&2
  printf '%s\n' "$(basename "$OUT_FILE")"
  exit 0
else
  echo "ERR: ffmpeg failed or timed out." >&2
  echo "Check the debug output above for details." >&2
  exit 1
fi
