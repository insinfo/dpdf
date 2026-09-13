/// The predefined simple-font encodings of ISO 32000-1:2008, Annex D.
///
/// Each table maps a one-byte character code to the glyph name assigned by
/// the standard; `null` marks a code the encoding leaves undefined. Glyph
/// names -- not Unicode values -- are the currency of 9.6.6, "Character
/// Encoding": a Type 1 or Type 3 program is keyed by them, `/Differences`
/// (Table 114) is written in them, and 9.6.6.4 routes TrueType lookups
/// through them as well.
///
/// Sources, all reproduced without transcription by hand:
///   * Table D.1 (Latin character set) supplies StandardEncoding,
///     MacRomanEncoding, WinAnsiEncoding and PDFDocEncoding, including the
///     duplicate assignments of its notes 3, 5 and 6.
///   * Table D.3 supplies MacExpertEncoding.
///   * The Symbol and ZapfDingbats built-in encodings (D.5 and D.6) are the
///     `C`/`N` pairs of the metrics shipped in `io/resources/afm`.
///   * Table 115 adds the sixteen Mac OS Roman assignments that 9.6.6.4
///     needs when a font offers only a (1,0) "cmap" subtable.
library;

/// Glyph-name tables for the encodings PDF defines by name.
abstract final class BaseEncodings {
  /// Adobe standard Latin encoding. Not a valid `/Encoding` name, but the
  /// default base encoding of 9.6.6.1 and the filler of 9.6.6.4.
  static const String standardEncoding = 'StandardEncoding';
  static const String winAnsiEncoding = 'WinAnsiEncoding';
  static const String macRomanEncoding = 'MacRomanEncoding';
  static const String macExpertEncoding = 'MacExpertEncoding';

  /// The text-string encoding of 7.9.2.2; never a font `/Encoding`.
  static const String pdfDocEncoding = 'PDFDocEncoding';
  static const String symbolEncoding = 'Symbol';
  static const String zapfDingbatsEncoding = 'ZapfDingbats';

  /// The Mac OS flavour of Table 115, used only to reach a (1,0) subtable.
  static const String macOsRomanEncoding = 'MacOSRoman';

  /// The names a font dictionary's `/Encoding` or `/BaseEncoding` may take.
  static const Set<String> predefinedNames = {
    winAnsiEncoding,
    macRomanEncoding,
    macExpertEncoding,
  };

  static List<String?> get standard => _table(standardEncoding, _standard);
  static List<String?> get winAnsi => _table(winAnsiEncoding, _winAnsi);
  static List<String?> get macRoman => _table(macRomanEncoding, _macRoman);
  static List<String?> get macExpert => _table(macExpertEncoding, _macExpert);
  static List<String?> get pdfDoc => _table(pdfDocEncoding, _pdfDoc);
  static List<String?> get symbol => _table(symbolEncoding, _symbol);
  static List<String?> get zapfDingbats =>
      _table(zapfDingbatsEncoding, _zapfDingbats);
  static List<String?> get macOsRoman =>
      _table(macOsRomanEncoding, _macOsRoman);

  /// The table for [name], or `null` when no encoding carries that name.
  /// Recognized spellings include the bare forms ("WinAnsi", "MacRoman")
  /// that appear in font descriptors and in this package's own resources.
  static List<String?>? byName(String? name) {
    final packed = _packed[_canonical(name)];
    return packed == null ? null : _table(_canonical(name)!, packed);
  }

  /// The canonical spelling of [name], or `null` when it names no encoding.
  static String? canonicalName(String? name) {
    final canonical = _canonical(name);
    return _packed.containsKey(canonical) ? canonical : null;
  }

  /// The Mac OS Roman code of [glyphName], per Table 115. Step three of the
  /// 9.6.6.4 lookup that ends in a (1,0) "cmap" subtable.
  static int? macOsRomanCode(String glyphName) => _macOsRomanCodes[glyphName];

  static String? _canonical(String? name) {
    if (name == null) return null;
    final folded = name.toLowerCase().replaceAll('encoding', '');
    return const {
      'standard': standardEncoding,
      'adobestandard': standardEncoding,
      'winansi': winAnsiEncoding,
      'windows-1252': winAnsiEncoding,
      'cp1252': winAnsiEncoding,
      'macroman': macRomanEncoding,
      'macexpert': macExpertEncoding,
      'pdfdoc': pdfDocEncoding,
      'pdf': pdfDocEncoding,
      'symbol': symbolEncoding,
      'zapfdingbats': zapfDingbatsEncoding,
      'macosroman': macOsRomanEncoding,
    }[folded];
  }

  static final Map<String, String> _packed = {
    standardEncoding: _standard,
    winAnsiEncoding: _winAnsi,
    macRomanEncoding: _macRoman,
    macExpertEncoding: _macExpert,
    pdfDocEncoding: _pdfDoc,
    symbolEncoding: _symbol,
    zapfDingbatsEncoding: _zapfDingbats,
    macOsRomanEncoding: _macOsRoman,
  };

  static final Map<String, List<String?>> _expanded = {};

  static List<String?> _table(String name, String packed) =>
      _expanded.putIfAbsent(name, () {
        final names = packed.split(' ');
        if (names.length != 256) {
          throw StateError('Encoding $name does not cover 256 codes.');
        }
        return List<String?>.unmodifiable(
            names.map((glyph) => glyph == '.' ? null : glyph));
      });

  /// The 258 glyph names of the standard Macintosh ordering.
  ///
  /// A "post" table of version 1.0 consists of nothing but this ordering,
  /// and one of version 2.0 indexes into it for every glyph whose name it
  /// does not spell out. 9.6.6.4 ends its TrueType lookup there: "the glyph
  /// name shall be looked up in the font program's post table (if one is
  /// present) and the associated glyph description shall be used".
  ///
  /// The ordering is not independent data. After three glyphs that no code
  /// reaches, it runs through Mac OS Roman in code order -- with the two
  /// names Apple spells differently, `nonbreakingspace` and the `currency`
  /// that Table 115 turns into a euro -- and ends with thirty-two glyphs
  /// that the encoding does not reach at all.
  static List<String> get macGlyphOrder => _macGlyphOrder ??= () {
        final order = <String>['.notdef', '.null', 'nonmarkingreturn'];
        for (var code = 0x20; code < 0x100; code++) {
          final name = macOsRoman[code];
          if (name == null) continue;
          order.add(switch (code) {
            0xca => 'nonbreakingspace',
            0xdb => 'currency',
            _ => name,
          });
        }
        order.addAll(const [
          'Lslash', 'lslash', 'Scaron', 'scaron', 'Zcaron', 'zcaron', //
          'brokenbar', 'Eth', 'eth', 'Yacute', 'yacute', 'Thorn', 'thorn',
          'minus', 'multiply', 'onesuperior', 'twosuperior', 'threesuperior',
          'onehalf', 'onequarter', 'threequarters', 'franc', 'Gbreve',
          'gbreve', 'Idotaccent', 'Scedilla', 'scedilla', 'Cacute', 'cacute',
          'Ccaron', 'ccaron', 'dcroat',
        ]);
        if (order.length != 258) {
          throw StateError('The Macintosh glyph ordering lost an entry.');
        }
        return List<String>.unmodifiable(order);
      }();

  static List<String>? _macGlyphOrder;

  /// The code a glyph keeps when an encoding assigns it more than once.
  ///
  /// Table D.1 defines three such duplicates and says which code is the real
  /// one: note 3 reserves only 0x95 for the bullet although WinAnsiEncoding
  /// shows a bullet for every otherwise unused code above 0x20, note 5 adds
  /// a soft hyphen at 0xAD, and note 6 adds a non-breaking space at 0xA0 in
  /// WinAnsiEncoding and at 0xCA in MacRomanEncoding. Encoding text has to
  /// pick one code per glyph, and these are the ones to pick.
  static const Map<String, Map<String, int>> canonicalCodes = {
    winAnsiEncoding: {'bullet': 0x95, 'space': 0x20, 'hyphen': 0x2d},
    macRomanEncoding: {'space': 0x20},
    macOsRomanEncoding: {'space': 0x20},
  };

  static final Map<String, int> _macOsRomanCodes = {
    for (var code = 255; code >= 0; code--)
      if (macOsRoman[code] != null) macOsRoman[code]!: code,
  };

  static const String _standard =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space exclam quotedbl numbersign dollar percent ampersand quoteright '
      'parenleft parenright asterisk plus comma hyphen period slash zero '
      'one two three four five six seven eight nine colon semicolon less '
      'equal greater question at A B C D E F G H I J K L M N O P Q R S T U '
      'V W X Y Z bracketleft backslash bracketright asciicircum underscore '
      'quoteleft a b c d e f g h i j k l m n o p q r s t u v w x y z '
      'braceleft bar braceright asciitilde . . . . . . . . . . . . . . . . '
      '. . . . . . . . . . . . . . . . . . exclamdown cent sterling '
      'fraction yen florin section currency quotesingle quotedblleft '
      'guillemotleft guilsinglleft guilsinglright fi fl . endash dagger '
      'daggerdbl periodcentered . paragraph bullet quotesinglbase '
      'quotedblbase quotedblright guillemotright ellipsis perthousand . '
      'questiondown . grave acute circumflex tilde macron breve dotaccent '
      'dieresis . ring cedilla . hungarumlaut ogonek caron emdash . . . . . '
      '. . . . . . . . . . . AE . ordfeminine . . . . Lslash Oslash OE '
      'ordmasculine . . . . . ae . . . dotlessi . . lslash oslash oe '
      'germandbls . . . .';

  static const String _macRoman =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space exclam quotedbl numbersign dollar percent ampersand '
      'quotesingle parenleft parenright asterisk plus comma hyphen period '
      'slash zero one two three four five six seven eight nine colon '
      'semicolon less equal greater question at A B C D E F G H I J K L M N '
      'O P Q R S T U V W X Y Z bracketleft backslash bracketright '
      'asciicircum underscore grave a b c d e f g h i j k l m n o p q r s t '
      'u v w x y z braceleft bar braceright asciitilde . Adieresis Aring '
      'Ccedilla Eacute Ntilde Odieresis Udieresis aacute agrave acircumflex '
      'adieresis atilde aring ccedilla eacute egrave ecircumflex edieresis '
      'iacute igrave icircumflex idieresis ntilde oacute ograve ocircumflex '
      'odieresis otilde uacute ugrave ucircumflex udieresis dagger degree '
      'cent sterling section bullet paragraph germandbls registered '
      'copyright trademark acute dieresis . AE Oslash . plusminus . . yen '
      'mu . . . . . ordfeminine ordmasculine . ae oslash questiondown '
      'exclamdown logicalnot . florin . . guillemotleft guillemotright '
      'ellipsis space Agrave Atilde Otilde OE oe endash emdash quotedblleft '
      'quotedblright quoteleft quoteright divide . ydieresis Ydieresis '
      'fraction currency guilsinglleft guilsinglright fi fl daggerdbl '
      'periodcentered quotesinglbase quotedblbase perthousand Acircumflex '
      'Ecircumflex Aacute Edieresis Egrave Iacute Icircumflex Idieresis '
      'Igrave Oacute Ocircumflex . Ograve Uacute Ucircumflex Ugrave '
      'dotlessi circumflex tilde macron breve dotaccent ring cedilla '
      'hungarumlaut ogonek caron';

  static const String _winAnsi =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space exclam quotedbl numbersign dollar percent ampersand '
      'quotesingle parenleft parenright asterisk plus comma hyphen period '
      'slash zero one two three four five six seven eight nine colon '
      'semicolon less equal greater question at A B C D E F G H I J K L M N '
      'O P Q R S T U V W X Y Z bracketleft backslash bracketright '
      'asciicircum underscore grave a b c d e f g h i j k l m n o p q r s t '
      'u v w x y z braceleft bar braceright asciitilde bullet Euro bullet '
      'quotesinglbase florin quotedblbase ellipsis dagger daggerdbl '
      'circumflex perthousand Scaron guilsinglleft OE bullet Zcaron bullet '
      'bullet quoteleft quoteright quotedblleft quotedblright bullet endash '
      'emdash tilde trademark scaron guilsinglright oe bullet zcaron '
      'Ydieresis space exclamdown cent sterling currency yen brokenbar '
      'section dieresis copyright ordfeminine guillemotleft logicalnot '
      'hyphen registered macron degree plusminus twosuperior threesuperior '
      'acute mu paragraph periodcentered cedilla onesuperior ordmasculine '
      'guillemotright onequarter onehalf threequarters questiondown Agrave '
      'Aacute Acircumflex Atilde Adieresis Aring AE Ccedilla Egrave Eacute '
      'Ecircumflex Edieresis Igrave Iacute Icircumflex Idieresis Eth Ntilde '
      'Ograve Oacute Ocircumflex Otilde Odieresis multiply Oslash Ugrave '
      'Uacute Ucircumflex Udieresis Yacute Thorn germandbls agrave aacute '
      'acircumflex atilde adieresis aring ae ccedilla egrave eacute '
      'ecircumflex edieresis igrave iacute icircumflex idieresis eth ntilde '
      'ograve oacute ocircumflex otilde odieresis divide oslash ugrave '
      'uacute ucircumflex udieresis yacute thorn ydieresis';

  static const String _pdfDoc =
      '. . . . . . . . . . . . . . . . . . . . . . . . breve caron '
      'circumflex dotaccent hungarumlaut ogonek ring tilde space exclam '
      'quotedbl numbersign dollar percent ampersand quotesingle parenleft '
      'parenright asterisk plus comma hyphen period slash zero one two '
      'three four five six seven eight nine colon semicolon less equal '
      'greater question at A B C D E F G H I J K L M N O P Q R S T U V W X '
      'Y Z bracketleft backslash bracketright asciicircum underscore grave '
      'a b c d e f g h i j k l m n o p q r s t u v w x y z braceleft bar '
      'braceright asciitilde . bullet dagger daggerdbl ellipsis emdash '
      'endash florin fraction guilsinglleft guilsinglright minus '
      'perthousand quotedblbase quotedblleft quotedblright quoteleft '
      'quoteright quotesinglbase trademark fi fl Lslash OE Scaron Ydieresis '
      'Zcaron dotlessi lslash oe scaron zcaron . Euro exclamdown cent '
      'sterling currency yen brokenbar section dieresis copyright '
      'ordfeminine guillemotleft logicalnot . registered macron degree '
      'plusminus twosuperior threesuperior acute mu paragraph '
      'periodcentered cedilla onesuperior ordmasculine guillemotright '
      'onequarter onehalf threequarters questiondown Agrave Aacute '
      'Acircumflex Atilde Adieresis Aring AE Ccedilla Egrave Eacute '
      'Ecircumflex Edieresis Igrave Iacute Icircumflex Idieresis Eth Ntilde '
      'Ograve Oacute Ocircumflex Otilde Odieresis multiply Oslash Ugrave '
      'Uacute Ucircumflex Udieresis Yacute Thorn germandbls agrave aacute '
      'acircumflex atilde adieresis aring ae ccedilla egrave eacute '
      'ecircumflex edieresis igrave iacute icircumflex idieresis eth ntilde '
      'ograve oacute ocircumflex otilde odieresis divide oslash ugrave '
      'uacute ucircumflex udieresis yacute thorn ydieresis';

  static const String _macExpert =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space exclamsmall Hungarumlautsmall centoldstyle dollaroldstyle '
      'dollarsuperior ampersandsmall Acutesmall parenleftsuperior '
      'parenrightsuperior twodotenleader onedotenleader comma hyphen period '
      'fraction zerooldstyle oneoldstyle twooldstyle threeoldstyle '
      'fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle eightoldstyle '
      'nineoldstyle colon semicolon . threequartersemdash . questionsmall . '
      '. . . Ethsmall . . onequarter onehalf threequarters oneeighth '
      'threeeighths fiveeighths seveneighths onethird twothirds . . . . . . '
      'ff fi fl ffi ffl parenleftinferior . parenrightinferior '
      'Circumflexsmall hypheninferior Gravesmall Asmall Bsmall Csmall '
      'Dsmall Esmall Fsmall Gsmall Hsmall Ismall Jsmall Ksmall Lsmall '
      'Msmall Nsmall Osmall Psmall Qsmall Rsmall Ssmall Tsmall Usmall '
      'Vsmall Wsmall Xsmall Ysmall Zsmall colonmonetary onefitted rupiah '
      'Tildesmall . . asuperior centsuperior . . . . Aacutesmall '
      'Agravesmall Acircumflexsmall Adieresissmall Atildesmall Aringsmall '
      'Ccedillasmall Eacutesmall Egravesmall Ecircumflexsmall '
      'Edieresissmall Iacutesmall Igravesmall Icircumflexsmall '
      'Idieresissmall Ntildesmall Oacutesmall Ogravesmall Ocircumflexsmall '
      'Odieresissmall Otildesmall Uacutesmall Ugravesmall Ucircumflexsmall '
      'Udieresissmall . eightsuperior fourinferior threeinferior '
      'sixinferior eightinferior seveninferior Scaronsmall . centinferior '
      'twoinferior . Dieresissmall . Caronsmall osuperior fiveinferior . '
      'commainferior periodinferior Yacutesmall . dollarinferior . . '
      'Thornsmall . nineinferior zeroinferior Zcaronsmall AEsmall '
      'Oslashsmall questiondownsmall oneinferior Lslashsmall . . . . . . '
      'Cedillasmall . . . . . OEsmall figuredash hyphensuperior . . . . '
      'exclamdownsmall . Ydieresissmall . onesuperior twosuperior '
      'threesuperior foursuperior fivesuperior sixsuperior sevensuperior '
      'ninesuperior zerosuperior . esuperior rsuperior tsuperior . . '
      'isuperior ssuperior dsuperior . . . . . lsuperior Ogoneksmall '
      'Brevesmall Macronsmall bsuperior nsuperior msuperior commasuperior '
      'periodsuperior Dotaccentsmall Ringsmall . . . .';

  static const String _symbol =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space exclam universal numbersign existential percent ampersand '
      'suchthat parenleft parenright asteriskmath plus comma minus period '
      'slash zero one two three four five six seven eight nine colon '
      'semicolon less equal greater question congruent Alpha Beta Chi Delta '
      'Epsilon Phi Gamma Eta Iota theta1 Kappa Lambda Mu Nu Omicron Pi '
      'Theta Rho Sigma Tau Upsilon sigma1 Omega Xi Psi Zeta bracketleft '
      'therefore bracketright perpendicular underscore radicalex alpha beta '
      'chi delta epsilon phi gamma eta iota phi1 kappa lambda mu nu omicron '
      'pi theta rho sigma tau upsilon omega1 omega xi psi zeta braceleft '
      'bar braceright similar . . . . . . . . . . . . . . . . . . . . . . . '
      '. . . . . . . . . . Euro Upsilon1 minute lessequal fraction infinity '
      'florin club diamond heart spade arrowboth arrowleft arrowup '
      'arrowright arrowdown degree plusminus second greaterequal multiply '
      'proportional partialdiff bullet divide notequal equivalence '
      'approxequal ellipsis arrowvertex arrowhorizex carriagereturn aleph '
      'Ifraktur Rfraktur weierstrass circlemultiply circleplus emptyset '
      'intersection union propersuperset reflexsuperset notsubset '
      'propersubset reflexsubset element notelement angle gradient '
      'registerserif copyrightserif trademarkserif product radical dotmath '
      'logicalnot logicaland logicalor arrowdblboth arrowdblleft arrowdblup '
      'arrowdblright arrowdbldown lozenge angleleft registersans '
      'copyrightsans trademarksans summation parenlefttp parenleftex '
      'parenleftbt bracketlefttp bracketleftex bracketleftbt bracelefttp '
      'braceleftmid braceleftbt braceex . angleright integral integraltp '
      'integralex integralbt parenrighttp parenrightex parenrightbt '
      'bracketrighttp bracketrightex bracketrightbt bracerighttp '
      'bracerightmid bracerightbt .';

  static const String _zapfDingbats =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space a1 a2 a202 a3 a4 a5 a119 a118 a117 a11 a12 a13 a14 a15 a16 '
      'a105 a17 a18 a19 a20 a21 a22 a23 a24 a25 a26 a27 a28 a6 a7 a8 a9 a10 '
      'a29 a30 a31 a32 a33 a34 a35 a36 a37 a38 a39 a40 a41 a42 a43 a44 a45 '
      'a46 a47 a48 a49 a50 a51 a52 a53 a54 a55 a56 a57 a58 a59 a60 a61 a62 '
      'a63 a64 a65 a66 a67 a68 a69 a70 a71 a72 a73 a74 a203 a75 a204 a76 '
      'a77 a78 a79 a81 a82 a83 a84 a97 a98 a99 a100 . a89 a90 a93 a94 a91 '
      'a92 a205 a85 a206 a86 a87 a88 a95 a96 . . . . . . . . . . . . . . . '
      '. . . . a101 a102 a103 a104 a106 a107 a108 a112 a111 a110 a109 a120 '
      'a121 a122 a123 a124 a125 a126 a127 a128 a129 a130 a131 a132 a133 '
      'a134 a135 a136 a137 a138 a139 a140 a141 a142 a143 a144 a145 a146 '
      'a147 a148 a149 a150 a151 a152 a153 a154 a155 a156 a157 a158 a159 '
      'a160 a161 a163 a164 a196 a165 a192 a166 a167 a168 a169 a170 a171 '
      'a172 a173 a162 a174 a175 a176 a177 a178 a179 a193 a180 a199 a181 '
      'a200 a182 . a201 a183 a184 a197 a185 a194 a198 a186 a195 a187 a188 '
      'a189 a190 a191 .';

  static const String _macOsRoman =
      '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . '
      'space exclam quotedbl numbersign dollar percent ampersand '
      'quotesingle parenleft parenright asterisk plus comma hyphen period '
      'slash zero one two three four five six seven eight nine colon '
      'semicolon less equal greater question at A B C D E F G H I J K L M N '
      'O P Q R S T U V W X Y Z bracketleft backslash bracketright '
      'asciicircum underscore grave a b c d e f g h i j k l m n o p q r s t '
      'u v w x y z braceleft bar braceright asciitilde . Adieresis Aring '
      'Ccedilla Eacute Ntilde Odieresis Udieresis aacute agrave acircumflex '
      'adieresis atilde aring ccedilla eacute egrave ecircumflex edieresis '
      'iacute igrave icircumflex idieresis ntilde oacute ograve ocircumflex '
      'odieresis otilde uacute ugrave ucircumflex udieresis dagger degree '
      'cent sterling section bullet paragraph germandbls registered '
      'copyright trademark acute dieresis notequal AE Oslash infinity '
      'plusminus lessequal greaterequal yen mu partialdiff summation '
      'product pi integral ordfeminine ordmasculine Omega ae oslash '
      'questiondown exclamdown logicalnot radical florin approxequal Delta '
      'guillemotleft guillemotright ellipsis space Agrave Atilde Otilde OE '
      'oe endash emdash quotedblleft quotedblright quoteleft quoteright '
      'divide lozenge ydieresis Ydieresis fraction Euro guilsinglleft '
      'guilsinglright fi fl daggerdbl periodcentered quotesinglbase '
      'quotedblbase perthousand Acircumflex Ecircumflex Aacute Edieresis '
      'Egrave Iacute Icircumflex Idieresis Igrave Oacute Ocircumflex apple '
      'Ograve Uacute Ucircumflex Ugrave dotlessi circumflex tilde macron '
      'breve dotaccent ring cedilla hungarumlaut ogonek caron';
}
