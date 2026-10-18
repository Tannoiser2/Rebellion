#!/usr/bin/env python3
"""Carte dell'Ascesa dell'Impero in italiano.

Il modulo TTS ha solo le carte inglesi dell'espansione: qui si cancella il testo inglese dai riquadri
(un filtro «massimo» toglie i tratti scuri lasciando lo sfondo chiaro) e si scrive il testo italiano
tradotto per questa versione (assets/data/carte.json: nome, testo, momento, sopra, sotto).
Le immagini nuove sono assets/cards/it_<id>.jpg e in carte.json il campo img punta a loro
(img_en conserva l'originale).

Uso: python3 tools/italianizza_carte.py   (dopo tools/prepara_asset.py)
"""
import json
import os
import re

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
DATA = os.path.join(ROOT, "assets", "data", "carte.json")
FONT_R = "/usr/share/fonts/truetype/crosextra/Carlito-Regular.ttf"
FONT_B = "/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf"
FONT_I = "/usr/share/fonts/truetype/crosextra/Carlito-Italic.ttf"
FONT_BI = "/usr/share/fonts/truetype/crosextra/Carlito-BoldItalic.ttf"
FONT_SYM = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SYMBOLS = set("✦▲■●")
INK = (34, 34, 34)
_cache = {}


def font(path, size):
    k = (path, size)
    if k not in _cache:
        _cache[k] = ImageFont.truetype(path, size)
    return _cache[k]


def clean(t):
    t = re.sub(r"\s*\(\[(colpo|colpo_diretto|speciale|opspec|intel|diplomazia|logistica)\]\)", "", t)
    t = t.replace("[speciale]", "✦").replace("[triangolo]", "▲").replace("[quadrato]", "■").replace("[cerchio]", "●")
    t = re.sub(r"\[[a-z_]+\]", "", t)
    return t.replace("---", "").strip()


def runs(text, fpath, size):
    """Divide il testo in pezzi con il loro font (i simboli con DejaVu)."""
    out = []
    cur = ""
    for ch in text:
        if ch in SYMBOLS:
            if cur:
                out.append((cur, font(fpath, size)))
                cur = ""
            out.append((ch, font(FONT_SYM, int(size * 0.8))))
        else:
            cur += ch
    if cur:
        out.append((cur, font(fpath, size)))
    return out


def width(text, fpath, size):
    return sum(f.getlength(t) for t, f in runs(text, fpath, size))


def wrap(text, fpath, size, maxw):
    lines = []
    for para in text.split("\n"):
        words = para.split()
        if not words:
            continue
        line = words[0]
        for w in words[1:]:
            if width(line + " " + w, fpath, size) <= maxw:
                line += " " + w
            else:
                lines.append(line)
                line = w
        lines.append(line)
        lines.append(None)          # fine paragrafo
    if lines and lines[-1] is None:
        lines.pop()
    return lines


def layout(blocks, box_w, box_h, smax, smin=8):
    """blocks: [(testo, font, scala)]; sceglie la dimensione più grande che ci sta."""
    for size in range(smax, smin - 1, -1):
        total = 0
        laid = []
        for text, fpath, scale in blocks:
            s = max(smin, int(size * scale))
            ls = wrap(text, fpath, s, box_w)
            lh = int(s * 1.16)
            h = sum(lh if l is not None else int(s * 0.45) for l in ls)
            laid.append((ls, fpath, s, lh, h))
            total += h + int(size * 0.35)
        total -= int(size * 0.35)
        if total <= box_h and all(width(l, fp, s) <= box_w for ls, fp, s, _, _ in laid for l in ls if l):
            return laid, total
    return laid, total


def draw_blocks(img, box, blocks, smax, valign="center", color=INK):
    x0, y0, x1, y1 = [int(v) for v in box]
    laid, total = layout(blocks, x1 - x0, y1 - y0, smax)
    d = ImageDraw.Draw(img)
    y = y0 + ((y1 - y0 - total) // 2 if valign == "center" else 0)
    for ls, fpath, s, lh, h in laid:
        for l in ls:
            if l is None:
                y += int(s * 0.45)
                continue
            w = width(l, fpath, s)
            x = x0 + (x1 - x0 - w) / 2
            for t, f in runs(l, fpath, s):
                dy = int(s * 0.12) if f.path == FONT_SYM else 0
                d.text((x, y + dy), t, font=f, fill=color)
                x += f.getlength(t)
            y += lh
        y += int(s * 0.35)


def draw_line(img, box, text, fpath, smax, color=INK):
    """Una sola riga, rimpicciolita finché ci sta."""
    x0, y0, x1, y1 = [int(v) for v in box]
    size = smax
    while size > 7 and (width(text, fpath, size) > x1 - x0 - 4 or size * 1.1 > y1 - y0):
        size -= 1
    d = ImageDraw.Draw(img)
    w = width(text, fpath, size)
    f = font(fpath, size)
    asc, desc = f.getmetrics()
    d.text((x0 + (x1 - x0 - w) / 2, y0 + (y1 - y0 - asc - desc) / 2 + 1), text, font=f, fill=color)


def erase(img, box, k=11):
    """Toglie il testo scuro dal riquadro chiaro: filtro massimo e una leggera sfocatura."""
    box = tuple(int(v) for v in box)
    reg = img.crop(box)
    reg = reg.filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.GaussianBlur(2))
    img.paste(reg, box[:2])


def rel(img, a, b, c, d):
    W, H = img.size
    return (a * W, b * H, c * W, d * H)


def box_bottom(img, x_rel, y0_rel, lo, hi):
    """Bordo inferiore (scuro) di un riquadro chiaro, scendendo lungo una colonna."""
    W, H = img.size
    g = img.convert("L")
    x = int(x_rel * W)
    run = 0
    for y in range(int(y0_rel * H), int(hi * H)):
        v = sum(g.getpixel((xx, y)) for xx in range(x - 3, x + 4)) / 7
        run = run + 1 if v < 95 else 0
        if run >= 3 and y > lo * H:
            return y - 3
    return int(hi * H)


def make(c):
    src = c.get("img_en") or c["img"]
    path = os.path.join(ROOT, src.replace("res://", ""))
    img = Image.open(path).convert("RGB")
    t = c["tipo"]
    name = c["nome"].upper()
    if t == "missione":
        tb = rel(img, 0.305, 0.03, 0.895, 0.098)
        erase(img, tb, 7)
        draw_line(img, tb, name, FONT_B, 17)
        bb = rel(img, 0.075, 0.585, 0.925, 0.905)
        erase(img, bb)
        draw_blocks(img, bb, [(clean(c["testo"]), FONT_R, 1.0)], 17)
    elif t == "azione":
        bb = rel(img, 0.05, 0.035, 0.95, 0.665)
        erase(img, bb, 13)
        x0, y0, x1, y1 = [int(v) for v in bb]
        # titolo, trattini decorativi, momento e testo
        th = int(0.17 * img.size[1])
        draw_blocks(img, (x0 + 6, y0, x1 - 6, y0 + th - 14), [(name, FONT_B, 1.0)], 30)
        d = ImageDraw.Draw(img)
        yy = y0 + th - 8
        n = 9
        seg = (x1 - x0 - 60) / (n * 1.6)
        for i in range(n):
            xs = x0 + 30 + i * seg * 1.6
            d.rectangle((xs, yy, xs + seg, yy + 3), fill=INK)
        draw_blocks(img, (x0, yy + 8, x1, yy + 8 + int(0.06 * img.size[1])), [(c.get("momento", ""), FONT_BI, 1.0)], 18)
        draw_blocks(img, (x0 + 8, yy + 14 + int(0.06 * img.size[1]), x1 - 8, y1 - 6), [(clean(c["testo"]), FONT_R, 1.0)], 22, "top")
    elif t == "obiettivo":
        yb = box_bottom(img, 0.6, 0.06, 0.2, 0.42)
        tb = (0.255 * img.size[0], 0.035 * img.size[1], 0.965 * img.size[0], yb - 2)
        erase(img, tb)
        draw_blocks(img, tb, [(c.get("momento", ""), FONT_B, 1.0), (clean(c["testo"]), FONT_R, 1.0)], 15)
        nb = rel(img, 0.07, 0.872, 0.93, 0.937)
        erase(img, nb, 7)
        draw_line(img, nb, name, FONT_B, 17)
    elif t == "tattica_av":
        nb = rel(img, 0.1, 0.035, 0.9, 0.11)
        erase(img, nb, 7)
        draw_line(img, nb, name, FONT_B, 19)
        x_top = 0.285 if c.get("sopra_unita") else 0.05
        tb = rel(img, x_top, 0.515, 0.965, 0.738)
        erase(img, tb)
        draw_blocks(img, tb, [(clean(c["sopra"]), FONT_R, 1.0)], 17)
        bb = rel(img, 0.05, 0.752, 0.95, 0.935)
        erase(img, bb)
        draw_blocks(img, bb, [(clean(c["sotto"]), FONT_R, 1.0)], 17)
    out = "assets/cards/it_%s.jpg" % c["id"].replace("#", "_")
    img.save(os.path.join(ROOT, out), quality=88)
    return "res://" + out


def main():
    cards = json.load(open(DATA))
    n = 0
    for c in cards:
        if c.get("scansione") or c.get("set") != "rote" and not c["id"].endswith("_rote"):
            continue
        if c["tipo"] not in ("missione", "azione", "obiettivo", "tattica_av"):
            continue
        if "img_en" not in c:
            c["img_en"] = c["img"]
        c["img"] = make(c)
        n += 1
    json.dump(cards, open(DATA, "w"), ensure_ascii=False, indent=1)
    print("carte italianizzate:", n)


if __name__ == "__main__":
    main()
