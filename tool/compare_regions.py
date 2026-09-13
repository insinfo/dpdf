# -*- coding: utf-8 -*-
"""Compara regioes nomeadas, para separar o que e texto do que e imagem."""
import sys

from PIL import Image

REF = "build/complexo/mupdf"
NOSSO = "build/complexo/nosso"

# (pagina, rotulo, x0, y0, x1, y1) em pixels a 72 dpi, y para baixo
REGIOES = [
    (3, "jpeg",        50,  60, 270, 210),
    (3, "png",        300,  60, 520, 210),
    (3, "bmp",         50, 240, 270, 390),
    (3, "tiff_g4",    300, 240, 520, 390),
    (3, "jpeg_prog",   50, 420, 270, 570),
    (3, "jpeg_cinza", 300, 420, 520, 570),
    (4, "jp2_lossless", 50,  60, 320, 230),
    (4, "jp2_lossy",    50, 260, 320, 430),
    (4, "jp2_cinza",    50, 460, 320, 630),
    (2, "retangulo",   50,  80, 200, 180),
    (2, "circulo",    270,  80, 370, 180),
    (2, "bezier",      50, 180, 350, 310),
    (2, "poligono",   375, 195, 475, 325),
    (2, "tracejado",   50, 350, 540, 390),
    (2, "transparencia", 50, 420, 350, 570),
]

print(f"{'pag':>3} {'regiao':<14} {'%dif>=16':>9} {'%dif>=64':>9} "
      f"{'media':>6} {'max':>4}")
cache = {}
for pag, rot, x0, y0, x1, y1 in REGIOES:
    if pag not in cache:
        cache[pag] = (Image.open(f"{REF}/p{pag}.png").convert("RGB"),
                      Image.open(f"{NOSSO}/p{pag}.png").convert("RGB"))
    a, b = cache[pag]
    ca = a.crop((x0, y0, x1, y1)).load()
    cb = b.crop((x0, y0, x1, y1)).load()
    w, h = x1 - x0, y1 - y0
    n16 = n64 = 0
    soma = 0
    mx = 0
    for y in range(h):
        for x in range(w):
            ra, ga, ba = ca[x, y]
            rb, gb, bb = cb[x, y]
            d = max(abs(ra - rb), abs(ga - gb), abs(ba - bb))
            soma += d
            mx = max(mx, d)
            if d >= 16:
                n16 += 1
            if d >= 64:
                n64 += 1
    tot = w * h
    print(f"{pag:>3} {rot:<14} {100.0*n16/tot:>8.2f}% {100.0*n64/tot:>8.2f}% "
          f"{soma/tot:>6.2f} {mx:>4}")
