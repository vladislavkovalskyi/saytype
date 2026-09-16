# Adds a soft glow around bright pixels of an RGBA render.
#   python3 bloom.py in.png out.png [strength] [radius]
import sys
from PIL import Image, ImageChops, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
strength = float(sys.argv[3]) if len(sys.argv) > 3 else 0.9
radius = float(sys.argv[4]) if len(sys.argv) > 4 else 18
im = Image.open(src).convert("RGBA")
rgb = im.convert("RGB")
lum = rgb.convert("L").point(lambda v: 255 if v > 248 else 0)
bright = Image.composite(rgb, Image.new("RGB", im.size), lum)
glow = bright.filter(ImageFilter.GaussianBlur(radius))
glow_alpha = glow.convert("L").point(lambda v: min(255, int(v * strength * 1.1)))
out = ImageChops.add(rgb, glow.point(lambda v: int(v * strength)))
alpha = ImageChops.lighter(im.getchannel("A"), glow_alpha)
out.putalpha(alpha)
out.save(dst)
print(dst)
