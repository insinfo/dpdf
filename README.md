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
