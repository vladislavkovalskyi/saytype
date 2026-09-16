#!/usr/bin/env python3
"""Renders the DMG window background: background.png (660x400) and background@2x.png.

    python3 packaging/dmg/make-background.py

Needs Pillow only. The output is deterministic: dithering noise uses a fixed seed.
Slot positions must match the create-dmg call in scripts/release.sh.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FONT = ROOT / "App/Resources/Fonts/Onest.ttf"

# Layout in points. Finder places icons by their centre.
WIDTH, HEIGHT = 660, 400
APP_SLOT = (170, 180)
APPLICATIONS_SLOT = (490, 180)
ICON_SIZE = 128
WORDMARK_Y = 344

# Palette: the ember world of the app.
TOP = (0x2A, 0x12, 0x16)
BOTTOM = (0x12, 0x0D, 0x10)
GLOW = (0xE0, 0x60, 0x2F)
INK = (0xF6, 0xD8, 0xC8)

SUPERSAMPLE = 4


def lerp(a, b, t):
    return a + (b - a) * t


def ground(scale):
    """Gradient, glow and vignette, computed per pixel and dithered to 8 bits."""
    w, h = WIDTH * scale, HEIGHT * scale
    rng = random.Random(0x2A1216)
    gx, gy = APP_SLOT[0] + 70, APP_SLOT[1] - 10
    rx, ry = 330.0, 210.0
    buf = bytearray(w * h * 3)
    i = 0
    for py in range(h):
        y = (py + 0.5) / scale
        v = y / HEIGHT
        for px in range(w):
            x = (px + 0.5) / scale
            u = x / WIDTH
            # Mostly top to bottom, leaning slightly to the right.
            t = min(1.0, max(0.0, 0.78 * v + 0.22 * u))
            t = t * t * (3 - 2 * t)
            dx, dy = (x - gx) / rx, (y - gy) / ry
            glow = 0.13 * math.exp(-2.2 * (dx * dx + dy * dy))
            cx, cy = u - 0.5, v - 0.5
            vignette = 1.0 - 0.28 * (cx * cx + cy * cy)
            for c in range(3):
                base = lerp(TOP[c], BOTTOM[c], t)
                value = lerp(base, GLOW[c], glow) * vignette
                # Triangular dither keeps the dark gradient free of bands.
                value += rng.random() - rng.random()
                buf[i] = 0 if value < 0 else 255 if value > 255 else int(value + 0.5)
                i += 1
    return Image.frombytes("RGB", (w, h), bytes(buf))


def overlay(scale):
    """Arrow and wordmark, drawn supersampled on a transparent layer."""
    s = scale * SUPERSAMPLE
    layer = Image.new("RGBA", (WIDTH * s, HEIGHT * s), (0, 0, 0, 0))

    # Arrow: a hairline that fades in from the app towards Applications.
    gap = 30
    x0 = APP_SLOT[0] + ICON_SIZE / 2 + gap
    x1 = APPLICATIONS_SLOT[0] - ICON_SIZE / 2 - gap
    y = (APP_SLOT[1] + APPLICATIONS_SLOT[1]) / 2
    stroke = 1.5
    head = 8.0
    line = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(line)
    steps = 96
    for k in range(steps):
        a = x0 + (x1 - x0) * k / steps
        b = x0 + (x1 - x0) * (k + 1) / steps
        alpha = 0.10 + 0.45 * ((k + 0.5) / steps) ** 1.4
        draw.line([(a * s, y * s), (b * s, y * s)], fill=INK + (round(255 * alpha),), width=round(stroke * s))
    tip_alpha = round(255 * 0.55)
    for sign in (-1, 1):
        ex = x1 - head * math.cos(math.radians(38))
        ey = y + sign * head * math.sin(math.radians(38))
        draw.line([(x1 * s, y * s), (ex * s, ey * s)], fill=INK + (tip_alpha,), width=round(stroke * s))
    r = stroke * s / 2
    for px, py in [(x1, y)] + [
        (x1 - head * math.cos(math.radians(38)), y + sign * head * math.sin(math.radians(38))) for sign in (-1, 1)
    ]:
        draw.ellipse([px * s - r, py * s - r, px * s + r, py * s + r], fill=INK + (tip_alpha,))
    layer.alpha_composite(line)

    # Wordmark.
    font = ImageFont.truetype(str(FONT), 15 * s)
    font.set_variation_by_axes([500])
    text = "voicemode"
    tracking = 0.02 * 15 * s
    widths = [font.getlength(ch) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    draw = ImageDraw.Draw(layer)
    x = WIDTH * s / 2 - total / 2
    for ch, cw in zip(text, widths):
        draw.text((x, WORDMARK_Y * s), ch, font=font, fill=INK + (round(255 * 0.58),), anchor="ls")
        x += cw + tracking

    return layer.resize((WIDTH * scale, HEIGHT * scale), Image.LANCZOS)


def render(scale):
    image = ground(scale).convert("RGBA")
    image.alpha_composite(overlay(scale))
    return image.convert("RGB")


def main():
    for scale, name in [(1, "background.png"), (2, "background@2x.png")]:
        path = HERE / name
        render(scale).save(path, dpi=(72 * scale, 72 * scale), optimize=True)
        print(f"{path.relative_to(ROOT)}  {WIDTH * scale}x{HEIGHT * scale}")


if __name__ == "__main__":
    main()
