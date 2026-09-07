# Compatibilidade de campos AcroForm

`form_field_roundtrip_test.dart` adapta cenários de
`C:/MyDartProjects/insinfo_dart_pdf/test/forms/form_field_types_test.dart`
aos construtores e métodos assíncronos de dpdf. Os casos são reexpressos
com APIs Craft e dicionários PDF públicos; não usam aliases que simulem a API
original. Nenhum engine ou asset da biblioteca de origem foi copiado.

Cobertura portada: texto; multiline/password/readonly e MaxLen; edição de texto
reaberto; estado de checkbox; combo com rótulo/exportação; combo editável; lista
com seleção múltipla; grupo radio e seus dois widgets. Sete testes agrupam esses
cenários. O caso original de lista simples é representado pela mesma seleção
unitária de campos Ch, mas não foi transplantado como teste separado.

Correções encontradas: seleção de opções usava rótulos no lugar de valores de
exportação e não gravava índices quando recebia esses valores; adicionar um
grupo ao AcroForm cadastrava o próprio campo como annotation em vez de cada
widget; radio criava aparência antes de associar o widget ao documento.
Os testes radio conferem agora AP/N e estados Off/selecionado após reabertura.

Não são reivindicados nesta etapa: estilo estrela de checkbox, pintura completa
de checkbox/texto/listas, botões de ação, assinatura vazia, remoção, flattening,
merge de formulários ou atualização automática das aparências ao editar valores.
A tabela/formatação pública foi preservada; a funcionalidade portável usa só SDK.
