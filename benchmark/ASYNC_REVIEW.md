# Auditoria de execução assíncrona

Data: 2026-09-06. Base da auditoria: c37c1b8. A tabela de evidências abaixo
descreve essa base; a refatoração posterior está registrada nesta seção.

## Refatoração aplicada após a auditoria

- CraftPdfTokenizer agora retorna valores diretamente, inclusive close,
  readFully, nextToken e nextValidToken. Aliases Sync compartilham o mesmo
  corpo; não há mais duas implementações do scanner.
- CraftCMapContentParser, leitura recursiva de operandos do canvas e análise
  de aparência padrão dos campos agora são síncronos.
- CraftRandomAccessSource e suas implementações em memória/delegação têm
  contrato síncrono. Implementações externas desse contrato precisam adaptar
  suas assinaturas.
- CraftPdfReader.close retorna void; os streams comuns e de xref usam leitura
  em lote. Removidos os awaits sobre tokenizer nos chamadores internos.
- Operadores padrão do canvas retornam void. O contrato de extensão aceita
  FutureOr<void>, e o processor aguarda somente callbacks que retornam Future.
  Testes verificam ordenação e propagação de erros dos dois tipos de callback.

Migração: remova await nessas chamadas; se usava `.then`, use o resultado
diretamente. Exceções dessas operações agora são lançadas durante a chamada,
em vez de entregues por Future. Em testes, use `expect(() => chamada(),
throwsA(...))`. O carregamento externo de CMap e os contratos de I/O
assíncrono continuam sendo aguardados.

Não houve conversão integral do grafo de objetos/dicionários, layout e edição
para uma API síncrona. A remoção dos wrappers acima não transforma processamento
de CPU em trabalho de background. `async_event_loop_vm_after.json` registra
uma execução posterior do mesmo benchmark; as poucas amostras não demonstram
ganho global de desempenho e o timer continua esperando no isolate principal.

Os Futures públicos não garantem execução em segundo plano. Parsing, merge,
extração, layout, compressão e criptografia local trabalham no isolate chamador.
Existe utilidade real nas fronteiras de I/O e nos callbacks externos assíncronos.

## Evidências do código

| Local | Comportamento observado |
| --- | --- |
| `lib/src/io/source/pdf_tokenizer.dart:488` | `nextToken` contém 18 pontos de await sobre `_file.read()` síncrono, inclusive em loops de bytes. Já existe `nextTokenSync`. |
| `lib/src/kernel/pdf/pdf_reader.dart:872` | `_readStream` copia bytes com um await por byte. Há primitivas de leitura em lote disponíveis. |
| `lib/src/io/source/pdf_tokenizer.dart:308` | `getStartxref` usa varredura síncrona dentro de método async sem await. |
| `lib/src/io/source/pdf_file_source_vm.dart:22` | Abertura e cache usam openSync, lengthSync, setPositionSync e readIntoSync. Leitura por blocos limita memória, mas pode bloquear em cache misses. |
| `lib/src/kernel/pdf/pdf_reader.dart:56` | `fromFile`, sem leitura por blocos, aguarda File.readAsBytes: I/O assíncrono real na VM, seguido de parsing local. |
| `lib/src/kernel/pdf/pdf_dictionary.dart:80` | Até consultas ao mapa estão envolvidas em Future; resolução de referências também pode executar parsing local. |
| `lib/src/platform/io_web.dart:43` | readAsBytes envolve cópia síncrona de memória. Já o transporte fetch, nas linhas 154–163, aguarda Promises de rede e arrayBuffer. |
| `lib/src/sign/pdf_signer.dart:301` | Hash local síncrono; o await do assinador externo é uma fronteira útil para serviços, hardware ou workers fornecidos pelo consumidor. |

As contagens são lexicais, não contagens de microtasks em execução. Não foi
medido o ganho de substituir os awaits internos por um núcleo síncrono.
O cliente TSA padrão ainda não implementa transporte; sua assinatura async
não significa que exista uma requisição HTTP funcional.

## Experimento reproduzível

Execute `dart run benchmark/async_event_loop_benchmark.dart 100`.
Resultado desta máquina: `async_event_loop_vm_baseline.json`.

Dart 3.6.2, Windows x64, JIT, 100 páginas sintéticas, três amostras por caso,
um aquecimento por caso. Construção do documento fora da medição. Merge reúne
duas cópias (200 páginas) e verifica o total; extração verifica o texto de todas
as páginas. Inclui abertura/fechamento e, no worker, inicialização e comunicação.

| Execução | Merge mediano | Extração mediana | Timer.zero executou antes do término |
| --- | ---: | ---: | --- |
| Future no mesmo isolate | 51,137 ms | 7,337 ms | 0 de 6 operações |
| Isolate.run | 48,215 ms | 7,722 ms | 6 de 6 operações |

O resultado demonstra responsividade do isolate principal neste experimento,
não ganho garantido de velocidade. Poucas amostras e documentos simples não
representam toda a biblioteca. A resolução de timers depende do sistema;
por isso registramos também Timer.zero, além do heartbeat periódico.
Não medimos frames Flutter nem executamos este benchmark em navegador/AngularDart.

## Consequências e prioridades

1. Manter async para I/O realmente assíncrono, sinks e assinadores externos.
2. Consolidar tokenizer/leitura de streams em núcleo síncrono e leituras em
   lote, com regressões e medição antes de alterar os contratos públicos.
   Essa otimização sozinha não torna o processamento não bloqueante.
3. Em Flutter nativo e servidores VM, executar trabalhos pesados completos em
   isolates. Para carga contínua, considerar pool limitado e contrapressão.
   Criar leitores e recursos de arquivo dentro do worker, passando bytes,
   caminhos e opções em vez de arquivos abertos.
4. Na Web, uma implementação de Web Worker é necessária para descarregar CPU;
   não há essa arquitetura automática na biblioteca auditada. Compilar para
   Wasm não cria uma thread. compute no Flutter Web usa o event loop atual.
5. Yield cooperativo em lotes pode permitir eventos, mas não paraleliza CPU.
   Future(() => trabalhoPesado()) apenas adia o bloqueio no mesmo isolate.

Referências oficiais: [concorrência em Dart](https://dart.dev/language/concurrency),
[microtasks e starvation](https://api.dart.dev/dart-async/scheduleMicrotask.html),
[compute nas plataformas](https://api.flutter.dev/flutter/foundation/compute.html).
