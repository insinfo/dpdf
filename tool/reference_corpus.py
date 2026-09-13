# -*- coding: utf-8 -*-
"""Monta um PDF complexo com ferramentas INDEPENDENTES do dpdf.

As imagens saem do Pillow e o PDF sai do PyMuPDF (MuPDF). Nada aqui passa pelo
nosso codigo, que e o ponto: um PDF gerado por nos mesmos nunca exercita as
construcoes que outro produtor usa.
"""
import os
import sys

import fitz
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "build/complexo"
os.makedirs(OUT, exist_ok=True)


def gradiente(w, h, semente=0):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = ((x * 255) // w, (y * 255) // h,
                        ((x + y + semente) * 255) // (w + h))
    return img


def xadrez(w, h, bloco):
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    for y in range(0, h, bloco):
        for x in range(0, w, bloco):
            if ((x // bloco) + (y // bloco)) % 2 == 0:
                d.rectangle([x, y, x + bloco - 1, y + bloco - 1], fill="black")
    return img


def cinza(w, h):
    img = Image.new("L", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = (x * 255) // w
    return img


# --- imagens, uma por codec ------------------------------------------------
caminhos = {}

g = gradiente(240, 160)
g.save(f"{OUT}/foto.jpg", "JPEG", quality=85)
caminhos["jpeg"] = f"{OUT}/foto.jpg"

g.save(f"{OUT}/foto.png", "PNG")
caminhos["png"] = f"{OUT}/foto.png"

xadrez(160, 120, 8).save(f"{OUT}/xadrez.bmp", "BMP")
caminhos["bmp"] = f"{OUT}/xadrez.bmp"

# JPEG 2000 colorido, sem perdas e com perdas
g.save(f"{OUT}/foto_lossless.jp2", "JPEG2000", irreversible=False)
caminhos["jp2_lossless"] = f"{OUT}/foto_lossless.jp2"
g.save(f"{OUT}/foto_lossy.jp2", "JPEG2000", irreversible=True,
       quality_mode="rates", quality_layers=[20])
caminhos["jp2_lossy"] = f"{OUT}/foto_lossy.jp2"

# JPEG 2000 em tons de cinza: e o caso que o j2k publicado quebrava na web
cinza(200, 140).save(f"{OUT}/cinza.jp2", "JPEG2000", irreversible=False)
caminhos["jp2_cinza"] = f"{OUT}/cinza.jp2"

# JPEG progressivo e JPEG em tons de cinza
g.save(f"{OUT}/prog.jpg", "JPEG", progressive=True, quality=80)
caminhos["jpeg_prog"] = f"{OUT}/prog.jpg"
cinza(200, 140).save(f"{OUT}/cinza.jpg", "JPEG", quality=90)
caminhos["jpeg_cinza"] = f"{OUT}/cinza.jpg"

# TIFF com CCITT G4, para o caminho de fax
xadrez(200, 150, 10).convert("1").save(f"{OUT}/fax.tif", "TIFF",
                                       compression="group4")
caminhos["tiff_g4"] = f"{OUT}/fax.tif"

for k, v in sorted(caminhos.items()):
    print(f"  {k:14} {os.path.getsize(v):8} bytes  {os.path.basename(v)}")

# --- o PDF -----------------------------------------------------------------
doc = fitz.open()

# Pagina 1: texto em varias fontes e tamanhos
p = doc.new_page(width=595, height=842)
p.insert_text((50, 60), "Pagina 1 - texto", fontname="helv", fontsize=24)
# Acentos de verdade: sem isto o corpus nao exercita codigo nenhum acima de
# 127, e foi essa a falha que deixou passar um teste que dizia "acentuacao" e
# so tinha ASCII.
p.insert_text((50, 95), "Helvetica com acentos: ação, coração, até",
              fontname="helv", fontsize=11)
p.insert_text((50, 195), "WinAnsi alto: ção éíó "
              "ÀÇÕ «» °±µ €",
              fontname="helv", fontsize=11)
p.insert_text((50, 115), "Times-Roman em italico", fontname="tiit", fontsize=11)
p.insert_text((50, 135), "Courier monoespacado 0123456789",
              fontname="cour", fontsize=11)
p.insert_text((50, 155), "Symbol: abgdez", fontname="symb", fontsize=11)
p.insert_text((50, 175), "ZapfDingbats: 34567", fontname="zadb", fontsize=11)
for i, s in enumerate([6, 8, 10, 14, 20, 28]):
    p.insert_text((50, 210 + i * 34), f"corpo {s}", fontname="helv", fontsize=s)

# Pagina 2: vetores
p = doc.new_page(width=595, height=842)
p.insert_text((50, 50), "Pagina 2 - vetores", fontname="helv", fontsize=18)
sh = p.new_shape()
sh.draw_rect(fitz.Rect(50, 80, 200, 180))
sh.finish(color=(0, 0, 1), fill=(0.8, 0.9, 1), width=2)
sh.draw_circle(fitz.Point(320, 130), 50)
sh.finish(color=(1, 0, 0), fill=(1, 0.9, 0.9), width=3)
sh.draw_bezier(fitz.Point(50, 220), fitz.Point(150, 180),
               fitz.Point(250, 300), fitz.Point(350, 230))
sh.finish(color=(0, 0.5, 0), width=4)
# poligono e linhas tracejadas
sh.draw_polyline([fitz.Point(400, 200), fitz.Point(470, 250),
                  fitz.Point(430, 320), fitz.Point(380, 270)])
sh.finish(color=(0.5, 0, 0.5), fill=(1, 1, 0.8), width=2, closePath=True)
sh.draw_line(fitz.Point(50, 360), fitz.Point(540, 360))
sh.finish(color=(0, 0, 0), width=3, dashes="[6 3] 0")
sh.draw_line(fitz.Point(50, 380), fitz.Point(540, 380))
sh.finish(color=(0, 0, 0), width=1, dashes="[1 2] 0")
# transparencia
sh.draw_rect(fitz.Rect(50, 420, 250, 520))
sh.finish(color=None, fill=(1, 0, 0), fill_opacity=0.5)
sh.draw_rect(fitz.Rect(150, 470, 350, 570))
sh.finish(color=None, fill=(0, 0, 1), fill_opacity=0.5)
sh.commit()

# Pagina 3: imagens rasterizadas, uma por codec
p = doc.new_page(width=595, height=842)
p.insert_text((50, 40), "Pagina 3 - imagens", fontname="helv", fontsize=18)
layout = [
    ("jpeg", 50, 60), ("png", 300, 60),
    ("bmp", 50, 240), ("tiff_g4", 300, 240),
    ("jpeg_prog", 50, 420), ("jpeg_cinza", 300, 420),
]
for chave, x, y in layout:
    r = fitz.Rect(x, y, x + 220, y + 150)
    p.insert_image(r, filename=caminhos[chave])
    p.insert_text((x, y + 165), chave, fontname="helv", fontsize=9)

# Pagina 4: so JPEG 2000, que e o codec mais delicado
p = doc.new_page(width=595, height=842)
p.insert_text((50, 40), "Pagina 4 - JPEG 2000", fontname="helv", fontsize=18)
for i, chave in enumerate(["jp2_lossless", "jp2_lossy", "jp2_cinza"]):
    y = 60 + i * 200
    p.insert_image(fitz.Rect(50, y, 320, y + 170), filename=caminhos[chave])
    p.insert_text((340, y + 20), chave, fontname="helv", fontsize=11)

doc.set_metadata({"title": "Teste complexo dpdf", "author": "PyMuPDF",
                  "subject": "codecs e vetores"})
doc.save(f"{OUT}/complexo.pdf", garbage=0, deflate=True)
doc.close()
print(f"\nPDF: {OUT}/complexo.pdf  {os.path.getsize(f'{OUT}/complexo.pdf')} bytes")
