import 'dart:io';
import 'dart:typed_data';

import 'package:dgfx/dgfx.dart';

import 'glyph_source.dart';

/// Procura nas fontes instaladas um substituto para a fonte que o PDF não
/// embutiu.
///
/// É a camada opcional da substituição, e não a principal: as catorze padrão
/// já têm substitutas embutidas e determinísticas em `standard_fonts.dart`.
/// O que esta camada acrescenta é a chance de achar a tipografia que o
/// produtor realmente nomeou, quando ela está instalada — mais fiel, porém
/// dependente da máquina. Duas execuções em máquinas diferentes podem desenhar
/// páginas diferentes, e é por isso que `PdfRenderOptions.useSystemFonts`
/// começa desligado.
///
/// O que ele devolve continua **não sendo** a fonte do documento quando o
/// nome não bate exatamente: o posicionamento vem do `/Widths` do PDF e os
/// contornos vêm de outro arquivo. Toda troca é contada em
/// `PdfRenderReport.fontsSubstituted`.
///
/// [directories] substitui os diretórios de fontes do sistema — é o gancho
/// que os testes usam para não depender do que está instalado na máquina.
/// Passar uma lista vazia desliga a busca sem desligar o resto.
PdfFontFallback? systemFontFallback({List<String>? directories}) =>
    _SystemFonts.forDirectories(directories).resolve;

/// Os diretórios habituais de fontes da plataforma corrente.
List<String> systemFontDirectories() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    final windows = env['WINDIR'] ?? env['SystemRoot'] ?? r'C:\Windows';
    final local = env['LOCALAPPDATA'];
    return <String>[
      '$windows\\Fonts',
      // Fontes instaladas "para este usuário" desde o Windows 10 1803.
      if (local != null) '$local\\Microsoft\\Windows\\Fonts',
    ];
  }
  final home = env['HOME'];
  if (Platform.isMacOS) {
    return <String>[
      '/System/Library/Fonts',
      '/System/Library/Fonts/Supplemental',
      '/Library/Fonts',
      if (home != null) '$home/Library/Fonts',
    ];
  }
  if (Platform.isAndroid) {
    return const <String>['/system/fonts', '/product/fonts', '/vendor/fonts'];
  }
  if (Platform.isIOS) {
    return const <String>['/System/Library/Fonts', '/Library/Fonts'];
  }
  return <String>[
    '/usr/share/fonts',
    '/usr/local/share/fonts',
    '/usr/share/texmf/fonts/opentype',
    if (home != null) '$home/.fonts',
    if (home != null) '$home/.local/share/fonts',
  ];
}

/// A que grupo de desenho a fonte pedida pertence.
enum _Kind {
  sans,
  serif,
  mono,

  /// `Symbol`, cujo conjunto de glifos é o da Adobe e não o Unicode.
  symbol,

  /// `ZapfDingbats`, idem.
  dingbats,

  /// Uma fonte marcada como simbólica que não é nenhuma das padrão. Não há
  /// substituto genérico possível: só serve o arquivo daquela fonte mesmo.
  symbolic,
}

/// Arquivos aceitáveis para cada grupo, do mais próximo ao mais distante.
class _Files {
  final List<String> regular;
  final List<String> bold;
  final List<String> italic;
  final List<String> boldItalic;

  const _Files({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });

  /// Nomes a tentar, na ordem, para o peso e a inclinação pedidos.
  ///
  /// Faltando o corte exato, um Arial normal no lugar de um negrito ainda
  /// desenha o texto; a alternativa é página em branco.
  List<String> forStyle({required bool bold, required bool italic}) => <String>[
        if (bold && italic) ...boldItalic,
        if (bold) ...this.bold,
        if (italic) ...this.italic,
        ...regular,
      ];
}

/// Windows, macOS, as clones métricas do Ghostscript/URW (Nimbus), as da
/// Red Hat (Liberation) e as livres mais comuns (DejaVu, Noto, GNU FreeFont).
/// Os nomes estão normalizados: minúsculas, sem espaços nem sublinhados.
const _tables = <_Kind, _Files>{
  _Kind.sans: _Files(
    regular: [
      'arial',
      'helvetica',
      'liberationsans-regular',
      'nimbussans-regular',
      'dejavusans',
      'notosans-regular',
      'freesans',
      'verdana',
    ],
    bold: [
      'arialbd',
      'arialbold',
      'helvetica-bold',
      'helveticabold',
      'liberationsans-bold',
      'nimbussans-bold',
      'dejavusans-bold',
      'notosans-bold',
      'freesansbold',
      'verdanab',
    ],
    italic: [
      'ariali',
      'arialitalic',
      'helvetica-oblique',
      'helveticaoblique',
      'liberationsans-italic',
      'nimbussans-italic',
      'dejavusans-oblique',
      'notosans-italic',
      'freesansoblique',
      'verdanai',
    ],
    boldItalic: [
      'arialbi',
      'arialbolditalic',
      'helvetica-boldoblique',
      'liberationsans-bolditalic',
      'nimbussans-bolditalic',
      'dejavusans-boldoblique',
      'notosans-bolditalic',
      'freesansboldoblique',
      'verdanaz',
    ],
  ),
  _Kind.serif: _Files(
    regular: [
      'times',
      'timesnewroman',
      'timesnewromanpsmt',
      'liberationserif-regular',
      'nimbusroman-regular',
      'dejavuserif',
      'notoserif-regular',
      'freeserif',
      'georgia',
    ],
    bold: [
      'timesbd',
      'timesnewromanbold',
      'timesbold',
      'liberationserif-bold',
      'nimbusroman-bold',
      'dejavuserif-bold',
      'notoserif-bold',
      'freeserifbold',
      'georgiab',
    ],
    italic: [
      'timesi',
      'timesnewromanitalic',
      'timesitalic',
      'liberationserif-italic',
      'nimbusroman-italic',
      'dejavuserif-italic',
      'notoserif-italic',
      'freeserifitalic',
      'georgiai',
    ],
    boldItalic: [
      'timesbi',
      'timesnewromanbolditalic',
      'liberationserif-bolditalic',
      'nimbusroman-bolditalic',
      'dejavuserif-bolditalic',
      'notoserif-bolditalic',
      'freeserifbolditalic',
      'georgiaz',
    ],
  ),
  _Kind.mono: _Files(
    regular: [
      'cour',
      'couriernew',
      'liberationmono-regular',
      'nimbusmonops-regular',
      'dejavusansmono',
      'notosansmono-regular',
      'freemono',
      'consola',
    ],
    bold: [
      'courbd',
      'couriernewbold',
      'liberationmono-bold',
      'nimbusmonops-bold',
      'dejavusansmono-bold',
      'notosansmono-bold',
      'freemonobold',
      'consolab',
    ],
    italic: [
      'couri',
      'couriernewitalic',
      'liberationmono-italic',
      'nimbusmonops-italic',
      'dejavusansmono-oblique',
      'freemonooblique',
      'consolai',
    ],
    boldItalic: [
      'courbi',
      'couriernewbolditalic',
      'liberationmono-bolditalic',
      'nimbusmonops-bolditalic',
      'dejavusansmono-boldoblique',
      'freemonoboldoblique',
      'consolaz',
    ],
  ),
  // Symbol e ZapfDingbats não têm corte negrito nem itálico: uma única lista.
  _Kind.symbol: _Files(
    regular: ['symbol', 'symbolmt', 'standardsymbolsps', 'standardsymbolsl'],
    bold: [],
    italic: [],
    boldItalic: [],
  ),
  _Kind.dingbats: _Files(
    regular: ['zapfdingbats', 'dingbats', 'd050000l'],
    bold: [],
    italic: [],
    boldItalic: [],
  ),
};

/// Famílias que um arquivo tem de declarar para valer como `Symbol`.
///
/// O nome do arquivo não basta: `seguisym.ttf` (Segoe UI Symbol) traz um
/// conjunto Unicode completamente diferente, e `wingding.ttf` responde aos
/// mesmos códigos 0xF0xx com outros desenhos. Desenhar qualquer um dos dois no
/// lugar de Symbol trocaria alfa por 'a' ou por uma mão apontando. Recusar
/// aqui não deixa a linha em branco: quem não passa nesta prova cai na
/// StandardSymbolsPS embutida, que tem o conjunto certo.
const _symbolFamilies = <String>{
  'symbol',
  'standardsymbolsps',
  'standardsymbolsl',
};

/// Idem para `ZapfDingbats`. A clone da URW ("Dingbats", `d050000l`) tem o
/// mesmo conjunto — é a que o pacote embute — e Wingdings **não** tem, que é
/// por que não está aqui.
const _dingbatFamilies = <String>{
  'zapfdingbats',
  'dingbats',
  'itczapfdingbats',
};

/// Índice de arquivos de fonte do sistema, construído sob demanda.
///
/// Mantido por processo e por conjunto de diretórios: varrer `C:\Windows\Fonts`
/// custa centenas de `stat`, e o renderizador pede fonte uma vez por recurso
/// de cada página.
class _SystemFonts {
  static final Map<String, _SystemFonts> _instances = <String, _SystemFonts>{};

  final List<String> _directories;

  /// Caminho por nome de arquivo normalizado.
  Future<Map<String, String>>? _index;

  /// Bytes já resolvidos, por chave de requisição. Guarda também o `null`:
  /// procurar de novo o que não existe custa o mesmo que procurar.
  final Map<String, Uint8List?> _resolved = <String, Uint8List?>{};

  _SystemFonts._(this._directories);

  factory _SystemFonts.forDirectories(List<String>? directories) {
    final list =
        List<String>.unmodifiable(directories ?? systemFontDirectories());
    return _instances.putIfAbsent(
        list.join('\u0000'), () => _SystemFonts._(list));
  }

  Future<Uint8List?> resolve(PdfFontRequest request) async {
    final key = '${request.familyName}\u0000${request.flags}'
        '\u0000${request.composite}';
    if (_resolved.containsKey(key)) return _resolved[key];
    Uint8List? bytes;
    try {
      bytes = await _search(request);
    } on FileSystemException {
      // Catálogo ilegível: o renderizador volta a relatar o texto como pulado.
      bytes = null;
    }
    return _resolved[key] = bytes;
  }

  Future<Uint8List?> _search(PdfFontRequest request) async {
    final family = _strippedFamily(request);
    final kind = _classify(family, request);
    final index = await (_index ??= _buildIndex());

    for (final name in _candidates(family, kind, request)) {
      final path = index[name];
      if (path == null) continue;
      final Uint8List bytes;
      try {
        bytes = await File(path).readAsBytes();
      } on FileSystemException {
        continue;
      }
      final BLFontFace face;
      try {
        face = BLFontFace.parse(bytes);
      } on Object {
        // Formato que este pacote ainda não abre (uma `.ttc`, um Type1 de
        // sistema). O próximo candidato pode servir.
        continue;
      }
      if (!_accepts(kind, family, face)) continue;
      return bytes;
    }
    return null;
  }

  /// `/BaseFont` sem prefixo de subconjunto e sem sufixo de estilo,
  /// normalizado.
  static String _strippedFamily(PdfFontRequest request) {
    final family = request.familyName.replaceFirst(
      RegExp(
          r'[-,]?(BoldItalic|BoldOblique|Bold|Italic|Oblique|Regular|MT|PS)+$',
          caseSensitive: false),
      '',
    );
    return _normalize(family);
  }

  static _Kind _classify(String family, PdfFontRequest request) {
    if (family.startsWith('zapfdingbats') || family == 'dingbats') {
      return _Kind.dingbats;
    }
    if (family == 'symbol' || family.startsWith('symbolmt')) {
      return _Kind.symbol;
    }
    if (family.startsWith('courier') || family.startsWith('mono')) {
      return _Kind.mono;
    }
    if (family.startsWith('times') ||
        family.startsWith('georgia') ||
        family.startsWith('garamond') ||
        family.startsWith('book')) {
      return _Kind.serif;
    }
    if (family.startsWith('helvetica') ||
        family.startsWith('arial') ||
        family.startsWith('verdana') ||
        family.startsWith('tahoma') ||
        family.startsWith('calibri')) {
      return _Kind.sans;
    }
    // Uma fonte simbólica desconhecida não tem parecido: o conjunto de glifos
    // é dela. Só o arquivo com aquele nome serve.
    if (request.isSymbolic) return _Kind.symbolic;
    if (request.isFixedPitch) return _Kind.mono;
    return request.isSerif ? _Kind.serif : _Kind.sans;
  }

  /// Nomes de arquivo a tentar, na ordem.
  static List<String> _candidates(
    String family,
    _Kind kind,
    PdfFontRequest request,
  ) {
    final bold = request.isBold;
    final italic = request.isItalic;
    final names = <String>[
      // O próprio nome primeiro: se a fonte estiver instalada, ela não é um
      // substituto, é a fonte que o produtor pediu.
      _normalize(request.familyName),
      family,
      if (bold) '${family}bd',
      if (bold) '${family}bold',
      if (bold) '$family-bold',
      if (italic) '${family}i',
      if (italic) '${family}italic',
      if (italic) '$family-italic',
      if (kind != _Kind.symbolic)
        ..._tables[kind]!.forStyle(bold: bold, italic: italic),
    ];
    final seen = <String>{};
    return <String>[
      for (final name in names)
        if (seen.add(name)) name
    ];
  }

  /// Decide se [face] pode desenhar no lugar de [family].
  static bool _accepts(_Kind kind, String family, BLFontFace face) {
    final actual = _normalize(face.familyName);
    switch (kind) {
      case _Kind.symbol:
        return _symbolFamilies.contains(actual) && _hasSymbolCodes(face);
      case _Kind.dingbats:
        return _dingbatFamilies.contains(actual) && _hasSymbolCodes(face);
      case _Kind.symbolic:
        return actual == family;
      case _Kind.sans:
      case _Kind.serif:
      case _Kind.mono:
        return face.glyphCount > 1;
    }
  }

  /// Confere que a fonte responde à faixa simbólica, em vez de presumir.
  ///
  /// Uma fonte simbólica mapeia seus códigos pela `cmap` (3,0) em 0xF000 + c,
  /// e é assim que o renderizador vai procurá-los.
  static bool _hasSymbolCodes(BLFontFace face) {
    for (final code in const <int>[0x41, 0x61, 0x62, 0x63]) {
      if (face.mapCodePoint(0xF000 + code) == 0 &&
          face.mapCodePoint(code) == 0) {
        return false;
      }
    }
    return true;
  }

  Future<Map<String, String>> _buildIndex() async {
    final index = <String, String>{};
    for (final directory in _directories) {
      final folder = Directory(directory);
      if (!await folder.exists()) continue;
      try {
        await for (final entity
            in folder.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final path = entity.path.replaceAll('\\', '/');
          final dot = path.lastIndexOf('.');
          if (dot < 0) continue;
          final extension = path.substring(dot).toLowerCase();
          if (extension != '.ttf' &&
              extension != '.otf' &&
              extension != '.ttc') {
            continue;
          }
          final name =
              _normalize(path.substring(path.lastIndexOf('/') + 1, dot));
          // O primeiro diretório da lista tem precedência sobre os seguintes.
          index.putIfAbsent(name, () => entity.path);
        }
      } on FileSystemException {
        // Subdiretório sem permissão não pode esconder o resto do catálogo.
      }
    }
    return index;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_]'), '');
}
