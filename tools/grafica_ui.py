#!/usr/bin/env python3
"""Disegna l'icona e la schermata di avvio (stelle, nebulose e il titolo in Orbitron)."""
import io
import random
from fontTools.ttLib import TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


def ttf(p):
    f = TTFont(p)
    f.flavor = None
    b = io.BytesIO()
    f.save(b)
    b.seek(0)
    return b.getvalue()


def font(data, size):
    return ImageFont.truetype(io.BytesIO(data), size)


def stars(w, h, n, seed=1):
    im = Image.new("RGB", (w, h), (5, 7, 13))
    d = ImageDraw.Draw(im)
    r = random.Random(seed)
    for _ in range(n):
        x, y = r.random() * w, r.random() * h
        s = r.choice([0.6, 0.8, 1, 1.4, 2])
        c = int(120 + r.random() * 135)
        d.ellipse((x - s, y - s, x + s, y + s), fill=(c, c, min(255, c + 20)))
    return im


blk = ttf("assets/fonts/Orbitron-Black.woff2")
bold = ttf("assets/fonts/Orbitron-Bold.woff2")
W, H = 1920, 1080
im = stars(W, H, 900)
glow = Image.new("RGB", (W, H), (0, 0, 0))
g = ImageDraw.Draw(glow)
g.ellipse((1100, -200, 2300, 900), fill=(70, 20, 15))
g.ellipse((-400, 500, 700, 1500), fill=(15, 35, 80))
im = ImageChops.add(im, glow.filter(ImageFilter.GaussianBlur(160)))
d = ImageDraw.Draw(im)
f1 = font(blk, 170)
f2 = font(bold, 46)
t = "REBELLION"
bb = d.textbbox((0, 0), t, font=f1)
x = (W - (bb[2] - bb[0])) // 2
y = 420
sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(sh).text((x, y), t, font=f1, fill=(127, 216, 255, 255))
sh = sh.filter(ImageFilter.GaussianBlur(18))
im.paste(sh, (0, 0), sh)
d.text((x, y), t, font=f1, fill=(235, 240, 248))
t2 = "GUERRE STELLARI"
bb2 = d.textbbox((0, 0), t2, font=f2)
d.text(((W - (bb2[2] - bb2[0])) // 2, 360), t2, font=f2, fill=(242, 193, 78))
im.save("assets/ui/splash.png")
ic = stars(256, 256, 60, 3)
d = ImageDraw.Draw(ic)
d.ellipse((28, 28, 228, 228), outline=(232, 85, 62), width=10)
fi = font(blk, 120)
bb = d.textbbox((0, 0), "R", font=fi)
d.text(((256 - (bb[2] - bb[0])) // 2 - bb[0], (256 - (bb[3] - bb[1])) // 2 - bb[1]), "R", font=fi, fill=(235, 240, 248))
ic.save("assets/ui/icon.png")
print("ok")
