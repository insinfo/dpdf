# Leitura, recuperação, merge e assinatura opcionais

As opções abaixo usam apenas SDK Dart e implementação local. O padrão de leitura
continua estrito; recuperação e reconciliações adicionais de merge precisam ser
selecionadas pelo chamador.

## Leitura por blocos e reconstrução

```dart
final options = CraftReaderProperties()
  ..readFileInBlocks = true
  ..fileBlockSize = 256 * 1024
  ..fileCacheBlocks = 32
  ..recoveryMode = PdfRecoveryMode.skipStreams;
final reader = await CraftPdfReader.fromFile('entrada.pdf', options);
final document = await CraftPdfDocument.open(reader);
print(document.wasRepaired);
await document.close();
```

`readFileInBlocks` atua no Dart VM. Na web, use bytes ou uma implementação de
`PdfByteSource`, passada a `CraftPdfReader.fromSource`. A fonte de arquivo é
selecionada por importação condicional, sem incluir `dart:io` na compilação web.
`PdfFileSource` expõe `cachedBytes` e `bytesRead` para medir o cache.

`PdfRecoveryMode.strict` rejeita xref danificado. `scan` reconstrói por varredura;
`skipStreams` usa `/Length` para saltar payloads somente após verificar seu fim,
com varredura de delimitadores como fallback. Ambos recuperam referências,
gerações, catálogo, objetos comprimidos em ObjStm e comprimentos de streams.
`recoveryScanLimit` limita o tamanho lógico aceito para recuperação (256 MiB por
padrão); `recoveryObjectLimit` limita identificadores e quantidade de objetos.
Esses limites podem ser aumentados explicitamente para arquivos maiores.

O cache limita entrada de arquivo, não a memória de todo o documento: objetos e
streams efetivamente usados ainda precisam de memória. A gravação incremental
copia a entrada em blocos. Assinatura continua preparando a saída em memória.
Reconstrução de PDFs criptografados é rejeitada; delimitadores dentro de streams
sem comprimento confiável podem ser ambíguos. O reparo não comprova integridade
criptográfica nem recupera automaticamente a semântica de entradas livres de
uma xref perdida.

## Merge

```dart
final bytes = await PdfPageAssembly.merge(
  [PdfPageSelection(inputBytes, pages: [3, 1, 3], readerProperties: options)],
  mode: PdfMergeMode.objectImport,
  includeAnnotations: true,
  preserveForms: true,
  preserveOutlines: true,
  resolveNamedDestinations: true,
  preserveLayers: true,
  preservePageLabels: true,
  signaturePolicy: PdfMergeSignaturePolicy.removeKeepAppearance,
);
```

- `objectImport` copia o grafo e as estruturas opcionais selecionadas.
- `flatten` transforma conteúdo e aparências normais `/AP/N` em Forms gráficos,
  removendo interação. Aparências são posicionadas usando Rect/BBox/Matrix.
- Formulários preservam valores, hierarquia, widgets e campos sem widget.
  Colisões de nomes ganham sufixos; recursos de fontes/DA são reconciliados.
  Páginas repetidas compartilham o campo, com widgets independentes.
- Destinos nomeados e links internos apontam para as páginas importadas; um
  destino para página omitida é rejeitado. Em repetições, aponta para a primeira.
- Camadas mantêm identidade por fonte e visibilidade estática. Rótulos mantêm
  prefixo/estilo/numeração, ajustados à seleção e à reordenação.

As políticas de assinatura são `reject` (padrão), `removeKeepAppearance`,
`removeAppearance` e `keepInvalid`. A última preserva dados de uma assinatura
que não valida o novo arquivo e é incompatível com flatten. A remoção impede
copiar o CMS para objetos órfãos; manter aparência não preserva a assinatura.

Continuam rejeitados XFA, árvores de estrutura marcada, ações não conciliadas,
regras automáticas/configurações alternativas de camadas e aparências visíveis
que não podem ser reproduzidas. Isso evita descarte silencioso dessas estruturas.

## Assinatura e gravação após reparo

```dart
final signer = CraftPdfSigner.fromBytesBuilder(inputBytes, output,
  readerProperties: options,
  mode: PdfSigningMode.incremental,
  repairedSaveMode: PdfRepairedSaveMode.fullRewrite,
);
await signer.signDetached(privateKeySigner, certificateChain);
```

`PdfSigningMode.incremental` é o padrão e conserva as revisões anteriores.
`fullRewrite` também pode ser selecionado para PDFs sem reparo. Ao reconstruir
xref, o padrão `PdfRepairedSaveMode.reject` impede uma revisão incremental com
Prev inválido. A opção `fullRewrite` escreve uma nova tabela e remove Prev.
Ela não conserva a validade de assinaturas anteriores.

Para edição, configure a mesma política em
`CraftStampingProperties()..useAppendMode()..repairedSaveMode = PdfRepairedSaveMode.fullRewrite`.
Não existe opção para gravar deliberadamente um Prev sem tabela válida.

## Evidências

Os testes estão em `pdf_recovery_test.dart`, `block_source_test.dart`,
`repaired_signature_test.dart`, `merge_modes_test.dart`,
`form_merge_policy_test.dart` e `form_style_loading_test.dart`.
Um PDF sintético de 4 MiB abre e é recuperado em skipStreams com menos de 150 KB
lidos da fonte e cache limitado a 16 KB. Isso é uma regressão de acesso aos
blocos, não um benchmark comparativo com MuPDF ou um corpus de vários GB.

Validação final em 2026-09-06: 1.044 testes aprovados (incluindo corpus ITI
preparado), análise estática limpa e teste integrado executado em VM/JIT, AOT,
JavaScript e WebAssembly via Node. As 458 bibliotecas aplicáveis compilaram
para JS e WASM; implementações exclusivas da VM são selecionadas condicionalmente.
