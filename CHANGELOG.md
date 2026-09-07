

## 1.0.0

Primeira versão publicada. O pacote é Dart puro, sem FFI e sem binários
externos, e compila para VM (JIT/AOT), `dart2js` e `dart2wasm`.

### Adicionado

- **Codec JPEG em Dart puro**: `JpegDecoder` (baseline sequencial, 4:4:4,
  4:2:2 e 4:2:0, intervalos de reinício, cinza/RGB/CMYK, transformação Adobe)
  e `JpegEncoder` (baseline, tabelas do Anexo K, qualidade 1-100, subamostragem
  opcional). O filtro `/DCTDecode` antes só repassava os bytes.
- **Reamostragem de imagens** (`ImageResampler`) com filtro de caixa, mais
  `PdfImageCompressionOptions.lossy` para reencodar imagens de tom contínuo
  como JPEG e limitar o lado maior a um número de pixels.
- **Compressão de PDF**: `PdfCompressor` reescreve o documento menor sem mudar
  o que ele desenha — object streams e xref stream, recompressão de fluxos,
  deduplicação de objetos idênticos, remoção de objetos órfãos e poda opcional
  de miniaturas, metadados e dados privados. Devolve o original quando a
  reescrita ficaria maior.
- **Recompressão de imagens bilevel** (`PdfImageCompressor`), sem perdas: cada
  imagem é codificada em JBIG2 (via `package:jbig2`) e em Flate, e a menor
  vence. Nenhum dos dois ganha sempre — medido numa página 800x1000, o Flate
  faz 287 bytes contra 886 do JBIG2 quando as linhas se repetem exatamente, e
  20304 contra 16519 quando há ruído de digitalização.
- **Decodificação JBIG2 real** no filtro `/JBIG2Decode`, que antes apenas
  concatenava os globals e devolvia os bytes crus.
- **Verificação de integridade**: `PdfIntegrityChecker` inspeciona cabeçalho,
  marcadores `%%EOF`, `startxref`, deslocamentos da tabela de referências
  cruzadas conferidos byte a byte, `/Count` conferido contra as páginas
  alcançáveis, ciclos na árvore de páginas, fluxos truncados e falhas de
  filtro, com códigos estáveis por achado.
- **Conformidade**: `PdfAVerifier` (PDF/A-1 a PDF/A-4) e `PdfUAVerifier`
  (PDF/UA-1), com a cláusula da norma em cada achado e a lista explícita das
  regras não avaliadas.
- **Redação por área**: `PdfAreaRedaction` remove os caracteres dentro de
  retângulos em documentos que o caminho estrito rejeita, preservando imagens,
  páginas e o grafo de objetos, com tarja opaca e remoção de anotações.
- **Métricas das 14 fontes padrão** embutidas, o que faz o conversor de HTML
  medir o texto com a face que realmente desenha: quebra de linha e alinhamento
  exatos, e seleção real de negrito, itálico, serifada e monoespaçada.
- **Kernel PDF**: leitura e escrita de objetos, tabela xref (clássica e em
  fluxo), fluxos de objetos, catálogo, árvore de páginas, incremental update,
  criptografia padrão (RC4 40/128, AES-128, AES-256) e intents de saída.
- **Fontes**: Type1, TrueType, Type0/CID e Type3, com subsetting TrueType,
  CMaps `ToUnicode`, Adobe Glyph List e recursos CJK carregados pelo consumidor.
- **Imagens e codecs**: PNG, JPEG, BMP, GIF, TIFF (incluindo LZW e CCITT G4) e
  JBIG2, com escritores PNG/TIFF e filtros Flate, LZW, RunLength e ASCII.
- **Layout**: `CraftDocument` com parágrafos, divs, listas, tabelas com
  `colspan`/`rowspan`, imagens, quebras de área, colapso de margens e cálculo
  de largura mínima/máxima.
- **HTML para PDF**: `CraftHtmlConverter` com pipeline independente de DOM,
  CSS, layout e pintura, cobrindo texto, listas, tabelas, imagens e links.
- **SVG**: processadores e renderizadores para as formas básicas, caminhos,
  transformações e marcadores.
- **Formulários**: `AcroForm` com campos de texto, botão, escolha e assinatura,
  além de mesclagem de formulários entre documentos.
- **Assinatura digital**: assinatura RSA/CMS, contêineres externos, carimbo do
  tempo (RFC 3161), OCSP, CRL e leitura de repositórios de chaves JKS e BKS.
- **Edição**: extração de texto com `ActualText` e Form XObjects, redação de
  texto, sobreposição e montagem de páginas, e modos opcionais de leitura,
  recuperação, mesclagem e assinatura.
- **Códigos de barras**: Code 39, Code 128, EAN/UPC e QR Code.
