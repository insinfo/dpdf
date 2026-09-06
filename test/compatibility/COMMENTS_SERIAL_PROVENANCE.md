# Origem dos testes de comentários e número serial

Os arquivos `pdf_percent_comments_test.dart`, `pdf_comment_sanitizer_test.dart`
e `certificate_serial_test.dart` foram transplantados dos testes correspondentes
em `C:/MyDartProjects/insinfo_dart_pdf/test`, por solicitação expressa do usuário.
Não foi encontrado LICENSE na raiz da origem durante esta etapa. Este registro
identifica a origem, sem atribuir uma licença presumida a esses arquivos.

Alterações: imports apontam explicitamente para os módulos novos de pdfcraft;
formatação Dart; o teste sanitizer usa uma sequência própria de bytes em lugar
do arquivo externo `slow_pdf.pdf`. As expectativas originais foram preservadas.
`comment_serial_guards_test.dart` contém testes novos de fronteiras e integridade.

Os dois módulos `lib/src/compatibility/pdf_percent_comments.dart` e
`certificate_serial.dart` foram escritos a partir dos contratos observados nos
testes, sem ler ou copiar a implementação da biblioteca de origem. Usam somente
o SDK Dart. Não foi transplantado nenhum recurso binário externo.

Limites: a extração percorre linhas físicas, não interpreta streams ou strings
PDF. O sanitizer altera somente comentários ASCII anteriores ao primeiro objeto,
mantém comprimento/terminadores e não valida assinaturas. O leitor de serial
aceita TLV iniciado por 0x02 ou bytes de magnitude; entradas iniciadas por 0x02
com mais de um byte são interpretadas como TLV, evitando aceitar DER malformado
silenciosamente. QuickInfo e inspeção declarativa de DocMDP são cobertos separadamente por
`pdf_quick_info_test.dart`; estes utilitários não validam essas estruturas.
