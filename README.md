# pdfcraft

Biblioteca PDF em Dart, sem dependências externas de execução ou FFI.
Importe `package:pdfcraft/pdfcraft.dart`. Arquivos e rede usam abstrações de
plataforma; no navegador, arquivos locais são representados pelo registro em
memória exposto em `pdfcraft_web.dart`.

O teste `example/platform_smoke.dart` exercita criação, edição com múltiplas
fontes, extração com ActualText e Form XObjects, merge, assinatura RSA/CMS e
codecs PNG/G4. Execute `dart test`, `dart analyze` e
`dart run tool/check_platforms.dart`; o último requer Node com WasmGC e verifica
VM/JIT, VM/AOT, dart2js e dart2wasm, incluindo a compilação dos módulos da biblioteca.

A migração comportamental de `insinfo_dart_pdf` está em
[`test/compatibility`](test/compatibility/README.md), com testes adaptados,
fixtures sintéticas e inventário explícito dos grupos ainda pendentes. A API
pode ser adaptada; a substituição integral ainda não foi demonstrada.

A edição textual aceita páginas de texto com Courier/Helvetica Type1 não
incorporadas e codificações Standard/WinAnsi. Documentos fora desse subconjunto
são rejeitados. Redação geométrica geral, renderização equivalente ao MuPDF,
reconciliação completa de formulários no merge e PAdES avançado permanecem
pendentes. O cliente de timestamp analisa envelopes RFC 3161, mas ainda não
implementa transporte HTTP nem validação completa do token.

## Licenças e procedência

A licença MIT em `LICENSE` expressa a autorização sobre as contribuições próprias
do projeto. Recursos de terceiros mantêm seus termos específicos em
`THIRD_PARTY_NOTICES.md`, incluindo Adobe Glyph List, métricas AFM e a fonte
ABeeZee (OFL). As fixtures têm hashes em `test/assets/manifest.json`.

A revisão técnica comparou 401 classes com referências públicas e substituiu os
trechos operacionais e comentários identificados nesta etapa. Essa comparação
não demonstra a origem de cada linha do legado nem constitui certificação de
compatibilidade MIT de componentes ainda não rastreados. A licença do projeto
não concede direitos sobre material de terceiros além dos termos respectivos.

### Arquivos de chaves JKS e BKS

Os leitores públicos operam sobre `Uint8List`, sem acesso obrigatório a arquivos
ou dependências de execução:

```dart
import 'package:pdfcraft/pdfcraft.dart';

final jks = JksKeyStore.read(jksBytes, password: storePassword);
final entry = jks.entries[alias] as JksPrivateKey;
final pkcs8 = entry.recoverPkcs8(keyPassword);

final bks = BksKeyStore.decode(bksBytes, password: storePassword);
final key = bks.records.firstWhere((record) => record.alias == alias)
    .recoverKey(keyPassword);
final rewritten = bks.encode(password: newStorePassword);
```

JKS v1/v2 e BKS v2 verificam integridade antes de retornar entradas. A senha de
cada chave pode ser diferente da senha do contêiner. Regravar BKS muda a proteção
do contêiner, mantendo a senha e os bytes das chaves seladas. Os limites e a
procedência dos testes estão em [test/pki/KEYSTORE_PROVENANCE.md](test/pki/KEYSTORE_PROVENANCE.md).

A comparação com os bugs registrados no changelog da biblioteca de referência
está em [test/compatibility/CHANGELOG_REVIEW.md](test/compatibility/CHANGELOG_REVIEW.md),
com correções, testes de regressão e recursos ainda não implementados.

Testes com o JKS e a cadeia completa oficiais do ITI estão documentados em
[test/pki/ITI_CORPUS.md](test/pki/ITI_CORPUS.md), com download verificado e execução offline.

### Modos opcionais de leitura, recuperação, merge e assinatura

Foram adicionados `readFileInBlocks`, `PdfRecoveryMode`, `PdfMergeMode` e
`PdfSigningMode`, com políticas explícitas para PDFs reparados e assinaturas
importadas. Exemplos, padrões e limites estão em
[test/compatibility/OPTIONAL_MODES.md](test/compatibility/OPTIONAL_MODES.md).
