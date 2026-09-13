"""Compara a nossa renderizacao contra duas implementacoes independentes.

Divergir do MuPDF E do pdf.js ao mesmo tempo e sinal forte de defeito nosso.
Divergir de apenas um pede investigacao antes de concluir qualquer coisa: ja
aconteceu de o MuPDF ser o que errava (veja README_reference_corpus.md).
"""
import sys, os
from PIL import Image

def carrega(p, tam):
    im = Image.open(p).convert('L')
    if im.size != tam:
        im = im.resize(tam, Image.LANCZOS)
    return im.load(), tam

def compara(a, b, tam):
    pa, _ = carrega(a, tam)
    pb, _ = carrega(b, tam)
    w, h = tam
    dif = 0; soma = 0; mx = 0
    for y in range(h):
        for x in range(w):
            d = abs(pa[x, y] - pb[x, y])
            if d >= 16: dif += 1
            soma += d
            if d > mx: mx = d
    n = w * h
    return 100.0 * dif / n, soma / n, mx

nosso, mupdf, pdfjs = sys.argv[1], sys.argv[2], sys.argv[3]
print(f'{"pag":>4} {"nosso~mupdf":>22} {"nosso~pdfjs":>22}')
print(f'{"":>4} {"%dif   media   max":>22} {"%dif   media   max":>22}')
i = 1
while os.path.exists(f'{nosso}/p{i}.png'):
    ref = Image.open(f'{nosso}/p{i}.png')
    tam = ref.size
    linha = f'{i:>4}'
    for outro in (mupdf, pdfjs):
        c = f'{outro}/p{i}.png'
        if not os.path.exists(c):
            linha += f'{"ausente":>23}'
            continue
        pd, md, mx = compara(f'{nosso}/p{i}.png', c, tam)
        linha += f'  {pd:6.2f}% {md:7.2f} {mx:5d}'
    print(linha)
    i += 1
