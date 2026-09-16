# Copies Blender renders into the app's asset catalog as trimmed PNG image sets.
#   python3 design/3d/export_app.py design/3d/renders App/Resources/Assets.xcassets [--glass]
#
# --glass adds a soft glow around the brightest pixels: glass.py renders through AgX, which
# keeps glowing symbols below pure white, so they need the bloom the old renders got from clipping.
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

args = [a for a in sys.argv[1:] if not a.startswith("--")]
GLASS = "--glass" in sys.argv
src, catalog = Path(args[0]), Path(args[1])


def bloom(im, strength=0.75, radius=12, threshold=228):
    rgb = im.convert("RGB")
    mask = rgb.convert("L").point(lambda v: 255 if v > threshold else 0)
    bright = Image.composite(rgb, Image.new("RGB", im.size), mask).filter(ImageFilter.GaussianBlur(radius * im.width / 1000))
    out = ImageChops.add(rgb, bright.point(lambda v: int(v * strength)))
    alpha = ImageChops.lighter(im.getchannel("A"), bright.convert("L").point(lambda v: min(255, int(v * strength * 1.1))))
    out.putalpha(alpha)
    return out


catalog.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))

MAX = {"capsule": 1600}

for png in sorted(src.glob("*.png")):
    name = png.stem
    im = Image.open(png).convert("RGBA")
    if GLASS:
        im = bloom(im)
    box = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    im = im.crop(box)
    limit = MAX.get(name, 700)
    if max(im.size) > limit:
        scale = limit / max(im.size)
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    asset = f"Object{name[:1].upper()}{name[1:]}"
    folder = catalog / f"{asset}.imageset"
    folder.mkdir(exist_ok=True)
    im.save(folder / f"{asset}.png", optimize=True)
    contents = {"images": [{"filename": f"{asset}.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2))
    print(f"{asset}: {im.size[0]}x{im.size[1]}")
