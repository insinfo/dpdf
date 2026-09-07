> Atualização posterior: reconstrução de xref (incluindo ObjStm), leitura por
> blocos e modos adicionais de merge foram implementados. Consulte
> [OPTIONAL_MODES.md](OPTIONAL_MODES.md) para a API atual. As observações abaixo
> registram o estado da etapa anterior e seus testes.

# Revisão das correções da biblioteca de referência

Data: 2026-09-06. Referência: `C:/MyDartProjects/insinfo_dart_pdf/CHANGELOG.md`,
versões 1.0.0 e 1.0.1, SHA-256
`74d39a0a195ead0886ab15cd6ce830be7ec19db83b08276accc98b818b6c5d3d`.
Os cenários foram usados para escrever testes e corrigir implementações locais.
Nenhum engine da referência foi transplantado nesta revisão.

## Resultado por grupo do changelog

| Cenário | Situação no dpdf e evidência |
| --- | --- |
| Desenhar em página importada substitui recursos e corrompe fontes | Não reproduzido na API `PdfPageOverlay`; novo teste de merge seguido de overlay preserva texto original e recursos herdados. |
| Carimbo desaparece ao salvar destino carregado | Não reproduzido; novo teste reabre o destino, aplica overlay, salva e reabre novamente. |
| Estado gráfico anterior desloca/recorta overlay | Coberto pelos testes existentes de transformações desequilibradas, recursos e reabertura em `loaded_page_overlay_test.dart`. |
| Resources/MediaBox/CropBox/Rotate herdados se perdem no merge | Novo teste confirma preservação em páginas reordenadas e repetidas. |
| Cadeia Parent cíclica é aceita parcialmente | Corrigido: merge agora rejeita ciclo e profundidade excessiva com erro de formato; regressão específica. |
| Destinos de marcadores após reordenação | Testes de `merge_outlines_test.dart` preservam destinos locais explícitos e propriedades visuais/hierarquia. |
| Destinos nomeados inline ou arrays ímpares | Não implementados no merge; os dois cenários são rejeitados explicitamente, sem null-check/índice inválido. Isso não equivale a suportá-los. |
| Campos de formulário, widgets múltiplos e campos sem widget no merge | Merge de AcroForm/widgets continua não implementado e é rejeitado; não foi declarada preservação desses campos. |
| Camadas, page labels e merge por flatten | Fora das capacidades atuais do merge; não implementados nesta auditoria. |
| Remoção de assinaturas e dicionários órfãos no merge | Não existe a política equivalente de importar/remover campos assinados; documentos com estruturas de formulário não suportadas são rejeitados. Não se afirma preservação de assinaturas após merge. |
| Compartilhamento de objetos entre páginas | Clone do grafo possui mapa por documento; testes de assembly e repetição continuam passando. Não foi medido consumo em corpus de vários GB. |
| startxref inválido, ausente ou xref malformado | Sem reconstrução automática; leitura falha explicitamente. Corrigido indicador `rebuiltXref` que antes ficava verdadeiro mesmo sem reconstrução. |
| Salvar documento reparado gera Prev inválido | Caminho de reparo não existe; abertura rejeita xref danificado antes da gravação. Revisões incrementais válidas têm testes próprios. |
| Root ausente ou não dicionário causa TypeError | Não reproduzido: quatro regressões confirmam `PdfException` para referências inválidas, null e número. |
| Referências antigas apontam para geração atual | Corrigido: gerações divergentes não resolvem silenciosamente. Testes com geração não zero e revisão incremental mais recente. |
| Xref aponta para cabeçalho de outro objeto | Corrigido: o cabeçalho lido precisa corresponder ao número e à geração esperados. |
| Comprimento de stream inválido causa RangeError/alocação indevida | Corrigido: comprimento negativo ou além dos bytes disponíveis é rejeitado antes da alocação. |
| Busca reversa lenta e omissão de prefixo | Corrigido: busca de startxref compara bytes, não cria strings por bloco e inclui offset zero. Testes de limites e entrada de 2 MiB. |
| Cabeçalho curto causa erro de índice | Corrigido: `%PDF-`, `%PDF-1` e `%PDF-1.` produzem exceção de entrada. |
| Reconstrução lenta, skipStreams e leitura por janela | Não implementados; não existe equivalência com os tempos publicados para PDFs de vários GB. |
| List<int> growable multiplica memória do PDF | Principais buffers atuais usam Uint8List/BytesBuilder. Assinatura ainda materializa o PDF e cópias em memória; não é streaming com memória constante. |
| Assinatura em saída baseada em bytes perde os patches | Testes existentes `memory_signature_roundtrip_test.dart` e assinatura múltipla passaram: ByteRange e Contents são preenchidos na saída. |
| Escrita direta em sink e fonte de arquivo por blocos | A escrita oferece sink, mas `fromFile` ainda lê o arquivo inteiro. Leitura com cache/janela e assinatura com memória constante não estão implementadas. |
| Datas ignoram offset ou interpretam Z como fuso local | Corrigido `PdfDate.decode`: offset explícito resulta em UTC, preservando o instante. Sem timezone continua local, documentado; datas inválidas não são normalizadas silenciosamente. |
| Datas truncadas causam RangeError | Corrigido e testado como FormatException; datas parciais válidas recebem os campos padrão. |
| Classificar todo dado malformado como Exception | Melhorado nos casos reproduzidos acima. Não é certificação de todos os caminhos de erro; testes de garbage anteriores também passaram. |
| adbe.pkcs7.sha1 aceita conteúdo ausente ou verifica digest errado | Corrigido: exige eContent de 20 bytes e SHA1(ByteRange)==eContent; messageDigest usa digest(eContent), independentemente da ordem das chamadas. |
| Assinaturas encapsuladas com/sem atributos e adulteração | Novos testes sintéticos com RSA real cobrem ambos, documento/eContent/digest alterados e assinatura destacada rotulada incorretamente. Não foi importado o corpus pessoal ICP-Brasil. |

## Validação

25 testes novos distribuídos entre `changelog_date_tokenizer_test.dart`,
`changelog_reader_regression_test.dart`, `changelog_merge_regression_test.dart`
e `changelog_legacy_signature_test.dart`. Antes da correção local de datas e
busca, seis dos sete testes desse grupo falharam; após as correções passaram.
A suíte completa aprovou 986 testes e `dart analyze` terminou sem problemas.

Uma limitação adicional encontrada foi a falta de AFM de Courier na fábrica de
fontes. O teste de importação usa Helvetica e não declara resolvida essa lacuna.
As capacidades ausentes nesta tabela continuam pendentes; rejeitá-las de forma
explícita não constitui implementação equivalente à biblioteca de referência.

O teste integrado executou em VM/JIT, AOT, JavaScript e WebAssembly (Node).
Inclui a preservação do offset de data e a busca no primeiro bloco; a superfície
de 454 bibliotecas também compilou em JS e WASM. Os 986 testes da suíte foram
executados na VM, não todos em navegador.
