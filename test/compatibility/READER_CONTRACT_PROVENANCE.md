# Contrato de entradas inválidas do leitor

`reader_garbage_contract_test.dart` adapta os seis cenários `_garbage()` de
`C:/MyDartProjects/insinfo_dart_pdf/test/api_contract_test.dart`: vazio, prosa,
cabeçalho isolado, cabeçalho seguido de zeros/letras e um único byte.
A API síncrona original foi substituída explicitamente por
`CraftPdfDocument.open(CraftPdfReader.fromBytes(...))`, com fechamento assíncrono.
Foram acrescentados três casos próprios de xref truncado ou fora dos limites.

O contrato adaptado aceita exceções recuperáveis de dpdf; não aceita `Error`
e não captura genericamente erros da implementação. Não houve transplante de
arquivos PDF nem leitura/cópia do engine da biblioteca de origem. A autorização
para usar os testes veio da solicitação do usuário; não foi presumida uma licença
para o restante do repositório de origem.

A mudança no leitor valida posições xref antes de acessar o buffer e restringe
um catch existente a `Exception`. Esses testes não constituem auditoria de todas
as mutações ou de todos os caminhos de parsing.
