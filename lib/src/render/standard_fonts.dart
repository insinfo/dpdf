/// Substitutas embutidas para as catorze fontes padrão do PDF.
///
/// No VM resolve para os programas URW Core 35 que viajam dentro do pacote; na
/// web, onde carregar um megabyte de tipografia junto com o código seria um
/// custo imposto a quem não pediu, resolve para o stub que devolve `null` — e
/// o texto continua sendo medido, posicionado e relatado como não desenhado.
library;

export 'standard_fonts_portable.dart'
    if (dart.library.io) 'standard_fonts_vm.dart';
