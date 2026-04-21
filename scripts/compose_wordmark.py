# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
from PIL import Image, ImageDraw, ImageFont

BG = (245, 241, 232)
INK = (42, 38, 35)

mark = Image.open("assets/logo.png").convert("RGB")
mark_w, mark_h = mark.size

font_path = "../cadence/tmp/fonts/DMSans-Regular.ttf"
font_size = 360
font = ImageFont.truetype(font_path, font_size)

text = "dotfiles"
bbox = font.getbbox(text)
text_w = bbox[2] - bbox[0]
text_h = bbox[3] - bbox[1]

gap = 40
right_pad = 120
canvas_w = mark_w + gap + text_w + right_pad
canvas_h = mark_h

canvas = Image.new("RGB", (canvas_w, canvas_h), BG)
canvas.paste(mark, (0, 0))

draw = ImageDraw.Draw(canvas)
text_x = mark_w + gap - bbox[0]
text_y = (canvas_h - text_h) // 2 - bbox[1]
draw.text((text_x, text_y), text, font=font, fill=INK)

canvas.save("assets/logo-wordmark.png")
print(f"Saved: {canvas_w}x{canvas_h}")
