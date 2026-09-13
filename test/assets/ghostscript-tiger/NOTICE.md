# Ghostscript Tiger

`ghostscript-tiger.svg` — 68 630 bytes,
sha256 `5211e169283f43ab8ad7ea7998d917d5fbb3c568ac85c1a0217e86792822684d` (completo abaixo).

Origem: <https://commons.wikimedia.org/wiki/File:Ghostscript_Tiger.svg>,
derivado de `examples/tiger.eps` do Ghostscript.

Autoria: Ghostscript authors.

## Licença

**GNU Affero General Public License**, texto integral em
`LICENSE.AGPL-3.0.txt`. Não é domínio público, ao contrário das demais
ilustrações usadas como corpus neste projeto.

## Por que está aqui, e fora do pacote publicado

Este diretório é versionado, para que a suíte rode em qualquer clone, e
consta do `.pubignore`, então não viaja no pacote publicado no pub.dev.

A razão é prática, não jurídica: incluir um asset de teste ao lado de código
MIT é mera agregação (AGPL-3.0, seção 5), mas um arquivo AGPL dentro de um
pacote publicado dispara alarme nos verificadores de licença que muitos
consumidores rodam na integração contínua. Deixando-o de fora do pacote, a
questão não chega a quem depende do `dpdf`, e os testes continuam podendo
usá-lo.

Toda ilustração em `test/assets` que **não** esteja neste diretório é de
domínio público; esta é a única exceção, e é por isso que ela fica separada
numa pasta com a licença ao lado.

## Por que vale tê-lo

É a imagem de esforço clássica do PostScript e do PDF: centenas de caminhos
preenchidos, muitos com contorno, e é o desenho com que geradores de PDF são
comparados há décadas.
