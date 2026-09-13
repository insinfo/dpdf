# Cobertura da especificação

Estado da implementação do `dpdf` e dos pacotes auxiliares `jbig2` e `dgfx` em relação à
**ISO 32000-1:2008** (PDF 1.7) e às normas que ela referencia.

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
| **Em curso** | Sendo implementado neste momento; o estado muda em breve |

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
| 7.7 Estrutura do documento | Parcial | Catálogo sendo completado entrada a entrada — **em curso** |
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
| 9.9 Programas de fonte embutidos | OK | Type1, TrueType, CFF/Type1C, CFF2, OpenType, WOFF 1.0 e **WOFF 2.0**, este com as transformações de `glyf`/`loca` e `hmtx` e Brotli embutido no pacote. Coleções `ttcf` são reconstruídas mas o leitor sfnt ainda não as abre |
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
| 12.2 Preferências de visualização | Parcial | **Em curso** — Tabela 150 sendo completada |
| 12.3.2 Destinos | OK | `XYZ`, `Fit`, `FitH`, `FitV`, `FitR`, `FitB`, `FitBH`, `FitBV`, nomeados, remotos |
| 12.3.3 Sumário (outline) | OK | |
| 12.3.4 Miniaturas | Parcial | Preservadas; sem geração |
| 12.3.5 Coleções | OK | |
| 12.3.6 Rótulos de página | OK | |
| 12.4.2 Transições de página | Parcial | **Em curso** — os treze estilos da Tabela 164 |
| 12.4.3 Fios de artigo | Ausente | **Em curso** — `/Threads`, beads e a lista circular |
| 12.5 Anotações | OK | 25 dos 26 subtipos da Tabela 169 têm classe própria, com fluxos de aparência `/AP`, `/AS`; a anotação 3D está **em curso** |
| 12.6 Ações | OK | `GoTo`, `GoToR`, `GoToE`, `Launch`, `Thread`, `URI`, `Sound`, `Movie`, `Hide`, `Named`, `SubmitForm`, `ResetForm`, `ImportData`, `JavaScript`, `SetOCGState`, `Rendition`, `Trans`, `GoTo3DView` |
| 12.7 Formulários interativos | OK | Campos de texto, escolha e botão; texto variável e geração de aparência; `/NeedAppearances` |
| 12.7.8 XFA | Parcial | Preservado e removível; sem interpretação |
| 12.8 Assinaturas digitais | OK | `adbe.pkcs7.detached`, CAdES, carimbo RFC 3161, DocMDP, FieldMDP, `/Changes` |
| 12.9 Propriedades de medida | Parcial | **Em curso** |
| 12.10 Requisitos do documento | Ausente | **Em curso** — `/Requirements` |

## 13 — Multimídia

| Cláusula | Estado | Observação |
|---|---|---|
| 13.2.2 Anotação Screen | Parcial | **Em curso** |
| 13.2.3 Renditions | Ausente | **Em curso** — `/MR` e `/SR` |
| 13.2.4 Media clips | Ausente | **Em curso** — `/MCD` e `/MCS` |
| 13.2.5–13.2.8 Parâmetros de mídia | Ausente | **Em curso** |
| 13.3 Sons | Parcial | **Em curso** |
| 13.4 Filmes | Parcial | **Em curso** |
| 13.5 Apresentações alternativas | Ausente | **Em curso** |
| 13.6 Arte 3D | Parcial | **Em curso** — o fluxo U3D/PRC permanece opaco por desenho |

## 14 — Intercâmbio de documentos

| Cláusula | Estado | Observação |
|---|---|---|
| 14.2 Conjuntos de procedimentos | OK | Obsoletos na 1.7; preservados |
| 14.3 Metadados XMP | OK | Leitura, edição e serialização; esquemas de extensão |
| 14.4 Identificadores de arquivo | OK | `/ID` com a regra de atualização incremental |
| 14.5 Dicionários page-piece | Parcial | **Em curso** — `/PieceInfo` |
| 14.6 Conteúdo marcado | OK | |
| 14.7 Estrutura lógica | OK | `/StructTreeRoot`, `/ParentTree`, `/RoleMap`, `/ClassMap`, MCR e OBJR, cópia entre documentos |
| 14.8 PDF marcado | OK | Tipos de estrutura padrão e atributos; espaços de nomes do PDF 2.0 |
| 14.9 Acessibilidade | OK | Verificada pelo `PdfUAVerifier` |
| 14.10 Captura web | Ausente | Baixo valor prático; não priorizado |
| 14.11.2 Caixas de página | OK | |
| 14.11.3 `/BoxColorInfo` | Ausente | **Em curso** |
| 14.11.4 Separações | Ausente | **Em curso** |
| 14.11.5 Marcas de impressão | Parcial | **Em curso** |
| 14.11.6 Trapping | Parcial | **Em curso** |
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
| Paralelismo | Ausente | `useIsolates`, `tileHeight` e `useSimd` são parâmetros inertes — a API promete o que não entrega. A rota é a mesma do `j2k`: `dart:isolate` atrás de import condicional, com `dgfx_io.dart` já servindo de ponto de entrada para a VM |
| Interpolação Gouraud | Ausente | O `dpdf` emula com um triângulo de cor chapada por faceta |
| Formatos de pixel | Parcial | Só ARGB32 alfa-reto |

---

## Lacunas conhecidas, em ordem de valor

1. **Quadros diferenciais por DCT no JPEG** (SOF5, SOF6, SOF13, SOF14) — exigem IDCT com
   saída assinada sem *level shift*; o plano de componente hoje é `Uint8List`.
2. **Recorte geométrico na redação de arte vetorial** — um caminho que atravessa a borda da
   área é recusado, não recortado. Exige subdividir Bézier e reconstruir o *winding*.
3. **Cobertura de borda curva no `dgfx`** — subestima a área em cerca de 10%: um círculo de
   raio 2 px rasteriza 11,3 em vez de 12,57, enquanto um retângulo 4×4 dá exato. Aponta para
   a tolerância de achatamento em raios pequenos.
4. **Coleções `ttcf`** — reconstruídas a partir de WOFF 2.0, mas o leitor sfnt não abre
   coleção, então a fonte falha depois da conversão.
5. **Redação de arte vetorial** — `PdfAreaRedaction` reescreve texto e imagens; vetores
   ainda exigem cobertura por sobreposição.
6. **Gouraud no `dgfx`** — remove a emulação cara e as costuras visíveis entre facetas nos
   sombreamentos de tipo 4 a 7.
7. **Paralelismo real no `dgfx`** — a API pública promete o que não entrega.
8. **Meios-tons na rasterização** (10.5) e **casos de *knockout*** (11.4).
9. **Captura web** (14.10) — baixo valor prático.

## O que não está no alcance

> Esta lista é sobre o que não faz sentido **para esta biblioteca**, não sobre o que é
> difícil. Coisas grandes mas bem definidas — Parte 2 do JPEG 2000, paralelismo — ficam nas
> tabelas acima como *Ausente*, porque são trabalho pendente e não decisão de projeto.

- **ISO 32000-2 (PDF 2.0)** além do que a 1.7 cobre: o alvo declarado é a 1.7, com alguns
  elementos do PDF 2.0 já presentes (espaços de nomes de estrutura, AES-256 revisão 6).
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
