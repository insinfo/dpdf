import 'glyph_source.dart';

/// Sem sistema de arquivos não há catálogo de fontes para consultar.
///
/// No navegador as fontes instaladas não são legíveis por bytes: o que existe
/// é a lista de famílias que o CSS pode nomear, e o dpdf precisa do programa
/// da fonte para extrair contornos. Devolver `null` aqui mantém o
/// comportamento honesto — o texto continua sendo medido, posicionado e
/// relatado como não desenhado. Um cliente web que queira o texto desenhado
/// fornece os bytes por conta própria em `PdfRenderOptions.fontFallback`,
/// baixando a fonte de uma URL.
PdfFontFallback? systemFontFallback({List<String>? directories}) => null;

/// Nenhum diretório de fontes para varrer fora do VM.
List<String> systemFontDirectories() => const <String>[];
