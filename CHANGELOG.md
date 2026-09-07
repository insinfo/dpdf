

## 1.0.0

Primeira versão publicada. O pacote é Dart puro, sem FFI e sem binários
externos, e compila para VM (JIT/AOT), `dart2js` e `dart2wasm`.

### Adicionado

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
