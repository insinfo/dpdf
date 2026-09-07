# dpdf

Biblioteca PDF em Dart puro: criação, leitura, edição, layout de texto,
conversão de HTML, formulários, assinatura digital e verificação de
conformidade. Sem FFI, sem binários externos e sem dependências de execução
além do parser `html`.

Compila para VM (JIT e AOT), `dart2js` e `dart2wasm`. Arquivos e rede passam
por abstrações de plataforma; no navegador, arquivos locais são representados
pelo registro em memória exposto em `dpdf_web.dart`.

```dart
import 'package:dpdf/dpdf.dart';
```

## O que a biblioteca faz

### HTML para PDF

O texto é medido com as métricas da fonte que o pintor realmente desenha, então
a quebra de linha, a centralização e o alinhamento à direita são exatos — e não
uma estimativa por largura média de caractere. As 14 faces padrão estão
embutidas, de modo que negrito, itálico, serifada e monoespaçada são
selecionadas de verdade.

```dart
final pdf = await HtmlConverter.convertToBytes('''
  <h1 style="font-family: serif">Relatório</h1>
  <p>Texto que quebra em linhas com as larguras reais da fonte.</p>
  <table><tr><th>Item</th><th>Valor</th></tr>
         <tr><td>Licenças</td><td>12.400</td></tr></table>
''');
```

### Verificação de integridade

Diz o que um leitor encontraria: cabeçalho, marcadores `%%EOF`, `startxref`,
deslocamentos da tabela de referências cruzadas conferidos byte a byte,
`/Count` da árvore de páginas conferido contra as páginas realmente
alcançáveis, ciclos, fluxos truncados e falhas de filtro.

```dart
final report = await PdfIntegrityChecker.inspect(bytes);

report.isDamaged;            // houve algum erro
report.recoveryUsed;         // a xref declarada era inutilizável
report.reachablePageCount;   // páginas realmente alcançadas
for (final f in report.findings) print(f);  // [error] missing-eof: ...
```

Cada achado carrega um código estável (`missing-eof`, `xref-offset-mismatch`,
`page-count-mismatch`, `stream-decode-failed`, …), então dá para reagir a ele
em código, não só lê-lo.

### Conformidade PDF/A e PDF/UA

```dart
final pdfa = await PdfAVerifier.verify(bytes, level: PdfAConformanceLevel.a2b);
pdfa.isConforming;
pdfa.violations;        // com a cláusula da norma em cada achado
pdfa.unverifiedRules;   // o que NÃO foi avaliado

final ua = await PdfUAVerifier.verify(bytes);
```

O relatório é uma verificação, não uma certificação: `unverifiedRules` lista
explicitamente o que exigiria um interpretador de fluxo de conteúdo, um parser
de perfil ICC ou julgamento humano — para que um relatório limpo nunca seja
confundido com validação completa.

### Edição avançada e redação

Redação por área, para documentos com imagens, fontes embutidas e qualquer
grafo de objetos. Os caracteres dentro do retângulo saem do fluxo de conteúdo e
são substituídos pelo avanço que ocupavam, de modo que o texto restante mantém
a posição.

```dart
final redigido = await PdfAreaRedaction.apply(bytes, [
  PdfRedactionArea(1, left: 70, bottom: 675, right: 300, top: 693),
]);
```

Ela remove **texto**. Uma imagem dentro da área é coberta pela tarja, mas seus
pixels permanecem no arquivo: redigir uma página digitalizada exige substituir
a própria imagem. Para a garantia mais forte — um documento reconstruído a
partir de nada além do texto sobrevivente — use `PdfTextRedaction`, que aceita
um subconjunto estrito e rejeita tudo o que não puder reconstruir.

### Compressão de PDF

`PdfCompressor` reescreve o documento menor sem mudar o que ele desenha:
object streams com xref stream, recompressão de fluxos, deduplicação de
objetos idênticos, remoção de objetos órfãos e poda opcional de miniaturas,
metadados e dados privados de aplicação.

```dart
final result = await PdfCompressor.compress(bytes);
print(result.report);          // 161294 -> 21890 bytes, 86.4% menor
print(result.report.toJson()); // detalhamento por passo
await File('menor.pdf').writeAsBytes(result.bytes);
```

Se a reescrita ficasse maior que a entrada, o original é devolvido intacto —
um compressor não deve piorar o arquivo.

Três perfis: `PdfCompressionOptions.conservative` (só o que nenhum leitor
percebe, mantendo metadados e miniaturas, de modo que um arquivo PDF/A
continua declarando PDF/A), o padrão, e `PdfCompressionOptions.aggressive`
(também descarta metadados e a árvore de estrutura — o que custa a
acessibilidade e a conformidade).

#### Imagens

Imagens bilevel são reencodadas **sem perdas**. Nenhum codec ganha sempre, e
por isso o padrão mede em vez de supor: cada imagem é codificada em JBIG2 e em
Flate, e a menor vence. Numa página 800×1000, o Flate faz 287 bytes contra 886
do JBIG2 quando as linhas se repetem exatamente, e 20304 contra 16519 quando
há ruído de digitalização.

Imagens de tom contínuo só são tocadas se você pedir, porque isso significa
JPEG e possivelmente reamostragem:

```dart
final result = await PdfCompressor.compress(
  bytes,
  options: const PdfCompressionOptions(
    images: PdfImageCompressionOptions.lossy(quality: 75, maxDimension: 1600),
  ),
);
```

`maxDimension` é um limite em **pixels**, não um DPI alvo: decidir um DPI exige
a transformação que o fluxo de conteúdo da página aplica à imagem, que este
passo não lê.

### Codec JPEG

O decodificador lê o modo baseline sequencial — qualquer amostragem de
componentes (4:4:4, 4:2:2, 4:2:0), intervalos de reinício, cinza, RGB e CMYK
com a transformação Adobe. Arquivos progressivos e com codificação aritmética
são recusados com uma mensagem, em vez de decodificados errado.

```dart
final image = JpegDecoder.decode(jpegBytes);
final smaller = ImageResampler.resize(image.pixels,
    width: image.width, height: image.height,
    targetWidth: 800, targetHeight: 600, channels: 3);
final out = JpegEncoder.encode(smaller,
    width: 800, height: 600, quality: 85);
```

### Layout de texto

`Document` compõe parágrafos, divs, listas, tabelas com `colspan`/
`rowspan`, imagens e quebras de área sobre o kernel, com colapso de margens e
cálculo de largura mínima/máxima.

```dart
final doc = Document(pdfDocument);
await doc.add(Paragraph('Primeiro parágrafo'));
await doc.close();
```

### Assinatura digital

Assinatura RSA/CMS, contêineres externos, carimbo do tempo (RFC 3161), OCSP,
CRL e leitura de repositórios de chaves JKS e BKS, sobre `Uint8List`, sem
acesso obrigatório a arquivos:

```dart
final jks = JksKeyStore.read(jksBytes, password: storePassword);
final pkcs8 = (jks.entries[alias] as JksPrivateKey).recoverPkcs8(keyPassword);

final bks = BksKeyStore.decode(bksBytes, password: storePassword);
final key = bks.records.firstWhere((r) => r.alias == alias)
    .recoverKey(keyPassword);
```

### Modos opcionais de leitura, recuperação, mesclagem e assinatura

`readFileInBlocks`, `PdfRecoveryMode`, `PdfMergeMode` e `PdfSigningMode`, com
políticas explícitas para PDFs reparados e assinaturas importadas. Exemplos,
padrões e limites em
[test/compatibility/OPTIONAL_MODES.md](test/compatibility/OPTIONAL_MODES.md).

## Limitações conhecidas

- O módulo SVG tem a infraestrutura de processadores e renderizadores, mas
  ainda não os renderizadores de elementos, e por isso não é exportado.
- A redação por área rejeita fontes compostas (Type0/CID), cujas posições de
  glifo exigem uma CMap que a máquina de texto de byte único não lê.
- O conversor de HTML desenha com as 14 faces padrão; não há descoberta nem
  incorporação de fontes do sistema.
- A reamostragem de imagens usa um limite em pixels, não um DPI alvo.
- O encoder JBIG2 usa região genérica; um dicionário de símbolos venceria em
  páginas de texto.

## Desenvolvimento

```bash
dart test
dart analyze
dart run tool/check_platforms.dart   # VM/JIT, VM/AOT, dart2js e dart2wasm
```

`tool/check_platforms.dart` exige Node com WasmGC.

Para regenerar os recursos embutidos (lista de glifos Adobe e métricas das 14
fontes padrão) a partir dos arquivos em `lib/src/io/resources/`:

```bash
dart run tool/generate_font_resources.dart
```

## Licença

MIT, com os avisos dos dados de terceiros embutidos em
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
