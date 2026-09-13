/// Fontes instaladas na máquina, quando a plataforma tem sistema de arquivos.
///
/// No VM a implementação varre os diretórios de fontes do sistema; na web, que
/// não tem disco nem `dart:io`, resolve para o stub que devolve `null` — e o
/// renderizador segue relatando o texto como não desenhado, como antes.
library;

export 'system_fonts_portable.dart'
    if (dart.library.io) 'system_fonts_vm.dart';
