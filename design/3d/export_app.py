# Copies Blender renders into the app's asset catalog as trimmed PNG image sets.
#   python3 design/3d/export_app.py design/3d/renders App/Resources/Assets.xcassets
import json
import sys
from pathlib import Path

from PIL import Image

src, catalog = Path(sys.argv[1]), Path(sys.argv[2])
catalog.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))

MAX = {"capsule": 1600}

for png in sorted(src.glob("*.png")):
    name = png.stem
    im = Image.open(png).convert("RGBA")
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
