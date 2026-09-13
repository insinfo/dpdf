# Avisos de recursos distribuídos

Estes termos se aplicam aos recursos identificados abaixo, incluindo os dados
Adobe embutidos em `lib/src/io/resources/embedded_font_resources.dart` e os
programas de fonte URW embutidos em
`lib/src/render/resources/standard_font_programs_vm.dart`.
Preserve estes avisos também ao redistribuir aplicações compiladas que incluam
esses dados. Este inventário não atribui uma licença ao restante do código.

## Adobe Glyph List

Arquivo: `lib/src/io/resources/AdobeGlyphList.txt`.
Origem verificada: https://github.com/adobe-type-tools/agl-aglfn/blob/4036a9ca80a62f64f9de4f7321a9a045ad0ecfd6/glyphlist.txt
A cópia preserva duplicatas e os aliases Delta=0394, Omega=03A9 e mu=03BC,
identificados no próprio cabeçalho como diferenças do upstream.

-----------------------------------------------------------
Copyright 2002-2019 Adobe (http://www.adobe.com/).

Redistribution and use in source and binary forms, with or
without modification, are permitted provided that the
following conditions are met:

Redistributions of source code must retain the above
copyright notice, this list of conditions and the following
disclaimer.

Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following
disclaimer in the documentation and/or other materials
provided with the distribution.

Neither the name of Adobe nor the names of its contributors
may be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-----------------------------------------------------------

## Métricas Helvetica AFM

Arquivo: `lib/src/io/resources/afm/Helvetica.afm`. São métricas, não o programa
da fonte Helvetica. A permissão integral também acompanha o arquivo em
`lib/src/io/resources/afm/LICENSE-Adobe.txt`.
Origem da permissão: https://github.com/apache/pdfbox/blob/21661b79f0e2c90ad53e322b80be3a3bf777b1c5/LICENSE.txt

Copyright (c) 1985, 1987, 1989, 1990, 1997 Adobe Systems Incorporated.
All Rights Reserved. Helvetica is a trademark of Linotype-Hell AG and/or its subsidiaries.

Adobe Font Metrics (AFM) for PDF Core 14 Fonts

   This file and the 14 PostScript(R) AFM files it accompanies may be used,
   copied, and distributed for any purpose and without charge, with or without
   modification, provided that all copyright notices are retained; that the
   AFM files are not distributed without this file; that all modifications
   to this file or any of the AFM files are prominently noted in the modified
   file(s); and that this paragraph is not modified. Adobe Systems has no
   responsibility or obligation to support the use of the AFM files.

## Fontes URW Core 35

Arquivos inalterados: `assets/fonts/urw-core35/*.otf`, catorze das trinta e oito
faces da versão 2.00. São as substitutas metricamente compatíveis das catorze
fontes padrão do PDF (NimbusSans para Helvetica, NimbusRoman para Times,
NimbusMonoPS para Courier, StandardSymbolsPS para Symbol e D050000L para
ZapfDingbats), e o renderizador as usa quando o documento referencia uma dessas
sem embuti-la. O mesmo conteúdo viaja comprimido em
`lib/src/render/resources/standard_font_programs_vm.dart`, gerado por
`tool/generate_standard_fonts.dart`; a compressão é a única diferença em
relação aos arquivos originais.

Os programas permanecem sob a SIL OFL 1.1 — não são relicenciados por virem
junto de código MIT, e a OFL não alcança os documentos desenhados com eles. O
texto integral da licença acompanha os arquivos em
`assets/fonts/urw-core35/LICENSE.OFL` e está reproduzido mais abaixo, na seção
da fonte de testes ABeeZee. A URW++ publicou as mesmas fontes também sob AGPL3
e LPPL 1.3c, como diz `assets/fonts/urw-core35/LICENSE.md`, deixando a escolha
para quem redistribui; este pacote escolhe a OFL, e é o texto dela que
acompanha os arquivos.

O enunciado de copyright não declara Reserved Font Name nenhum, de modo que os
nomes das famílias podem ser carregados como estão.

Copyright (c) 2014,2015 by (URW)++ Design & Development

## Decodificador Brotli

Arquivos: `lib/src/io/codec/brotli/` (exceto `brotli.dart`, que e fachada propria
deste pacote).

Porte em Dart do decodificador de referencia do Brotli, `org.brotli.dec`, escrito
pelo Projeto Brotli do Google. O porte veio de um projeto irmao do mesmo autor e
foi copiado para ca com os nomes de arquivo ajustados a convencao do Dart e sem
`Decoder.dart`, que depende de `dart:io` e custaria a este pacote o suporte a
`dart2js` e `dart2wasm`. A logica de decodificacao nao foi alterada.

O decodificador e usado apenas para expandir os dados de tabela de uma fonte
WOFF 2.0, conforme exige a recomendacao da W3C. O dicionario estatico do anexo A
da RFC 7932 esta embutido em `dictionary_data.dart` e e indispensavel: sem ele
fluxos validos simplesmente nao decodificam.

Origem: https://github.com/google/brotli
Licenca: MIT, a mesma deste pacote.

Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## Fonte de testes ABeeZee

Arquivo inalterado: `test/assets/ABeeZee-Regular.ttf`.
Origem: https://github.com/google/fonts/tree/fffdadf0f0c9cc1ec8b407063424a8bfbee05611/ofl/abeezee
A fonte mantém SIL OFL 1.1; não é relicenciada MIT.

Derivados desse mesmo arquivo, usados para testar a leitura de WOFF 2.0:
`test/assets/ABeeZee-Regular.woff2` (com a transformação de `glyf` e `loca`) e
`test/assets/ABeeZee-Regular-untransformed.woff2` (sem transformação). Ambos
foram gerados com a `fontTools` a partir do TTF acima e permanecem sob a mesma
OFL 1.1, que cobre obras derivadas.

Copyright 2011 The ABeeZee Project Authors (https://github.com/googlefonts/abeezee), with Reserved Font Name 'ABeeZee'

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://scripts.sil.org/OFL


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.

## Exemplo PDF 2.0 da PDF Association

Arquivo inalterado: `test/assets/pdf20-offset-start.pdf`, cópia byte a byte de
`PDF 2.0 with offset start.pdf` do repositório de exemplos da PDF Association.
Só o nome do arquivo mudou, para evitar espaços no caminho; o conteúdo é
idêntico (SHA-256 em `test/assets/manifest.json`).
Origem: https://github.com/pdf-association/pdf20examples

É o exemplo oficial da provisão da ISO 32000-2, 7.5.2, que permite bytes
arbitrários antes de `%PDF-`: o cabeçalho começa no byte 656 e os deslocamentos
da tabela de referências cruzadas são contados a partir do sinal de porcentagem.
Serve de fixture para `test/kernel/pdf/reader_offset_start_test.dart`.

A PDF Association distribui esses exemplos sob Creative Commons
Attribution-ShareAlike 4.0 International (CC BY-SA 4.0), que permite a
redistribuição, inclusive comercial, desde que se dê o crédito acima e que este
arquivo continue sob a mesma licença. A CC BY-SA 4.0 cobre somente este arquivo;
não se estende ao restante do pacote. Termos completos:
https://creativecommons.org/licenses/by-sa/4.0/legalcode

## Ilustrações de domínio público

Os arquivos `anatomy-of-the-hand.svg`, `attacking-tiger.svg`,
`back-to-school.svg`, `bengal-tiger-head.svg`, `cartoon-tiger.svg`,
`soccer-ball.svg`, `tiger-sticker-red-on-green.svg` e
`united-states-map-with-capitals.svg`, em `test/assets`, vêm de
publicdomainvectors.org sob domínio público, sem exigência de atribuição. A
URL de origem de cada um está em `test/assets/manifest.json`. Só os nomes de
arquivo mudaram, para kebab-case; o conteúdo é o publicado.

## Fixtures de geração própria

A licença abaixo cobre somente shapes-rgb.png, blue-square-16.gif, shapes-rgb.jpg,
image-2frames.gif, image.jb2, png_greyscale.png, rootRsa.cer, test.pdf e
shapes-rgb-large.bmp em `test/assets`. O inventário de hashes e origens está em
`test/assets/manifest.json`. O certificado é uma CA sintética para testes,
não uma credencial de produção; contém somente o certificado público.

MIT License

Copyright (c) 2026 DPDF contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
