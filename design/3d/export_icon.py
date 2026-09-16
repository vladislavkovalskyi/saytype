# Builds the macOS app icon from the face-on render.
#   python3 design/3d/export_icon.py design/3d/renders/appicon_front.png App/Resources/Assets.xcassets/AppIcon.appiconset
#
# macOS 26 puts icons that are not squircle-shaped into a grey container, so the render
# is masked to the squircle on Apple's 1024 grid (824 content, 100 margin) with a drop shadow.
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

src, out = Path(sys.argv[1]), Path(sys.argv[2])
CANVAS, CONTENT = 1024, 824
SUPER = 4


def squircle(size, n=5.0):
    s = size * SUPER
    t = (np.arange(s) + 0.5) / s * 2 - 1
    x, y = np.meshgrid(t, t)
    inside = (np.abs(x) ** n + np.abs(y) ** n) <= 1
    mask = Image.fromarray((inside * 255).astype(np.uint8), "L")
    return mask.resize((size, size), Image.LANCZOS)


def ember_depth(im):
    """Deepens the flat orange toward the ember world: warm top, red bottom. Bars stay white."""
    rgb = np.asarray(im.convert("RGB")).astype(np.float32) / 255
    h = rgb.shape[0]
    ramp = np.linspace(0, 1, h)[:, None, None]
    top, bottom = np.array([1.0, 0.72, 0.42]), np.array([0.86, 0.32, 0.22])
    tint = top * (1 - ramp) + bottom * ramp
    whiteness = np.clip((rgb.min(axis=2, keepdims=True) - 0.62) / 0.3, 0, 1)
    shaded = rgb * (0.55 + 0.45 * tint / tint.max())
    shaded = shaded * (1 - 0.35) + (rgb * tint * 1.25) * 0.35
    result = rgb * whiteness + np.clip(shaded, 0, 1) * (1 - whiteness)
    return _with_alpha(result, np.asarray(im.getchannel("A")))


def _with_alpha(rgb, alpha):
    im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    im.putalpha(Image.fromarray(alpha))
    return im


render = Image.open(src).convert("RGBA")
render = render.crop(render.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox())
face = ember_depth(render.resize((CONTENT, CONTENT), Image.LANCZOS))
mask = squircle(CONTENT)
face.putalpha(mask)

icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow_alpha = Image.new("L", (CANVAS, CANVAS), 0)
shadow_alpha.paste(mask.point(lambda v: v * 0.32), (100, 112))
shadow.putalpha(shadow_alpha.filter(ImageFilter.GaussianBlur(14)))
icon.alpha_composite(shadow)
icon.alpha_composite(face, (100, 100))

out.mkdir(parents=True, exist_ok=True)
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        icon.resize((px, px), Image.LANCZOS).save(out / name, optimize=True)
icon.save(src.with_name("appicon_final.png"))
print("icon written to", out)
