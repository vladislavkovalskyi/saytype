"""Builds README images from real overlay renders.

    saytype.app/Contents/MacOS/saytype --snapshot-overlays <snap> --transparent -AppleLanguages "(en)"
    python3 design/media/readme_media.py <snap> docs/media

Everything is drawn at 2x: one point in the app is two pixels here.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SNAP, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
SF = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(size, path=SF):
    return ImageFont.truetype(path, size)


def wallpaper(w, h):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    base = np.zeros((h, w, 3), np.float32)
    top, bottom = np.array([15, 26, 38]), np.array([30, 20, 36])
    t = (x / w * 0.35 + y / h * 0.65)[..., None]
    base += top * (1 - t) + bottom * t

    def glow(cx, cy, r, color, strength):
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
        a = np.clip(1 - d, 0, 1) ** 2 * strength
        return a[..., None] * (np.array(color, np.float32) - base)

    base += glow(w * 0.12, h * 1.08, w * 0.62, (122, 52, 70), 0.9)
    base += glow(w * 0.92, -h * 0.12, w * 0.6, (38, 96, 116), 0.85)
    base += glow(w * 0.55, h * 0.95, w * 0.45, (170, 80, 50), 0.35)
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def menubar(img, notch_center_x):
    draw = ImageDraw.Draw(img)
    w = img.width
    bar = Image.new("RGBA", (w, 64), (0, 0, 0, 40))
    img.alpha_composite(bar)
    f = font(26)
    x = 44
    for item in ["Terminal", "Shell", "Edit", "View", "Window", "Help"]:
        draw.text((x, 17), item, font=f, fill=(255, 255, 255, 240))
        x += draw.textlength(item, font=f) + 40
    right = "Wed 16 Sep  15:20"
    rw = draw.textlength(right, font=f)
    draw.text((w - 36 - rw, 17), right, font=f, fill=(255, 255, 255, 240))
    # status icons: battery, wi-fi, saytype waveform
    bx = w - 36 - rw - 90
    draw.rounded_rectangle((bx, 22, bx + 46, 44), radius=7, outline=(255, 255, 255, 150), width=2)
    draw.rounded_rectangle((bx + 5, 27, bx + 34, 39), radius=3, fill="white")
    wx = bx - 70
    for i, hgt in enumerate([8, 16, 26, 14, 6]):
        draw.rounded_rectangle((wx + i * 8, 33 - hgt / 2, wx + i * 8 + 4, 33 + hgt / 2), radius=2, fill="white")


def shadowed(layer, radius=40, offset=(0, 30), opacity=150):
    alpha = layer.getchannel("A")
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda v: v * opacity // 255))
    canvas = Image.new("RGBA", (layer.width + radius * 4, layer.height + radius * 4), (0, 0, 0, 0))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius)) if False else shadow, (radius * 2 + offset[0], radius * 2 + offset[1]))
    canvas = canvas.filter(ImageFilter.GaussianBlur(radius))
    canvas.alpha_composite(layer, (radius * 2, radius * 2))
    return canvas, radius * 2


def terminal(w, h, lines):
    win = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(win)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=24, fill=(24, 23, 29, 244), outline=(255, 255, 255, 38), width=2)
    d.rounded_rectangle((0, 0, w - 1, 60), radius=24, fill=(42, 41, 48, 255))
    d.rectangle((0, 36, w - 1, 60), fill=(42, 41, 48, 255))
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        d.ellipse((26 + i * 38, 19, 48 + i * 38, 41), fill=c)
    title = "zsh — ~/saytype"
    tf = font(24)
    d.text(((w - d.textlength(title, font=tf)) / 2, 16), title, font=tf, fill=(185, 185, 194))
    mf = font(27, MONO)
    y = 96
    for text, color in lines:
        d.text((40, y), text, font=mf, fill=color)
        y += 44
    return win


def crop_alpha(img, pad=0):
    box = img.getchannel("A").getbbox()
    l, t, r, b = box
    return img.crop((max(l - pad, 0), max(t - pad, 0), min(r + pad, img.width), min(b + pad, img.height)))


def island(name):
    return Image.open(SNAP / f"island-{name}.png").convert("RGBA")


# ---------- hero ----------
W, H = 2400, 1030
hero = wallpaper(W, H)
dim, acc, ink, code = (124, 124, 136), (255, 154, 92), (225, 225, 232), (142, 240, 176)
term = terminal(1400, 600, [
    ("Last login: Wed Sep 16 15:02 on ttys003", dim),
    ("~/saytype git:(main) claude", ink),
    ("", ink),
    ("› Сегодня три дела:", ink),
    ("  1. Обнови Next.js.", ink),
    ("  2. Задеплой feature/auth на Vercel.", ink),
    ("  3. Скинь превью.", ink),
    ("› ", acc),
])
framed, off = shadowed(term, radius=34, offset=(0, 26), opacity=170)
hero.alpha_composite(framed, ((W - 1400) // 2 - off, 330 - off))
menubar(hero, W // 2)
live = island("5-listening")
hero.alpha_composite(live, ((W - live.width) // 2, 0))
hero.convert("RGB").resize((1760, round(1760 * H / W)), Image.LANCZOS).save(OUT / "hero.png", optimize=True)

# ---------- table tiles ----------
def island_tile(name, height, width=1500):
    tile = wallpaper(width, height)
    menubar(tile, width // 2)
    img = island(name)
    tile.alpha_composite(img, ((width - img.width) // 2, 0))
    return tile.convert("RGB").resize((1200, round(1200 * height / width)), Image.LANCZOS)

island_tile("3-panel", 650).save(OUT / "island-panel.png", optimize=True)
island_tile("5-listening", 650).save(OUT / "island-live.png", optimize=True)

pill = Image.open(SNAP / "pill-5-listening.png").convert("RGBA")
tile = wallpaper(1200, 520)
dock = Image.new("RGBA", (760, 120), (0, 0, 0, 0))
dd = ImageDraw.Draw(dock)
dd.rounded_rectangle((0, 0, 759, 119), radius=40, fill=(255, 255, 255, 46), outline=(255, 255, 255, 70), width=2)
colors = [((110, 195, 255), (42, 115, 232)), ((254, 254, 254), (216, 216, 220)), ((59, 59, 66), (22, 22, 26)), ((255, 207, 90), (242, 154, 30)), ((126, 224, 142), (37, 165, 90)), ((180, 140, 255), (111, 69, 216)), ((255, 154, 138), (224, 72, 90)), ((95, 224, 232), (20, 138, 166))]
for i, (a, b) in enumerate(colors):
    x = 26 + i * 90
    dd.rounded_rectangle((x, 16, x + 84, 100), radius=20, fill=b)
tile.alpha_composite(dock, ((1200 - 760) // 2, 520 - 136))
tile.alpha_composite(pill, ((1200 - pill.width) // 2, 520 - 136 - pill.height + 20))
tile.convert("RGB").save(OUT / "pill.png", optimize=True)

print("wrote", sorted(p.name for p in OUT.glob("*.png")))
