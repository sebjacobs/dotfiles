# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Compose a project logo: a square mark image next to a wordmark set in DM Sans.

Everything the skill needs is bundled alongside this file (the font under
assets/), so it runs unchanged from any project's checkout.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SKILL_DIR = Path(__file__).resolve().parent
BUNDLED_FONT = SKILL_DIR / "assets" / "DMSans-Regular.ttf"

DEFAULT_BG = (245, 241, 232)
DEFAULT_INK = (42, 38, 35)


def parse_colour(value):
    parts = value.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("colour must be 'R,G,B' (0-255 each)")
    return tuple(int(p) for p in parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mark", required=True, help="path to the square mark image")
    parser.add_argument("--text", required=True, help="wordmark text (e.g. project name)")
    parser.add_argument("--output", required=True, help="path to write the composed PNG")
    parser.add_argument("--font", default=str(BUNDLED_FONT), help="TTF font path")
    parser.add_argument("--font-size", type=int, default=360)
    parser.add_argument("--gap", type=int, default=40, help="px between mark and text")
    parser.add_argument("--right-pad", type=int, default=120, help="px of padding after text")
    parser.add_argument("--bg", type=parse_colour, default=DEFAULT_BG, help="background 'R,G,B'")
    parser.add_argument("--ink", type=parse_colour, default=DEFAULT_INK, help="text 'R,G,B'")
    args = parser.parse_args()

    mark = Image.open(args.mark).convert("RGB")
    mark_w, mark_h = mark.size

    font = ImageFont.truetype(args.font, args.font_size)
    bbox = font.getbbox(args.text)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    canvas_w = mark_w + args.gap + text_w + args.right_pad
    canvas_h = mark_h

    canvas = Image.new("RGB", (canvas_w, canvas_h), args.bg)
    canvas.paste(mark, (0, 0))

    draw = ImageDraw.Draw(canvas)
    text_x = mark_w + args.gap - bbox[0]
    text_y = (canvas_h - text_h) // 2 - bbox[1]
    draw.text((text_x, text_y), args.text, font=font, fill=args.ink)

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output)
    print(f"Saved {args.output}: {canvas_w}x{canvas_h}")


if __name__ == "__main__":
    main()
