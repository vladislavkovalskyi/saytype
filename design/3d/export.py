# Turns full renders into UI-sized WebP assets.
#   python3 export.py <renders_dir> <out_dir>
#
# capsule -> capsule.webp (hero, 1120 px wide)
# others  -> <name>.webp (tile art, 420 px) and <name>-sm.webp (rail icon, 112 px)
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)


def bloom(im, strength=0.5, radius=10):
    rgb = im.convert("RGB")
    mask = rgb.convert("L").point(lambda v: 255 if v > 248 else 0)
    bright = Image.composite(rgb, Image.new("RGB", im.size), mask).filter(ImageFilter.GaussianBlur(radius))
    out = ImageChops.add(rgb, bright.point(lambda v: int(v * strength)))
    alpha = ImageChops.lighter(im.getchannel("A"), bright.convert("L").point(lambda v: min(255, int(v * strength * 1.1))))
    out.putalpha(alpha)
    return out


def trim(im, pad=0.04):
    box = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    im = im.crop(box)
    p = int(max(im.size) * pad)
    canvas = Image.new("RGBA", (im.width + 2 * p, im.height + 2 * p))
    canvas.paste(im, (p, p))
    return canvas


def square(im):
    side = max(im.size)
    canvas = Image.new("RGBA", (side, side))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return canvas


def save(im, path, width):
    h = round(im.height * width / im.width)
    im.resize((width, h), Image.LANCZOS).save(path, "WEBP", quality=86, method=6)
    print(f"{path.name}: {path.stat().st_size // 1024} KB")


for png in sorted(src.glob("*.png")):
    name = png.stem
    im = Image.open(png).convert("RGBA")
    if name not in ("appicon",):
        im = bloom(im)
    im = trim(im)
    if name.startswith("capsule"):
        save(im, dst / f"{name}.webp", 1120)
        save(im, dst / f"{name}-sm.webp", 140)
    else:
        sq = square(im)
        save(sq, dst / f"{name}.webp", 420)
        save(sq, dst / f"{name}-sm.webp", 112)
