import 'dart:typed_data';

import 'glyph_source.dart';
import 'resources/standard_font_programs_vm.dart';

/// Desenha as catorze fontes padrão do PDF com as URW Core 35 embutidas.
///
/// As catorze existem como especificação de métricas, não como arquivo que se
/// possa distribuir: um PDF que referencia `Helvetica` sem embuti-la conta com
/// o leitor para ter algo equivalente. As URW foram desenhadas exatamente para
/// isso — são **metricamente compatíveis**, o mesmo conjunto que o Ghostscript
/// usa —, então as larguras do `/Widths` que o produtor usou para diagramar a
/// página continuam valendo e a linha termina onde deveria.
///
/// Isso ainda **não é** a fonte original, e o relatório diz quais fontes foram
/// trocadas em `PdfRenderReport.fontsSubstituted`. Mas, diferente de procurar
/// no sistema, o resultado é o mesmo em qualquer máquina: é o que permite
/// comparar pixels entre execuções.
///
/// Uma fonte não embutida que não seja nenhuma das catorze também recebe
/// substituta, escolhida pelo `/Flags` do descritor: serifada, monoespaçada ou
/// sem serifa. É o que os leitores fazem, e mantém a página legível em vez de
/// vazia.
PdfFontFallback? standardFontFallback() {
  return (request) async => _programFor(request);
}

/// Nome da face URW para [request], ou null quando não há substituta honesta.
String? standardFaceName(PdfFontRequest request) {
  // Uma fonte composta endereça glifos por CID, e o CID só significa alguma
  // coisa dentro do programa que o produtor usou: sem ele não há como saber
  // que glifo o CID 42 designa. Emprestar o índice para outra tipografia
  // desenharia caracteres aleatórios — pior do que não desenhar.
  if (request.composite) return null;

  final family = _normalize(request.familyName);
  var kind = _byName(family);
  if (kind == null) {
    // Uma fonte simbólica traz o próprio conjunto de glifos; nenhuma fonte de
    // texto serve no lugar dela. `Symbol` e `ZapfDingbats` não caem aqui:
    // esses dois são reconhecidos pelo nome acima e têm substituta exata.
    if (request.isSymbolic) return null;
    kind = request.isFixedPitch
        ? _Kind.mono
        : (request.isSerif ? _Kind.serif : _Kind.sans);
  }

  final bold = request.isBold;
  final italic = request.isItalic;
  switch (kind) {
    // Symbol e ZapfDingbats têm um corte só: a especificação não define
    // negrito nem itálico para elas.
    case _Kind.symbol:
      return 'StandardSymbolsPS';
    case _Kind.dingbats:
      return 'D050000L';
    case _Kind.sans:
      // O corte inclinado da Helvetica chama-se Oblique, não Italic.
      return 'NimbusSans-${bold && italic ? 'BoldOblique' : bold ? 'Bold' : italic ? 'Oblique' : 'Regular'}';
    case _Kind.serif:
      return 'NimbusRoman-${bold && italic ? 'BoldItalic' : bold ? 'Bold' : italic ? 'Italic' : 'Regular'}';
    case _Kind.mono:
      return 'NimbusMonoPS-${bold && italic ? 'BoldItalic' : bold ? 'Bold' : italic ? 'Italic' : 'Regular'}';
  }
}

/// Os programas já descomprimidos, por face.
///
/// Inflar custa mais que analisar: guardar evita repetir o trabalho a cada
/// página, e as catorze somam pouco mais de um megabyte se todas forem usadas.
final Map<String, Uint8List> _inflated = <String, Uint8List>{};

Uint8List? _programFor(PdfFontRequest request) {
  final face = standardFaceName(request);
  if (face == null) return null;
  final cached = _inflated[face];
  if (cached != null) return cached;
  final bytes = StandardFontPrograms.program(face);
  if (bytes == null) return null;
  return _inflated[face] = bytes;
}

/// Os cinco desenhos distintos entre as catorze.
enum _Kind { sans, serif, mono, symbol, dingbats }

/// Classifica pelo `/BaseFont`, incluindo os apelidos que produtores usam no
/// lugar dos nomes canônicos.
_Kind? _byName(String family) {
  if (family.contains('zapfdingbats') ||
      family == 'dingbats' ||
      family == 'd050000l') {
    return _Kind.dingbats;
  }
  if (family == 'symbol' ||
      family.startsWith('symbolmt') ||
      family.startsWith('standardsymbols')) {
    return _Kind.symbol;
  }
  if (family.startsWith('courier') ||
      family.startsWith('nimbusmono') ||
      family.startsWith('liberationmono') ||
      family.startsWith('monospace')) {
    return _Kind.mono;
  }
  if (family.startsWith('times') ||
      family.startsWith('nimbusroman') ||
      family.startsWith('liberationserif') ||
      family.startsWith('serif')) {
    return _Kind.serif;
  }
  if (family.startsWith('helvetica') ||
      family.startsWith('arial') ||
      family.startsWith('nimbussans') ||
      family.startsWith('liberationsans') ||
      family.startsWith('sansserif')) {
    return _Kind.sans;
  }
  return null;
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s,_-]'), '');
