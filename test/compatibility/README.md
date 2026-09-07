> Atualização posterior: reconstrução de xref (incluindo ObjStm), leitura por
> blocos e modos adicionais de merge foram implementados. Consulte
> [OPTIONAL_MODES.md](OPTIONAL_MODES.md) para a API atual. As observações abaixo
> registram o estado da etapa anterior e seus testes.

# Migração comportamental de dart_pdf

Os testes desta pasta adaptam chamadas para a API assíncrona de dpdf,
conforme autorizado pelo usuário. `migration_inventory.json` registra os 89
arquivos de testes da referência, hashes e o estado de migração. A contagem de
545 declarações na referência é lexical; não significa 545 testes aprovados.

Execute `dart test test/compatibility`. Os testes não dependem da instalação de
dart_pdf. A biblioteca de origem foi usada separadamente como referência de
comportamento; seu engine e suas dependências não foram incorporados.

As três fixtures em `assets` são sintéticas e foram copiadas por autorização
expressa. A origem e os hashes estão no manifesto dessa pasta. Não foram
incluídos os documentos pessoais e o arquivo PFX encontrados na referência.
Essas fixtures PDF permanecem excluídas do pacote publicado por `.pubignore`;
os testes completos podem ser executados a partir deste repositório.

## Chamadas equivalentes nesta etapa

| Operação na referência | API em dpdf |
| --- | --- |
| `appendGraphics()` | `await PdfPageOverlay.create(page)` |
| Merge de anotações estáticas | `PdfPageAssembly.merge(..., includeAnnotations: true)` |
| Merge de marcadores com destinos locais explícitos | `PdfPageAssembly.merge(..., preserveOutlines: true)` |
| Inspeção de cabeçalho | `await PdfQuickInfo.fromBytes(bytes, readDocument: false)` |
| DocMDP declarado | `await PdfQuickInfo.fromBytes(bytes)` |
| Formulários | `CraftPdfAcroForm` e campos exportados por `dpdf.dart` |
| Comentários e serial de certificado | Exports correspondentes em `dpdf.dart` |

O overlay utiliza coordenadas PDF, com origem inferior esquerda, e Forms com
recursos separados. Seus testes verificam sobrevivência após reabertura,
chamadas repetidas, recursos herdados e isolamento de transformações. Uma
verificação externa de leitura confirmou a posição da linha de base do texto;
o leitor externo não é dependência da biblioteca. Conteúdo marcado com tags e
imagens inline ainda são rejeitados pelo overlay. A fundamentação dos Forms
está na seção 8.10 da [especificação PDF](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf).

Os dois parâmetros de merge podem ser combinados; o modo padrão permanece
estrito. Marcadores que apontam para páginas omitidas ou destinos nomeados
ainda são rejeitados. Na duplicação de uma página dentro da mesma seleção,
o marcador aponta para a primeira ocorrência.

Os testes de formulários cobrem valores, opções, widgets e aparências dos tipos
texto, checkbox, combo, lista e rádio. O teste de documentos carregados exercita
inserção, remoção, rotação, metadados Unicode e XMP, tanto em regravação quanto
em revisão incremental, incluindo a preservação dos bytes da revisão anterior.

O merge de anotações não cobre widgets nem ações entre páginas. A inspeção de
DocMDP informa a declaração, sem validar assinatura, confiança ou cumprimento
da política. Os testes adicionais e seus limites constam dos arquivos de
procedência desta pasta. A substituição integral da biblioteca ainda não foi
demonstrada: os grupos pendentes permanecem explicitamente no inventário.

## Desempenho

`dart run benchmark/compatibility_benchmark.dart` mede abertura com extração e
merge de três cópias de uma fixture de três páginas. A primeira comparação está
em `benchmark/compatibility_baseline.json`, com runtime, amostras, aquecimento,
medianas, verificação do resultado e tamanho da saída. Essa fixture pequena
não representa o desempenho em documentos gerais.

## Validação desta etapa

Em 2026-09-06, `dart test` aprovou 927 testes, dos quais 64 estão nesta pasta,
e `dart analyze` terminou sem problemas. Naquele momento, o inventário continha 80 dos 89
arquivos da referência com estado pendente; os demais têm cobertura adaptada
ou parcial. Esses números não demonstram equivalência integral entre as bibliotecas.

O teste integrado executou com sucesso em VM/JIT, executável AOT, dart2js e
dart2wasm (os dois últimos em Node). Também foi compilada a superfície de 450
bibliotecas para JS e WASM. Isso verifica compilação e os fluxos exercitados,
sem afirmar que todos os testes da suíte foram executados em navegador.

A etapa posterior de PKI adaptou também `bks_keystore_test.dart` em `test/pki`,
reduzindo para 79 os arquivos da referência ainda com estado pendente.
