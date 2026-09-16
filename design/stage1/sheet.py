# Tiles screenshots into one contact sheet.
#   python3 sheet.py out.png cols scale a.png b.png ...
import sys
from PIL import Image
out, cols, scale, *files = sys.argv[1:]
cols, scale = int(cols), float(scale)
ims = [Image.open(f).convert("RGB") for f in files]
ims = [im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS) for im in ims]
w = max(i.width for i in ims); h = max(i.height for i in ims)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows), (233, 229, 223))
for n, im in enumerate(ims):
    sheet.paste(im, ((n % cols) * w, (n // cols) * h))
sheet.save(out)
print(out)
