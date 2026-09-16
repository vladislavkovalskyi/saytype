"""README tour: window screenshots as WebP and a looping GIF that pages through the app.

    # window captures with shadow, from preview launches (mock data only):
    #   saytype --show-onboarding N | --show-main SECTION  -AppleLanguages "(en)"
    #   screencapture -l<window> -x shots/en-onb3.png
    python3 design/media/tour_media.py <shots> docs/media

Needs Pillow, cwebp and gifski.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

SHOTS, OUT = Path(sys.argv[1]), Path(sys.argv[2])
ROOT = Path(__file__).resolve().parents[2]

SETUP = ["onb1", "onb2", "onb3", "onb4", "onb5", "onb6", "onb7", "onb8"]
SECTIONS = ["home", "keys", "text", "dictionary", "history", "model", "permissions", "about"]
TOUR = ["onb1", "onb2", "onb3", "onb4", "onb5", "onb6", "onb8", "home", "keys", "text", "dictionary", "history", "model", "about"]

FPS = 12
HOLD = 26        # frames per slide, ~2.2 s
FADE = 6         # page transition frames
GIF_WIDTH = 840


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


def webp(image, path, width=1400):
    image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "frame.png"
        image.save(png)
        subprocess.run(["cwebp", "-quiet", "-q", "88", "-alpha_q", "90", "-m", "6", str(png), "-o", str(path)], check=True)


def fitted(capture, canvas):
    scale = min(canvas.width * 0.9 / capture.width, canvas.height * 0.94 / capture.height)
    return capture.resize((round(capture.width * scale), round(capture.height * scale)), Image.LANCZOS)


def frame(canvas, shots):
    """Windows over the wallpaper; `shots` is a list of (image, horizontal offset in px)."""
    out = canvas.copy()
    for shot, dx in shots:
        x = (canvas.width - shot.width) // 2 + round(dx)
        out.alpha_composite(shot, (x, (canvas.height - shot.height) // 2))
    return out.convert("RGB").resize((GIF_WIDTH, round(GIF_WIDTH * canvas.height / canvas.width)), Image.LANCZOS)


def ease(t):
    return t * t * (3 - 2 * t)


for lang in ("en", "ru"):
    folder = OUT / lang
    folder.mkdir(parents=True, exist_ok=True)
    captures = {name: Image.open(SHOTS / f"{lang}-{name}.png").convert("RGBA") for name in SETUP + SECTIONS}

    for i, name in enumerate(SETUP, 1):
        webp(captures[name], folder / f"setup-{i}.webp")
    for name in SECTIONS:
        webp(captures[name], folder / f"section-{name}.webp")

    canvas = wallpaper(2000, 1280)
    shots = [fitted(captures[name], canvas) for name in TOUR]
    frames_dir = Path(tempfile.mkdtemp())
    n = 0
    for i, current in enumerate(shots):
        following = shots[(i + 1) % len(shots)]
        still = frame(canvas, [(current, 0)])
        for _ in range(HOLD):
            still.save(frames_dir / f"{n:05d}.png")
            n += 1
        # Page to the next window: it pushes the current one out to the left.
        for k in range(1, FADE + 1):
            offset = ease(k / (FADE + 1)) * canvas.width
            frame(canvas, [(current, -offset), (following, canvas.width - offset)]).save(frames_dir / f"{n:05d}.png")
            n += 1
    gif = OUT / f"tour-{lang}.gif"
    subprocess.run(["gifski", "--quiet", "--fps", str(FPS), "--quality", "80", "--width", str(GIF_WIDTH), "-o", str(gif)]
                   + sorted(str(p) for p in frames_dir.glob("*.png")), check=True)
    shutil.rmtree(frames_dir)
    print(lang, gif.stat().st_size // 1024, "KB,", n, "frames")
