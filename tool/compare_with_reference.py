# -*- coding: utf-8 -*-
"""Renderiza com o MuPDF e compara pixel a pixel com o que o dpdf produziu."""
import os
import sys

import fitz
from PIL import Image, ImageChops

PDF = sys.argv[1] if len(sys.argv) > 1 else "build/complexo/complexo.pdf"
NOSSO = sys.argv[2] if len(sys.argv) > 2 else "build/complexo/nosso"
REF = sys.argv[3] if len(sys.argv) > 3 else "build/complexo/mupdf"
DPI = float(sys.argv[4]) if len(sys.argv) > 4 else 72.0
os.makedirs(REF, exist_ok=True)

doc = fitz.open(PDF)
print(f"{'pag':>4} {'tamanho':>12} {'iguais':>8} {'difer':>8} "
      f"{'%dif':>7} {'maxdif':>7}  media")
for i, page in enumerate(doc, 1):
    pix = page.get_pixmap(dpi=int(DPI))
    pix.save(f"{REF}/p{i}.png")

    nosso_path = f"{NOSSO}/p{i}.png"
    if not os.path.exists(nosso_path):
        print(f"{i:>4}  (nosso nao renderizou)")
        continue

    a = Image.open(f"{REF}/p{i}.png").convert("RGB")
    b = Image.open(nosso_path).convert("RGB")
    if a.size != b.size:
        print(f"{i:>4}  TAMANHO DIFERE: mupdf={a.size} nosso={b.size}")
        continue

    diff = ImageChops.difference(a, b)
    hist = diff.convert("L").histogram()
    total = a.size[0] * a.size[1]
    iguais = hist[0]
    difer = total - iguais
    maxdif = max(i2 for i2, c in enumerate(hist) if c) if difer else 0
    soma = sum(v * c for v, c in enumerate(hist))
    print(f"{i:>4} {str(a.size):>12} {iguais:>8} {difer:>8} "
          f"{100.0*difer/total:>6.1f}% {maxdif:>7}  {soma/total:>5.1f}")
    diff.save(f"{REF}/diff_p{i}.png")
doc.close()
