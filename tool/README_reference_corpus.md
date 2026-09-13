# Comparação contra um produtor e um renderizador independentes

Estes quatro scripts montam um PDF com ferramentas de fora deste projeto, renderizam com o
`dpdf` e comparam contra a renderização do MuPDF, região por região.

Eles existem porque a suíte de testes tem um ponto cego estrutural: **todo o corpus de teste
é gerado pelo próprio pacote**. Um PDF que nós escrevemos só exercita as construções que nós
escolhemos escrever. Dois defeitos reais do traçador passaram por 2 715 testes e apareceram
no primeiro PDF produzido por outra ferramenta:

- traçar um contorno fechado saturava a cobertura parcial, e uma linha de 1 px saía com 2 px.
  O gatilho é `h` antes de `S`, que este pacote nunca emitia e o PyMuPDF emite em toda linha;
- traçar uma curva perdia largura, e com junção *miter* — que é o padrão do PDF — perdia
  metade.

## Dependências

Python com `PyMuPDF` e `Pillow`. Nenhuma delas entra no pacote; são só para este arnês.

```bash
pip install pymupdf pillow
```

## Uso

```bash
python tool/reference_corpus.py build/complexo         # gera imagens e o PDF
dart run tool/render_corpus.dart \
    build/complexo/complexo.pdf build/complexo/nosso 72
python tool/compare_with_reference.py \
    build/complexo/complexo.pdf build/complexo/nosso build/complexo/mupdf 72
python tool/compare_regions.py                          # por região nomeada
```

`build/` é ignorado pelo git, então nada disso polui o repositório.

## Como ler o resultado

A comparação página inteira dá percentual de pixels diferentes e diferença média. **Média
baixa com percentual alto é antisserrilhamento**, não defeito; o que denuncia problema real é
uma região inteira divergindo ou uma diferença grande concentrada.

`compare_regions.py` separa por região nomeada, que é o que torna o resultado acionável: ele
mostra, por exemplo, que imagens e transparência batem enquanto círculo e Bézier não —
apontando o traçado de curvas em vez de deixar um número agregado sem explicação.

Medir cobertura absoluta também vale: somar `(255 - valor) / 255` ao longo de um corte
perpendicular a um traço de largura `w` tem de dar exatamente `w`. Foi essa medida que
transformou "parece mais fino" em "perde metade da largura com junção miter".
