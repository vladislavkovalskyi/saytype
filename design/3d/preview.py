# Composites rendered objects over a colour field to judge them in context.
#   python3 preview.py <render_dir> <out.png> name[:scale] ...
import sys
from PIL import Image, ImageDraw

src, out, *items = sys.argv[1:]
W, H = 1600, 900
bg = Image.new("RGB", (W, H))
top, bottom = (238, 132, 52), (92, 22, 38)
draw = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    draw.line([(0, y), (W, y)], fill=tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)))
x = 20
for item in items:
    name, _, scale = item.partition(":")
    im = Image.open(f"{src}/{name}.png").convert("RGBA")
    s = float(scale or 1)
    im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    bg.paste(im, (x, (H - im.height) // 2), im)
    x += im.width - 40
bg.save(out)
print(out)
