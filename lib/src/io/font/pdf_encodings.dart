import 'dart:convert';
import 'dart:typed_data';

abstract class ExtraEncoding {
  Uint8List charToByte(String text, String encoding);
  Uint8List charToByteChar(int char1, String encoding);
  String? byteToChar(Uint8List b, String encoding);
}

class PdfEncodings {
  static const String IDENTITY_H = "Identity-H";
  static const String IDENTITY_V = "Identity-V";
  static const String CP1250 = "Windows-1250";
  static const String CP1252 = "Windows-1252";
  static const String CP1253 = "Windows-1253";
  static const String CP1257 = "Windows-1257";
  static const String WINANSI = "Windows-1252";
  static const String MACROMAN = "MacRoman";
  static const String SYMBOL = "Symbol";
  static const String ZAPFDINGBATS = "ZapfDingbats";
  static const String UNICODE_BIG = "UnicodeBig";
  static const String UNICODE_BIG_UNMARKED = "UnicodeBigUnmarked";
  static const String PDF_DOC_ENCODING = "PDF";
  static const String UTF8 = "UTF-8";

  static const String EMPTY_STRING = "";

  // Character assignments from ISO 32000-1:2008, Annex D, Table D.2.
  // Undefined entries (including controls marked U) decode as U+FFFD.
  static final List<int> _documentCharacters = _buildDocumentCharacters();
  static final Map<int, int> _documentBytes = {
    for (var byte = 0; byte < 256; byte++)
      if (_documentCharacters[byte] != 0xfffd) _documentCharacters[byte]: byte,
  };

  static List<int> _buildDocumentCharacters() {
    final characters = List<int>.filled(256, 0xfffd);
    for (final byte in [9, 10, 13]) {
      characters[byte] = byte;
    }
    for (var byte = 0x20; byte <= 0xff; byte++) {
      if (byte < 0x7f || (byte > 0xa0 && byte != 0xad)) {
        characters[byte] = byte;
      }
    }
    characters.setRange(0x18, 0x20, const [
      0x02d8,
      0x02c7,
      0x02c6,
      0x02d9,
      0x02dd,
      0x02db,
      0x02da,
      0x02dc,
    ]);
    characters.setRange(0x80, 0x9f, const [
      0x2022,
      0x2020,
      0x2021,
      0x2026,
      0x2014,
      0x2013,
      0x0192,
      0x2044,
      0x2039,
      0x203a,
      0x2212,
      0x2030,
      0x201e,
      0x201c,
      0x201d,
      0x2018,
      0x2019,
      0x201a,
      0x2122,
      0xfb01,
      0xfb02,
      0x0141,
      0x0152,
      0x0160,
      0x0178,
      0x017d,
      0x0131,
      0x0142,
      0x0153,
      0x0161,
      0x017e,
    ]);
    characters[0xa0] = 0x20ac;
    return List<int>.unmodifiable(characters);
  }

  static final List<int> winansiByteToChar = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    109,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    120,
    121,
    122,
    123,
    124,
    125,
    126,
    127,
    8364,
    65533,
    8218,
    402,
    8222,
    8230,
    8224,
    8225,
    710,
    8240,
    352,
    8249,
    338,
    65533,
    381,
    65533,
    65533,
    8216,
    8217,
    8220,
    8221,
    8226,
    8211,
    8212,
    732,
    8482,
    353,
    8250,
    339,
    65533,
    382,
    376,
    160,
    161,
    162,
    163,
    164,
    165,
    166,
    167,
    168,
    169,
    170,
    171,
    172,
    173,
    174,
    175,
    176,
    177,
    178,
    179,
    180,
    181,
    182,
    183,
    184,
    185,
    186,
    187,
    188,
    189,
    190,
    191,
    192,
    193,
    194,
    195,
    196,
    197,
    198,
    199,
    200,
    201,
    202,
    203,
    204,
    205,
    206,
    207,
    208,
    209,
    210,
    211,
    212,
    213,
    214,
    215,
    216,
    217,
    218,
    219,
    220,
    221,
    222,
    223,
    224,
    225,
    226,
    227,
    228,
    229,
    230,
    231,
    232,
    233,
    234,
    235,
    236,
    237,
    238,
    239,
    240,
    241,
    242,
    243,
    244,
    245,
    246,
    247,
    248,
    249,
    250,
    251,
    252,
    253,
    254,
    255
  ];

  static final List<int> standardEncoding = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    8217,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
    8216,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    109,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    120,
    121,
    122,
    123,
    124,
    125,
    126,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    161,
    162,
    163,
    8260,
    165,
    402,
    167,
    164,
    39,
    8220,
    171,
    8249,
    8250,
    64257,
    64258,
    0,
    8211,
    8224,
    8225,
    183,
    0,
    182,
    8226,
    8218,
    8222,
    8221,
    187,
    8230,
    8240,
    0,
    191,
    0,
    96,
    180,
    710,
    732,
    175,
    728,
    729,
    168,
    0,
    730,
    184,
    0,
    733,
    731,
    711,
    8212,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    198,
    0,
    170,
    0,
    0,
    0,
    0,
    321,
    216,
    338,
    186,
    0,
    0,
    0,
    0,
    0,
    230,
    0,
    0,
    0,
    305,
    0,
    0,
    322,
    248,
    339,
    223,
    0,
    0,
    0,
    0
  ];

  static final Map<int, int> winansi = {};
  static final Map<String, ExtraEncoding> extraEncodings = {};

  static void init() {
    if (winansi.isNotEmpty) return;
    for (int k = 128; k < 161; ++k) {
      int c = winansiByteToChar[k];
      if (c != 65533) {
        winansi[c] = k;
      }
    }
  }

  static Uint8List convertToBytes(String text, String? encoding) {
    if (encoding == null || encoding.isEmpty) {
      return Uint8List.fromList(text.codeUnits);
    }
    init();

    var normalizedEncoding = encoding.toLowerCase();
    if (normalizedEncoding == 'pdf') {
      final result = BytesBuilder(copy: false);
      for (final character in text.runes) {
        final byte = _documentBytes[character];
        if (byte == null) {
          throw FormatException(
            'PDFDocEncoding cannot represent U+${character.toRadixString(16).toUpperCase()}.',
          );
        }
        result.addByte(byte);
      }
      return result.takeBytes();
    }
    var extra = extraEncodings[normalizedEncoding];
    if (extra != null) {
      return extra.charToByte(text, encoding);
    }

    if (encoding == WINANSI) {
      List<int> codes = text.codeUnits;
      Uint8List b = Uint8List(codes.length);
      for (int i = 0; i < codes.length; i++) {
        int ch = codes[i];
        if (ch < 128 || (ch > 160 && ch <= 255)) {
          b[i] = ch;
        } else {
          b[i] = winansi[ch] ?? 0;
        }
      }
      return b;
    }

    if (encoding == UNICODE_BIG || encoding == UNICODE_BIG_UNMARKED) {
      bool unmarked = (encoding == UNICODE_BIG_UNMARKED);
      int len = text.length * 2 + (unmarked ? 0 : 2);
      Uint8List b = Uint8List(len);
      int p = 0;
      if (!unmarked) {
        b[p++] = 0xFE;
        b[p++] = 0xFF;
      }
      for (int i = 0; i < text.length; i++) {
        int c = text.codeUnitAt(i);
        b[p++] = (c >> 8) & 0xFF;
        b[p++] = c & 0xFF;
      }
      return b;
    }

    if (normalizedEncoding == "utf-8") {
      return Uint8List.fromList(utf8.encode(text));
    }

    // Fallback
    try {
      return Uint8List.fromList(latin1.encode(text));
    } catch (e) {
      return Uint8List.fromList(text.codeUnits.map((e) => e & 0xFF).toList());
    }
  }

  static String convertToString(Uint8List bytes, String? encoding) {
    if (encoding?.toLowerCase() == 'pdf') {
      return String.fromCharCodes(
          bytes.map((byte) => _documentCharacters[byte]));
    }
    if (encoding == null || encoding.isEmpty) {
      return String.fromCharCodes(bytes);
    }
    if (encoding == WINANSI) {
      StringBuffer sb = StringBuffer();
      for (int b in bytes) {
        sb.writeCharCode(winansiByteToChar[b & 0xFF]);
      }
      return sb.toString();
    }
    if (encoding == UNICODE_BIG || encoding == UNICODE_BIG_UNMARKED) {
      int start = 0;
      if (encoding == UNICODE_BIG &&
          bytes.length >= 2 &&
          bytes[0] == 0xFE &&
          bytes[1] == 0xFF) {
        start = 2;
      }
      StringBuffer sb = StringBuffer();
      for (int i = start; i < bytes.length - 1; i += 2) {
        sb.writeCharCode((bytes[i] << 8) + bytes[i + 1]);
      }
      return sb.toString();
    }
    if (encoding.toLowerCase() == "utf-8") {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return String.fromCharCodes(bytes);
  }
}
