import 'dart:typed_data';

import 'pdf_object.dart';

/// Represents a PDF name object.
///
/// Names are used as keys in dictionaries and to identify operators.
/// They are written with a leading slash: /Name
class PdfName extends PdfObject {
  /// Cache for interned names.
  static final Map<String, PdfName> _staticNames = {};

  /// The name value (without leading slash).
  String _value;

  /// Creates a PdfName from a string.
  PdfName(String name) : _value = name;

  /// Creates a PdfName from bytes.
  factory PdfName.fromBytes(Uint8List bytes) {
    final value = _decodeName(bytes);
    return PdfName(value);
  }

  /// Gets or creates an interned (cached) name.
  factory PdfName.intern(String name) {
    return _staticNames.putIfAbsent(name, () => PdfName(name));
  }

  @override
  int getObjectType() => PdfObjectType.name;

  @override
  PdfObject clone() {
    return PdfName(_value);
  }

  @override
  PdfObject newInstance() {
    return PdfName('');
  }

  /// Gets the name value.
  String getValue() => _value;

  /// Generates bytes for PDF output.
  Uint8List generateContent() {
    return _encodeName(_value);
  }

  /// Decodes name bytes, handling # escape sequences.
  static String _decodeName(Uint8List bytes) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      var ch = bytes[i++];
      if (ch == 0x23) {
        // '#'
        if (i + 2 <= bytes.length) {
          final hex1 = _hexValue(bytes[i++]);
          final hex2 = _hexValue(bytes[i++]);
          if (hex1 >= 0 && hex2 >= 0) {
            ch = (hex1 << 4) | hex2;
          }
        }
      }
      buffer.writeCharCode(ch);
    }
    return buffer.toString();
  }

  /// Encodes a name string to bytes, escaping special characters.
  static Uint8List _encodeName(String name) {
    final bytes = <int>[];
    for (final char in name.codeUnits) {
      if (_needsEscape(char)) {
        bytes.add(0x23); // '#'
        bytes.add(_hexDigit((char >> 4) & 0x0F));
        bytes.add(_hexDigit(char & 0x0F));
      } else {
        bytes.add(char);
      }
    }
    return Uint8List.fromList(bytes);
  }

  /// Checks if a character needs escaping in a name.
  static bool _needsEscape(int ch) {
    // Escape if outside printable ASCII or is delimiter/whitespace
    if (ch < 0x21 || ch > 0x7E) return true;
    // Escape delimiters
    switch (ch) {
      case 0x23: // #
      case 0x25: // %
      case 0x28: // (
      case 0x29: // )
      case 0x2F: // /
      case 0x3C: // <
      case 0x3E: // >
      case 0x5B: // [
      case 0x5D: // ]
      case 0x7B: // {
      case 0x7D: // }
        return true;
      default:
        return false;
    }
  }

  /// Converts hex character to value.
  static int _hexValue(int ch) {
    if (ch >= 0x30 && ch <= 0x39) return ch - 0x30; // '0'-'9'
    if (ch >= 0x41 && ch <= 0x46) return ch - 0x41 + 10; // 'A'-'F'
    if (ch >= 0x61 && ch <= 0x66) return ch - 0x61 + 10; // 'a'-'f'
    return -1;
  }

  /// Converts value to hex digit.
  static int _hexDigit(int value) {
    if (value < 10) return 0x30 + value;
    return 0x61 + value - 10;
  }

  @override
  String toString() {
    return '/$_value';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfName) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;

  // ========================================
  // Common PDF name constants
  // ========================================

  // Basic document structure
  static final PdfName catalog = PdfName.intern('Catalog');
  static final PdfName pages = PdfName.intern('Pages');
  static final PdfName page = PdfName.intern('Page');
  static final PdfName type = PdfName.intern('Type');
  static final PdfName parent = PdfName.intern('Parent');
  static final PdfName kids = PdfName.intern('Kids');
  static final PdfName count = PdfName.intern('Count');
  static final PdfName resources = PdfName.intern('Resources');
  static final PdfName contents = PdfName.intern('Contents');
  static final PdfName mediaBox = PdfName.intern('MediaBox');
  static final PdfName cropBox = PdfName.intern('CropBox');
  static final PdfName bleedBox = PdfName.intern('BleedBox');
  static final PdfName trimBox = PdfName.intern('TrimBox');
  static final PdfName artBox = PdfName.intern('ArtBox');
  static final PdfName rotate = PdfName.intern('Rotate');

  // Font related
  static final PdfName font = PdfName.intern('Font');
  static final PdfName baseFont = PdfName.intern('BaseFont');
  static final PdfName subtype = PdfName.intern('Subtype');
  static final PdfName encoding = PdfName.intern('Encoding');
  static final PdfName type0 = PdfName.intern('Type0');
  static final PdfName type1 = PdfName.intern('Type1');
  static final PdfName trueType = PdfName.intern('TrueType');
  static final PdfName cidFontType0 = PdfName.intern('CIDFontType0');
  static final PdfName cidFontType2 = PdfName.intern('CIDFontType2');
  static final PdfName descendantFonts = PdfName.intern('DescendantFonts');
  static final PdfName toUnicode = PdfName.intern('ToUnicode');
  static final PdfName fontDescriptor = PdfName.intern('FontDescriptor');
  static final PdfName fontFile = PdfName.intern('FontFile');
  static final PdfName fontFile2 = PdfName.intern('FontFile2');
  static final PdfName fontFile3 = PdfName.intern('FontFile3');
  static final PdfName fontName = PdfName.intern('FontName');
  static final PdfName flags = PdfName.intern('Flags');
  static final PdfName fontBBox = PdfName.intern('FontBBox');
  static final PdfName italicAngle = PdfName.intern('ItalicAngle');
  static final PdfName ascent = PdfName.intern('Ascent');
  static final PdfName descent = PdfName.intern('Descent');
  static final PdfName capHeight = PdfName.intern('CapHeight');
  static final PdfName stemV = PdfName.intern('StemV');
  static final PdfName widths = PdfName.intern('Widths');
  static final PdfName firstChar = PdfName.intern('FirstChar');
  static final PdfName lastChar = PdfName.intern('LastChar');

  // Image/XObject related
  static final PdfName xObject = PdfName.intern('XObject');
  static final PdfName image = PdfName.intern('Image');
  static final PdfName form = PdfName.intern('Form');
  static final PdfName width = PdfName.intern('Width');
  static final PdfName height = PdfName.intern('Height');
  static final PdfName bitsPerComponent = PdfName.intern('BitsPerComponent');
  static final PdfName colorSpace = PdfName.intern('ColorSpace');
  static final PdfName interpolate = PdfName.intern('Interpolate');
  static final PdfName imageMask = PdfName.intern('ImageMask');
  static final PdfName mask = PdfName.intern('Mask');
  static final PdfName sMask = PdfName.intern('SMask');
  static final PdfName decode = PdfName.intern('Decode');
  static final PdfName decodeParms = PdfName.intern('DecodeParms');

  // Color spaces
  static final PdfName deviceGray = PdfName.intern('DeviceGray');
  static final PdfName deviceRgb = PdfName.intern('DeviceRGB');
  static final PdfName deviceCmyk = PdfName.intern('DeviceCMYK');
  static final PdfName indexed = PdfName.intern('Indexed');
  static final PdfName iccBased = PdfName.intern('ICCBased');
  static final PdfName pattern = PdfName.intern('Pattern');
  static final PdfName separation = PdfName.intern('Separation');
  static final PdfName deviceN = PdfName.intern('DeviceN');
  static final PdfName calGray = PdfName.intern('CalGray');
  static final PdfName calRgb = PdfName.intern('CalRGB');
  static final PdfName lab = PdfName.intern('Lab');

  // Stream/Filter related
  static final PdfName length = PdfName.intern('Length');
  static final PdfName filter = PdfName.intern('Filter');
  static final PdfName flateDecodeFilter = PdfName.intern('FlateDecode');
  static final PdfName dctDecodeFilter = PdfName.intern('DCTDecode');
  static final PdfName ascii85DecodeFilter = PdfName.intern('ASCII85Decode');
  static final PdfName asciiHexDecodeFilter = PdfName.intern('ASCIIHexDecode');
  static final PdfName lzwDecodeFilter = PdfName.intern('LZWDecode');
  static final PdfName runLengthDecodeFilter =
      PdfName.intern('RunLengthDecode');
  static final PdfName ccittFaxDecodeFilter = PdfName.intern('CCITTFaxDecode');
  static final PdfName jpxDecodeFilter = PdfName.intern('JPXDecode');
  static final PdfName jbig2DecodeFilter = PdfName.intern('JBIG2Decode');
  static final PdfName crypt = PdfName.intern('Crypt');

  // Graphics state
  static final PdfName extGState = PdfName.intern('ExtGState');
  static final PdfName ca = PdfName.intern('ca');
  static final PdfName caUppercase = PdfName.intern('CA');
  static final PdfName bm = PdfName.intern('BM');
  static final PdfName smaskG = PdfName.intern('SMask');
  static final PdfName ais = PdfName.intern('AIS');
  static final PdfName lw = PdfName.intern('LW');
  static final PdfName lc = PdfName.intern('LC');
  static final PdfName lj = PdfName.intern('LJ');
  static final PdfName ml = PdfName.intern('ML');
  static final PdfName d = PdfName.intern('D');
  static final PdfName ri = PdfName.intern('RI');
  static final PdfName op = PdfName.intern('op');
  static final PdfName opUppercase = PdfName.intern('OP');
  static final PdfName opm = PdfName.intern('OPM');
  static final PdfName fontG = PdfName.intern('Font');
  static final PdfName bg = PdfName.intern('BG');
  static final PdfName bg2 = PdfName.intern('BG2');
  static final PdfName ucr = PdfName.intern('UCR');
  static final PdfName ucr2 = PdfName.intern('UCR2');
  static final PdfName tr = PdfName.intern('TR');
  static final PdfName tr2 = PdfName.intern('TR2');
  static final PdfName ht = PdfName.intern('HT');
  static final PdfName fl = PdfName.intern('FL');
  static final PdfName sm = PdfName.intern('SM');
  static final PdfName sa = PdfName.intern('SA');
  static final PdfName tk = PdfName.intern('TK');

  // Annotations
  static final PdfName annot = PdfName.intern('Annot');
  static final PdfName annots = PdfName.intern('Annots');
  static final PdfName rect = PdfName.intern('Rect');
  static final PdfName border = PdfName.intern('Border');
  static final PdfName c = PdfName.intern('C');
  static final PdfName a = PdfName.intern('A');
  static final PdfName dest = PdfName.intern('Dest');
  static final PdfName h = PdfName.intern('H');
  static final PdfName p = PdfName.intern('P');
  static final PdfName da = PdfName.intern('DA');
  static final PdfName q = PdfName.intern('Q');
  static final PdfName ap = PdfName.intern('AP');
  static final PdfName n = PdfName.intern('N');
  static final PdfName r = PdfName.intern('R');
  static final PdfName dAnnot = PdfName.intern('D');
  static final PdfName f = PdfName.intern('F');
  static final PdfName bs = PdfName.intern('BS');
  static final PdfName be = PdfName.intern('BE');
  static final PdfName t = PdfName.intern('T');
  static final PdfName popup = PdfName.intern('Popup');
  static final PdfName m = PdfName.intern('M');
  static final PdfName v = PdfName.intern('V');
  static final PdfName mk = PdfName.intern('MK');

  // Actions
  static final PdfName action = PdfName.intern('Action');
  static final PdfName s = PdfName.intern('S');
  static final PdfName uri = PdfName.intern('URI');
  static final PdfName goTo = PdfName.intern('GoTo');
  static final PdfName goToR = PdfName.intern('GoToR');
  static final PdfName goToE = PdfName.intern('GoToE');
  static final PdfName launch = PdfName.intern('Launch');
  static final PdfName named = PdfName.intern('Named');
  static final PdfName javaScript = PdfName.intern('JavaScript');
  static final PdfName js = PdfName.intern('JS');
  static final PdfName next = PdfName.intern('Next');

  // Document info
  static final PdfName info = PdfName.intern('Info');
  static final PdfName title = PdfName.intern('Title');
  static final PdfName author = PdfName.intern('Author');
  static final PdfName subject = PdfName.intern('Subject');
  static final PdfName keywords = PdfName.intern('Keywords');
  static final PdfName creator = PdfName.intern('Creator');
  static final PdfName producer = PdfName.intern('Producer');
  static final PdfName creationDate = PdfName.intern('CreationDate');
  static final PdfName modDate = PdfName.intern('ModDate');
  static final PdfName trapped = PdfName.intern('Trapped');

  // Metadata
  static final PdfName metadata = PdfName.intern('Metadata');
  static final PdfName xml = PdfName.intern('XML');

  // Outlines
  static final PdfName outlines = PdfName.intern('Outlines');
  static final PdfName outline = PdfName.intern('Outline');
  static final PdfName first = PdfName.intern('First');
  static final PdfName last = PdfName.intern('Last');
  static final PdfName prev = PdfName.intern('Prev');
  static final PdfName nextO = PdfName.intern('Next');

  // Objects
  static final PdfName objStm = PdfName.intern('ObjStm');
  static final PdfName xRef = PdfName.intern('XRef');

  // Miscellaneous
  static final PdfName size = PdfName.intern('Size');
  static final PdfName root = PdfName.intern('Root');
  static final PdfName id = PdfName.intern('ID');
  static final PdfName encrypt = PdfName.intern('Encrypt');
  static final PdfName w = PdfName.intern('W');
  static final PdfName index = PdfName.intern('Index');
  static final PdfName bbox = PdfName.intern('BBox');
  static final PdfName matrix = PdfName.intern('Matrix');
  static final PdfName formType = PdfName.intern('FormType');
  static final PdfName group = PdfName.intern('Group');
  static final PdfName transparency = PdfName.intern('Transparency');
  static final PdfName cs = PdfName.intern('CS');
  static final PdfName i = PdfName.intern('I');
  static final PdfName k = PdfName.intern('K');
  static final PdfName g = PdfName.intern('G');

  // Viewer preferences
  static final PdfName viewerPreferences = PdfName.intern('ViewerPreferences');
  static final PdfName pageLayout = PdfName.intern('PageLayout');
  static final PdfName pageMode = PdfName.intern('PageMode');
  static final PdfName openAction = PdfName.intern('OpenAction');

  // AcroForm
  static final PdfName acroForm = PdfName.intern('AcroForm');
  static final PdfName fields = PdfName.intern('Fields');
  static final PdfName needAppearances = PdfName.intern('NeedAppearances');
  static final PdfName sigFlags = PdfName.intern('SigFlags');
  static final PdfName co = PdfName.intern('CO');
  static final PdfName dr = PdfName.intern('DR');
  static final PdfName ft = PdfName.intern('FT');
  static final PdfName tx = PdfName.intern('Tx');
  static final PdfName btn = PdfName.intern('Btn');
  static final PdfName ch = PdfName.intern('Ch');
  static final PdfName sig = PdfName.intern('Sig');
  static final PdfName ff = PdfName.intern('Ff');
  static final PdfName dv = PdfName.intern('DV');
  static final PdfName opt = PdfName.intern('Opt');
  static final PdfName ti = PdfName.intern('TI');
  static final PdfName iName = PdfName.intern('I');
  static final PdfName tu = PdfName.intern('TU');
  static final PdfName tm = PdfName.intern('TM');
  static final PdfName maxLen = PdfName.intern('MaxLen');
  static final PdfName properties = PdfName.intern('Properties');
  static final PdfName shading = PdfName.intern('Shading');
  static final PdfName relativeColorimetric =
      PdfName.intern('RelativeColorimetric');
  static final PdfName absoluteColorimetric =
      PdfName.intern('AbsoluteColorimetric');
  static final PdfName perceptual = PdfName.intern('Perceptual');
  static final PdfName saturation = PdfName.intern('Saturation');
  static final PdfName normal = PdfName.intern('Normal');
  static final PdfName none = PdfName.intern('None');
}
