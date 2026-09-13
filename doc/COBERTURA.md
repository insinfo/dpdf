# Cobertura da especificação

Estado da implementação do `dpdf` e dos pacotes auxiliares `jbig2`, `dgfx` e `j2k` em
relação à **ISO 32000-1:2008** (PDF 1.7), com os pontos da **ISO 32000-2:2020** (PDF 2.0)
que já foram atendidos assinalados na linha correspondente, e às normas que elas
referenciam.

> **Como este documento foi levantado.** A coluna de estado combina três fontes: a presença
> de código localizada por busca em `lib/`, a existência de teste que exercite o
> comportamento em `test/`, e verificação manual contra o texto da norma nos pontos
> assinalados. Presença de arquivo **não** é prova de completude, e este documento procura
> não confundir as duas coisas: onde só há esqueleto, o estado é *Parcial*.
>
> Última medição: 2026-09-13. Reproduza com o roteiro da seção
> [Como remedir](#como-remedir).
>
> Uma advertência que vale a pena repetir: neste levantamento, um módulo de 1811 linhas
> (o linearizador) estava **completo, não exportado, não referenciado e não testado** — e
> falhava numa autoverificação na primeira vez que foi executado. Código presente não é
> código que funciona, e código que funciona não é código alcançável pelo usuário.

## Legenda

| Símbolo | Significado |
|---|---|
| **OK** | Implementado e coberto por teste |
| **Parcial** | Implementado em parte; o que falta está descrito na própria linha |
| **Ausente** | Não implementado |
| **Fora do alcance** | Decisão de projeto, com a razão na própria linha — não é trabalho pendente |

## Números

| | `dpdf` | `jbig2` | `dgfx` | `j2k` |
|---|---|---|---|---|
| Linhas em `lib/` | 108 629 | ~12 000 | ~11 800 | 51 530 |
| Arquivos em `lib/` | 618 | 60 | 45 | 240 |
| Testes passando | 2 715 | 104 | 329 | 428 |
| `dart analyze` | sem erros nem avisos | limpo | limpo | limpo |

Os três pacotes auxiliares são projetos separados. `jbig2` e `dgfx` entram no `dpdf` por
`dependency_overrides` apontando para o repositório local; **`j2k` não** — ele vem do
pub.dev na versão `^0.9.0`. Melhorias feitas no repositório local do `j2k` só chegam ao
`dpdf` depois de uma publicação nova.

---

## 7 — Sintaxe

| Cláusula | Estado | Observação |
|---|---|---|
| 7.2 Convenções léxicas | OK | |
| 7.3 Objetos | OK | Todos os oito tipos, incluindo fluxos e referências indiretas |
| 7.4.2 `ASCIIHexDecode` | OK | Ida e volta testada |
| 7.4.3 `ASCII85Decode` | OK | Ida e volta testada |
| 7.4.4 `LZWDecode` | OK | Com `EarlyChange` |
| 7.4.4 `FlateDecode` | OK | Preditores PNG 10–15 e TIFF 2, 1–16 bits por componente |
| 7.4.5 `RunLengthDecode` | OK | |
| 7.4.6 `CCITTFaxDecode` | OK | Grupo 4, Grupo 3 1-D e 2-D misto, `EncodedByteAlign`, `BlackIs1`, `EndOfLine`, `DamagedRowsBeforeError`. **Codificação só escreve Grupo 4.** |
| 7.4.7 `JBIG2Decode` | OK | Via `package:jbig2`; ver seção própria |
| 7.4.8 `DCTDecode` | OK | Baseline e progressivo com Huffman **e aritmético** (SOF9/SOF10), lossless (SOF3/SOF11) com os sete preditores do Anexo H, e hierárquico sobre os processos sem perdas (Anexo J). 8 e 12 bits por amostra. Quadro diferencial por DCT (SOF5/6/13/14) é recusado com mensagem explícita |
| 7.4.9 `JPXDecode` | Parcial | Via `package:j2k`; `SMaskInData` tratado. Uma recusa do codec vira imagem pulada no `PdfRenderReport`, não exceção. Codestream cru com componentes subamostrados ainda é recusado — ver a seção do `j2k` |
| 7.4.10 `Crypt` | OK | Filtro `/Identity` e os nomeados em `/CF` |
| 7.5.2 Cabeçalho | OK | Bytes arbitrários antes do `%PDF-` são aceitos, com os deslocamentos contados a partir do sinal de porcentagem, como a 7.5.2 do PDF 2.0 exige |
| 7.5.4 Tabela de referência cruzada | OK | |
| 7.5.5 Trailer | OK | |
| 7.5.6 Atualizações incrementais | OK | |
| 7.5.7 Fluxos de objeto | OK | `/N`, `/First`, `/Extends` |
| 7.5.8 Fluxos de referência cruzada | OK | `/Index` esparso, `/W`, `/Prev`, tipos 0/1/2 |
| 7.5.8.4 Arquivos híbridos `/XRefStm` | Parcial | Lidos; não escritos |
| 7.6.3 Manipulador padrão | OK | R2–R6, incluindo AES-256 e os algoritmos 2.A/2.B |
| 7.6.4 Manipulador por chave pública | OK | `/Adobe.PubSec`, envelope CMS, permissões por destinatário |
| 7.6.5 Filtros de cripto | OK | `/CF`, `/StmF`, `/StrF`, `/EFF`, `/V2`, `/AESV2`, `/AESV3` |
| 7.7 Estrutura do documento | OK | Tabela 28 completa, entrada por entrada |
| 7.8 Fluxos de conteúdo e recursos | OK | |
| 7.9 Estruturas de dados comuns | OK | Datas, strings de texto, árvores de nomes e de números, retângulos |
| 7.10 Funções | OK | Tipos 0, 2, 3 e 4, com todos os operadores da Tabela 42 |
| 7.11 Especificações de arquivo | OK | `/EF`, `/F`, `/UF`, `/RF`, arquivos embutidos |
| 7.12 Dicionário de extensões | Parcial | Lido; sem API de escrita dedicada |
| **Anexo F — Linearização** | OK | `PdfLinearizer.linearize` e `PdfLinearizationInfo.read`, com dicionário de parâmetros, hint streams e validação das regras do anexo |

## 8 — Gráficos

| Cláusula | Estado | Observação |
|---|---|---|
| 8.2 Objetos gráficos | OK | |
| 8.3 Sistemas de coordenadas | OK | |
| 8.4 Estado gráfico | OK | Incluindo `/ExtGState` |
| 8.5 Construção e pintura de caminhos | OK | |
| 8.6.3 Espaços de cor de dispositivo | OK | |
| 8.6.5 Espaços CIE | OK | `CalGray`, `CalRGB`, `Lab`, `ICCBased` com `/N` e `/Alternate` |
| 8.6.6 Espaços especiais | OK | `Indexed`, `Separation` (incl. `/All` e `/None`), `DeviceN` com `/Process`, `Pattern` |
| 8.7.3 Padrões de ladrilho | OK | Coloridos e não coloridos, em preenchimento e traço |
| 8.7.4 Sombreamentos | OK | Tipos 1–7; malhas Gouraud e retalhos Coons/tensoriais |
| 8.8 XObjects externos | OK | |
| 8.9 Imagens | OK | 1–16 bpc, `/Decode`, `/ImageMask`, `/Mask` por estêncil e por chave de cor, `/SMask` com `/Matte` |
| 8.9.7 Imagens inline | OK | Desenhadas e puladas com segurança na extração: o fim da imagem é calculado de `/W`, `/H`, `/BPC` e `/CS` e o `EI` é verificado, não procurado, então bytes que contenham `EI` não confundem o leitor |
| 8.10 Form XObjects | OK | `/BBox`, `/Matrix`, `/Group` |
| 8.11 Conteúdo opcional | OK | OCG, OCMD com `/VE`, `/OCProperties`, configurações alternativas, `/OC` em XObject e anotação |

## 9 — Texto

| Cláusula | Estado | Observação |
|---|---|---|
| 9.3 Parâmetros de estado de texto | OK | |
| 9.4 Objetos de texto | OK | |
| 9.6 Fontes simples | OK | Type1, TrueType e Type3, este com os procedimentos de glifo executados pelo renderizador; resolução completa de codificação de 9.6.6 |
| 9.6.6 Codificação | OK | `/BaseEncoding`, `/Differences`, tabelas padrão, TrueType simbólica com `cmap` (3,0) e (1,0) |
| 9.7 Fontes compostas | OK | CIDFont, `/CIDToGIDMap`, CMaps predefinidos e embutidos, `/W`, `/W2`, escrita vertical |
| 9.8 Descritores de fonte | OK | |
| 9.9 Programas de fonte embutidos | OK | Type1, TrueType, CFF/Type1C, CFF2, OpenType, WOFF 1.0 e **WOFF 2.0**, este com as transformações de `glyf`/`loca` e `hmtx` e Brotli embutido no pacote. Coleções `ttcf` são reconstruídas **e abertas**, com as fontes compartilhando tabelas no mesmo buffer |
| 9.10 Extração de texto | OK | `/ToUnicode` e mapeamento reverso; imagens inline são atravessadas corretamente |

## 10 — Renderização

| Cláusula | Estado | Observação |
|---|---|---|
| 10.2/10.3 Conversão de cor | OK | |
| 10.4 Funções de transferência | OK | |
| 10.5 Meios-tons | Fora do alcance | Preservados no documento, deliberadamente não aplicados: a saída é de tom contínuo, e aplicar a trama viraria degradê e borda antisserrilhada em padrão de pontos numa frequência de papel. Justificativa no código |
| 10.6 Conversão de varredura | OK | Rasterizador analítico com antisserrilhamento |

## 11 — Transparência

| Cláusula | Estado | Observação |
|---|---|---|
| 11.3.5 Modos de mistura | OK | Os 12 separáveis e os 4 não separáveis |
| 11.4 Grupos de transparência | OK | Isolados, não isolados e *knockout*, este auditado e coberto por teste. O `/TK` de texto da 9.3.8 também é honrado |
| 11.5 Máscaras suaves | OK | `/Alpha` e `/Luminosity`, `/BC`, `/TR` |
| 11.6.6 Grupos como XObject | OK | |
| 11.7 Espaço de cor do grupo | OK | |

## 12 — Recursos interativos

| Cláusula | Estado | Observação |
|---|---|---|
| 12.2 Preferências de visualização | OK | As dezessete entradas da Tabela 150, com validação de `/PrintPageRange` |
| 12.3.2 Destinos | OK | `XYZ`, `Fit`, `FitH`, `FitV`, `FitR`, `FitB`, `FitBH`, `FitBV`, nomeados, remotos |
| 12.3.3 Sumário (outline) | OK | |
| 12.3.4 Miniaturas | Parcial | Preservadas; sem geração |
| 12.3.5 Coleções | OK | |
| 12.3.6 Rótulos de página | OK | |
| 12.4.2 Transições de página | OK | Os doze estilos da Tabela 164, com validação de quais entradas cada estilo aceita |
| 12.4.3 Fios de artigo | OK | `/Threads`, beads e a validação da lista circular duplamente ligada |
| 12.5 Anotações | OK | Os 26 subtipos da Tabela 169 têm classe própria, com fluxos de aparência `/AP` e `/AS` |
| 12.6 Ações | OK | `GoTo`, `GoToR`, `GoToE`, `Launch`, `Thread`, `URI`, `Sound`, `Movie`, `Hide`, `Named`, `SubmitForm`, `ResetForm`, `ImportData`, `JavaScript`, `SetOCGState`, `Rendition`, `Trans`, `GoTo3DView` |
| 12.7 Formulários interativos | OK | Campos de texto, escolha e botão; texto variável e geração de aparência; `/NeedAppearances` |
| 12.7.8 XFA | Parcial | Preservado e removível; sem interpretação |
| 12.8 Assinaturas digitais | OK | `adbe.pkcs7.detached`, CAdES, carimbo RFC 3161, DocMDP, FieldMDP, `/Changes` |
| 12.9 Propriedades de medida | OK | `/Measure`, `/Viewport` e a regra de sobreposição quando mais de um viewport cobre o ponto |
| 12.10 Requisitos do documento | OK | `/Requirements`, com `/RH` recusado em `/EnableJavaScripts` como a 12.10.1 exige |

## 13 — Multimídia

| Cláusula | Estado | Observação |
|---|---|---|
| 13.2.2 Anotação Screen | OK | Ligada a ação de rendição |
| 13.2.3 Renditions | OK | `/MR` e `/SR`, com a busca em profundidade das seletoras |
| 13.2.4 Media clips | OK | `/MCD` e `/MCS`, com permissões |
| 13.2.5–13.2.8 Parâmetros de mídia | OK | Reprodução, tela com janela flutuante, deslocamentos de tempo/quadro/marcador e identificadores de software, incluindo os algoritmos normativos de escolha de reprodutor |
| 13.3 Sons | OK | Objeto de som e a ação correspondente |
| 13.4 Filmes | OK | Dicionário de filme, anotação, ação e parâmetros de ativação |
| 13.5 Apresentações alternativas | OK | `/AlternatePresentations` e `/SlideShow` |
| 13.6 Arte 3D | OK | Fluxo, referência, vistas, projeção, fundo, modo de renderização, iluminação e animação. O fluxo U3D/PRC permanece opaco por desenho; seções transversais e nós 3D ficam como array cru |

## 14 — Intercâmbio de documentos

| Cláusula | Estado | Observação |
|---|---|---|
| 14.2 Conjuntos de procedimentos | OK | Obsoletos na 1.7; preservados |
| 14.3 Metadados XMP | OK | Leitura, edição e serialização; esquemas de extensão |
| 14.4 Identificadores de arquivo | OK | `/ID` com a regra de atualização incremental |
| 14.5 Dicionários page-piece | OK | `/PieceInfo` na página e no catálogo, com `/LastModified` obrigatório |
| 14.6 Conteúdo marcado | OK | |
| 14.7 Estrutura lógica | OK | `/StructTreeRoot`, `/ParentTree`, `/RoleMap`, `/ClassMap`, MCR e OBJR, cópia entre documentos |
| 14.8 PDF marcado | OK | Tipos de estrutura padrão e atributos; espaços de nomes do PDF 2.0 |
| 14.9 Acessibilidade | OK | Verificada pelo `PdfUAVerifier` |
| 14.10 Captura web | OK | `/SpiderInfo`, comandos, árvores `/IDS` e `/URLS`, algoritmo canônico de URL e identificadores por resumo |
| 14.11.2 Caixas de página | OK | |
| 14.11.3 `/BoxColorInfo` | OK | Com os estilos de borda das Tabelas 360 e 361 |
| 14.11.4 Separações | OK | Com as regras de grupo da Tabela 364 |
| 14.11.5 Marcas de impressão | OK | Anotação e XObject de formulário, com `/MarkStyle` e `/Colorants` |
| 14.11.6 Trapping | OK | Rede de trapping, com a exclusão mútua entre `/LastModified` e `/Version` |
| 14.11.7 Intenções de saída | OK | |

---

## Conformidade

| Norma | Estado | Observação |
|---|---|---|
| PDF/A-1, A-2, A-3 (ISO 19005) | Parcial | `PdfAVerifier` relata violações **e** `unverifiedRules`, a lista explícita do que está fora do alcance do verificador. Relatório, não certificação |
| PDF/UA-1 (ISO 14289-1) | Parcial | `PdfUAVerifier`, mesma ressalva |

O contrato destes verificadores é deliberado: uma regra que não pode ser verificada sem
renderizar ou sem julgamento humano **permanece** em `unverifiedRules` em vez de ser
declarada aprovada. O valor do relatório está nessa honestidade.

---

## Pacotes auxiliares

### `jbig2` — ITU-T T.88

| Cláusula | Decodifica | Codifica |
|---|---|---|
| 6.2 Região genérica (templates 0–3, TPGDON) | OK | Template 0 e demais |
| 6.2 `EXTTEMPLATE` | Parcial | Ausente |
| 6.3 Refinamento genérico | OK | OK |
| 6.4 Região de texto | OK | OK |
| 6.5 Dicionário de símbolos | OK | OK, com refinamento e agregação |
| 6.6/6.7 Halftone e dicionário de padrões | OK | OK |
| Anexo B Tabelas Huffman padrão e customizadas | OK | Parcial |
| 7.2.7 Comprimento de dados desconhecido | OK | — |
| 7.4.x Páginas listradas, end-of-stripe | OK | Parcial |
| MMR dentro de região genérica | OK | Ausente |

### `j2k` — ISO/IEC 15444-1 (ITU-T T.800), JPEG 2000 Parte 1

Porte do JJ2000, a implementação de referência. Bit-exato contra ela no subconjunto de
conformidade embutido. Consumido pelo `dpdf` no renderizador e no compressor de imagens.

| Área | Estado | Observação |
|---|---|---|
| Análise de codestream, EBCOT/MQ | OK | |
| Wavelets 5x3 reversível e 9x7 irreversível | OK | |
| RCT/ICT inversos, de-escalonamento de ROI | OK | |
| Cores JP2: sRGB, greyscale, sYCC, paletas, `cdef` | OK | |
| Perfis ICC restritos | OK | Monocromático e RGB de três componentes |
| Ladrilhamento, camadas, as cinco ordens de progressão | OK | |
| Sondagem de cabeçalho e orçamentos | OK | `maxPixels`, `maxDimension` |
| Codificador: pixels entrelaçados, PGM/PPM, J2K e JP2 | OK | Sem perdas ou com controle de taxa |
| Componentes subamostrados em codestream cru | OK | Reamostrados pelo mesmo código que o caminho JP2 usa; fator inteiro de 1 a 255, todo o alcance de `XRsiz`/`YRsiz` |
| Codificador com profundidade por componente e sinal | OK | `bitsPerComponent` e `signedComponents`; a MCT é desligada quando os três primeiros componentes divergem, como a G.2 exige |
| Saída com profundidade diferente de 8 ou 16 bits | Parcial | Reescalonada; a profundidade original fica em `sourceBitsPerComponent` |
| Resolução reduzida | OK | Corrigida uma divergência herdada do JJ2000, documentada em `doc/DIVERGENCIAS_JJ2000.md` do repositório `jpeg2000`: a referência responde geometria de componente no nível errado e escreve mais amostras do que o próprio cabeçalho declara |
| Filtros wavelet customizados (ATK) | OK | Síntese genérica por *lifting* do Anexo G da 15444-2. Validada por reproduzir **bit a bit** os filtros 5-3 e 9-7 especializados. A categoria arbitrária do Anexo H é recusada citando a cláusula |
| Part 2 / JPX (demais extensões) | Ausente | Trabalho **grande e aberto**: decomposição arbitrária (DFS/ADS), transformada multicomponente (MCT), precisão estendida, deslocamento DC variável, ROI arbitrária. Cada uma é independente e pode ser feita isoladamente |
| Decodificação em paralelo | OK | `decodeJpeg2000Parallel`, assíncrona, com isolates atrás de `if (dart.library.io)` e caminho sequencial como padrão na Web. Paraleliza por tile e, quando há menos tiles que workers, por code-block — que é o caso de tile único do PDF. Medido 2,6x a 3,8x em 8 núcleos acima de 0,2 MP, com saída bit a bit idêntica. `decodeJpeg2000` segue síncrona e inalterada |

### `dgfx` — rasterizador

| Área | Estado | Observação |
|---|---|---|
| Caminhos, regras de preenchimento | OK | Validado contra o Marlin do OpenJDK |
| Traçado (caps, joins, miter) | OK | Paridade com o `pathstroke` do Blend2D |
| Tracejado | OK | Dois bugs corrigidos nesta sessão |
| Transformações, recorte | OK | Máscara A8 antisserrilhada |
| Gradientes linear, radial, cônico | OK | Com matriz própria |
| Padrões | OK | Sem filtro de redução — reduções grandes serrilham |
| Composição (28 operadores Porter-Duff) | OK | |
| Fontes TrueType, CFF, CFF2 | OK | |
| Fontes Type 1 | OK | PFA/PFB, flex, `seac`, substituição de hints |
| Tabela `post` | OK | |
| Shaping GSUB/GPOS | Parcial | GSUB 1–4; GPOS 1–2 e só avanço horizontal |
| Bidi | Parcial | Analisador simplificado, sem níveis de embutimento |
| Paralelismo | Fora do alcance | Medido: preencher uma A4 a 300 dpi custa 10,6 ms, e só mandar o framebuffer para um isolate custa 30,7 ms. Sem memória compartilhada entre isolates (que exigiria FFI), paralelizar seria quatro vezes mais lento. Os parâmetros viraram `@Deprecated` com a razão escrita; o lugar certo de paralelizar é acima do dgfx, uma imagem por isolate |
| Interpolação Gouraud | OK | `fillTriangleGouraud` e `fillTriangleMesh`. A malha entra como contornos de um caminho com regra nonZero, então a aresta interna se cancela e não sobra costura. O `dpdf` ainda não trocou a emulação por ela |
| Formatos de pixel | Parcial | Só ARGB32 alfa-reto |

---

## Lacunas conhecidas, em ordem de valor

1. **Recorte geométrico na redação de arte vetorial** — um caminho que atravessa a borda da
   área é recusado, não recortado. Exige subdividir Bézier e reconstruir o *winding*. Hoje a
   recusa é honesta, mas recusar é pior que redigir.
2. **`j2k` publicado está defasado** — o `dpdf` consome a `0.9.0` do pub.dev, que ainda
   carrega o defeito de `dart2js` (todo decode 8 bits não-RGB quebra na web) e recusa
   codestream cru subamostrado. Nenhuma correção local chega ao `dpdf` sem uma publicação.
3. **Cobertura de borda curva no `dgfx`** — subestima a área em cerca de 10%: um círculo de
   raio 2 px rasteriza 11,3 em vez de 12,57, enquanto um retângulo 4×4 dá exato. Aponta para
   a tolerância de achatamento em raios pequenos.
4. **O `dpdf` ainda não usa o Gouraud do `dgfx`** — `_paintMeshFacet` continua pintando um
   triângulo de cor chapada por faceta, com as costuras que isso deixa. A API do outro lado
   já existe; falta trocar.
5. **Quadros diferenciais por DCT no JPEG** (SOF5, SOF6, SOF13, SOF14) — exigem IDCT com
   saída assinada sem *level shift*; o plano de componente hoje é `Uint8List`.
6. **Codificação CCITT só escreve Grupo 4**, e o `jbig2` não codifica MMR nem `EXTTEMPLATE`.
7. **Shaping e bidi no `dgfx`** — GSUB 1–4 e GPOS 1–2 com só avanço horizontal; o analisador
   bidi é simplificado. Não afeta o renderizador de PDF, que posiciona por `/Widths`, mas
   afeta o caminho SVG.
8. **Arquivos híbridos `/XRefStm`** são lidos e não escritos; o dicionário de extensões não
   tem API de escrita; miniaturas são preservadas e não geradas.

## O que não está no alcance

> Esta lista é sobre o que não faz sentido **para esta biblioteca**, não sobre o que é
> difícil. Coisas grandes mas bem definidas — Parte 2 do JPEG 2000, paralelismo — ficam nas
> tabelas acima como *Ausente*, porque são trabalho pendente e não decisão de projeto.

- **ISO 32000-2 (PDF 2.0)** além do que a 1.7 cobre: o alvo declarado é a 1.7. Já estão
  atendidos os espaços de nomes de estrutura, AES-256 revisão 6 e a regra de bytes antes do
  cabeçalho da 7.5.2. Não foram avaliados os documentos ISO/TS que estendem o PDF 2.0
  (32001 SHA-2, 32002 EdDSA, 32003 AES-GCM, 32004 integridade, 32005 namespace).
- **Interpretação de XFA**: formulários XFA são preservados e podem ser removidos, mas não
  são executados.
- **Decodificação de U3D e PRC**: os fluxos de arte 3D são tratados como opacos.
- **JavaScript**: ações `JavaScript` são modeladas e preservadas; nenhum interpretador é
  embutido.

---

## Como remedir

```bash
dart analyze && dart test                 # dpdf
cd ../jbig2 && dart analyze && dart test
cd ../dgfx  && dart analyze && dart test
dart run tool/check_platforms.dart        # VM JIT/AOT, dart2js, dart2wasm
```

Para conferir a presença de um recurso antes de declarar o estado:

```bash
grep -rl "MediaClip" lib --include=*.dart   # zero arquivos = ausente
```

Presença não é completude: confirme sempre que existe teste exercitando o comportamento
antes de mover uma linha deste documento para *OK*.
