import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';

/// Represents a PDF name object.
///
/// Names are used as keys in dictionaries and to identify operators.
/// They are written with a leading slash: /Name
class PdfName extends PdfPrimitiveObject {
  /// Cache for interned names.
  static final Map<String, PdfName> _staticNames = {};

  /// The name value (without leading slash).
  final String _value;

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

  @override
  void generateContent() {
    setContent(_encodeName(_value));
  }

  static String _decodeName(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 35 && i + 2 < bytes.length) {
        // #
        final hex = String.fromCharCodes([bytes[i + 1], bytes[i + 2]]);
        buffer.writeCharCode(int.parse(hex, radix: 16));
        i += 2;
      } else {
        buffer.writeCharCode(bytes[i]);
      }
    }
    return buffer.toString();
  }

  static Uint8List _encodeName(String name) {
    final bytes = <int>[];
    final units = name.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit < 33 ||
          unit > 126 ||
          unit == 35 ||
          unit == 47 ||
          unit == 40 ||
          unit == 41 ||
          unit == 60 ||
          unit == 62 ||
          unit == 91 ||
          unit == 93 ||
          unit == 123 ||
          unit == 125) {
        bytes.add(35); // #
        final hex = unit.toRadixString(16).padLeft(2, '0').toUpperCase();
        bytes.addAll(hex.codeUnits);
      } else {
        bytes.add(unit);
      }
    }
    return Uint8List.fromList(bytes);
  }

  @override
  String toString() => '/$_value';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfName) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;

  // Encryption
  static final PdfName standard = PdfName.intern('Standard');
  static final PdfName encryptMetadata = PdfName.intern('EncryptMetadata');
  static final PdfName cf = PdfName.intern('CF');
  static final PdfName stdCF = PdfName.intern('StdCF');
  static final PdfName authEvent = PdfName.intern('AuthEvent');
  static final PdfName docOpen = PdfName.intern('DocOpen');
  static final PdfName efOpen = PdfName.intern('EFOpen');
  static final PdfName eff = PdfName.intern('EFF');
  static final PdfName strF = PdfName.intern('StrF');
  static final PdfName stmF = PdfName.intern('StmF');
  static final PdfName cfm = PdfName.intern('CFM');
  static final PdfName identity = PdfName.intern('Identity');
  static final PdfName v2 = PdfName.intern('V2');
  static final PdfName aesV2 = PdfName.intern('AESV2');
  static final PdfName aesV3 = PdfName.intern('AESV3');
  static final PdfName aesV4 = PdfName.intern('AESV4');
  static final PdfName o = PdfName.intern('O');
  static final PdfName u = PdfName.intern('U');

  // Basic properties used by crypto
  static final PdfName filter = PdfName.intern('Filter');
  static final PdfName p = PdfName.intern('P');
  static final PdfName r = PdfName.intern('R');
  static final PdfName v = PdfName.intern('V');
  static final PdfName length = PdfName.intern('Length');
  static final PdfName oe = PdfName.intern('OE');
  static final PdfName ue = PdfName.intern('UE');
  static final PdfName perms = PdfName.intern('Perms');

  // Object Streams
  static final PdfName type = PdfName.intern('Type');
  static final PdfName objStm = PdfName.intern('ObjStm');
  static final PdfName n = PdfName.intern('N');
  static final PdfName first = PdfName.intern('First');

  // Page / Resources
  static final PdfName contents = PdfName.intern('Contents');
  static final PdfName resources = PdfName.intern('Resources');
  static final PdfName mediaBox = PdfName.intern('MediaBox');
  static final PdfName parent = PdfName.intern('Parent');
  static final PdfName kids = PdfName.intern('Kids');
  static final PdfName count = PdfName.intern('Count');

  // Fonts
  static final PdfName subtype = PdfName.intern('Subtype');
  static final PdfName baseFont = PdfName.intern('BaseFont');
  static final PdfName type1 = PdfName.intern('Type1');
  static final PdfName trueType = PdfName.intern('TrueType');
  static final PdfName fontFile = PdfName.intern('FontFile');
  static final PdfName fontFile2 = PdfName.intern('FontFile2');
  static final PdfName fontFile3 = PdfName.intern('FontFile3');
  static final PdfName encoding = PdfName.intern('Encoding');
  static final PdfName fontDescriptor = PdfName.intern('FontDescriptor');
  static final PdfName fontName = PdfName.intern('FontName');
  static final PdfName flags = PdfName.intern('Flags');
  static final PdfName fontBBox = PdfName.intern('FontBBox');
  static final PdfName italicAngle = PdfName.intern('ItalicAngle');
  static final PdfName ascent = PdfName.intern('Ascent');
  static final PdfName descent = PdfName.intern('Descent');
  static final PdfName capHeight = PdfName.intern('CapHeight');
  static final PdfName stemV = PdfName.intern('StemV');
  static final PdfName xHeight = PdfName.intern('XHeight');
  static final PdfName avgWidth = PdfName.intern('AvgWidth');
  static final PdfName maxWidth = PdfName.intern('MaxWidth');
  static final PdfName missingWidth = PdfName.intern('MissingWidth');
  static final PdfName widths = PdfName.intern('Widths');
  static final PdfName firstChar = PdfName.intern('FirstChar');
  static final PdfName lastChar = PdfName.intern('LastChar');

  // Graphics
  static final PdfName relativeColorimetric =
      PdfName.intern('RelativeColorimetric');
  static final PdfName normal = PdfName.intern('Normal');
  static final PdfName none = PdfName.intern('None');

  // Color Spaces
  static final PdfName deviceGray = PdfName.intern('DeviceGray');
  static final PdfName deviceRgb = PdfName.intern('DeviceRGB');
  static final PdfName deviceCmyk = PdfName.intern('DeviceCMYK');
  static final PdfName pattern = PdfName.intern('Pattern');

  // Filters
  static final PdfName flateDecodeFilter = PdfName.intern('FlateDecode');
  static final PdfName asciiHexDecodeFilter = PdfName.intern('ASCIIHexDecode');
  static final PdfName ascii85DecodeFilter = PdfName.intern('ASCII85Decode');
  static final PdfName lzwDecodeFilter = PdfName.intern('LZWDecode');
  static final PdfName runLengthDecodeFilter =
      PdfName.intern('RunLengthDecode');
  static final PdfName ccittFaxDecode = PdfName.intern('CCITTFaxDecode');
  static final PdfName jbig2Decode = PdfName.intern('JBIG2Decode');
  static final PdfName dctDecode = PdfName.intern('DCTDecode');
  static final PdfName jpxDecode = PdfName.intern('JPXDecode');
  static final PdfName crypt = PdfName.intern('Crypt');

  // ExtGState
  static final PdfName extGState = PdfName.intern('ExtGState');
  static final PdfName lw = PdfName.intern('LW');
  static final PdfName lc = PdfName.intern('LC');
  static final PdfName lj = PdfName.intern('LJ');
  static final PdfName ml = PdfName.intern('ML');
  static final PdfName d = PdfName.intern('D');
  static final PdfName ri = PdfName.intern('RI');
  static final PdfName op = PdfName.intern('op');
  static final PdfName opUppercase = PdfName.intern('OP');
  static final PdfName opm = PdfName.intern('OPM');
  static final PdfName font = PdfName.intern('Font');
  static final PdfName bg = PdfName.intern('BG');
  static final PdfName bg2 = PdfName.intern('bg');
  static final PdfName ucr = PdfName.intern('UCR');
  static final PdfName ucr2 = PdfName.intern('UCR2'); // Corrected
  static final PdfName tr = PdfName.intern('TR');
  static final PdfName tr2 = PdfName.intern('TR2');
  static final PdfName ht = PdfName.intern('HT');
  static final PdfName fl = PdfName.intern('FL');
  static final PdfName sm = PdfName.intern('SM');
  static final PdfName sa = PdfName.intern('SA');
  static final PdfName bm = PdfName.intern('BM');
  static final PdfName smaskG = PdfName.intern('SMask');
  static final PdfName ca = PdfName.intern('ca');
  static final PdfName caUppercase = PdfName.intern('CA');
  static final PdfName ais = PdfName.intern('AIS');
  static final PdfName tk = PdfName.intern('TK');
  static final PdfName fontG = PdfName.intern('Font');

  // Catalog / Page
  static final PdfName catalog = PdfName.intern('Catalog');
  static final PdfName pageMode = PdfName.intern('PageMode');
  static final PdfName pageLayout = PdfName.intern('PageLayout');
  static final PdfName page = PdfName.intern('Page');
  static final PdfName pages = PdfName.intern('Pages');
  static final PdfName rotate = PdfName.intern('Rotate');
  static final PdfName cropBox = PdfName.intern('CropBox');
  static final PdfName root = PdfName.intern('Root');

  // Reader / Trailer
  static final PdfName prev = PdfName.intern('Prev');
  static final PdfName size = PdfName.intern('Size');
  static final PdfName w = PdfName.intern('W');
  static final PdfName index = PdfName.intern('Index');
  static final PdfName encrypt = PdfName.intern('Encrypt');
  static final PdfName info = PdfName.intern('Info');
  static final PdfName id = PdfName.intern('ID');

  // Resources
  static final PdfName xObject = PdfName.intern('XObject');
  static final PdfName properties = PdfName.intern('Properties');
  static final PdfName colorSpace = PdfName.intern('ColorSpace');
  static final PdfName shading = PdfName.intern('Shading');
  static final PdfName form = PdfName.intern('Form');
  // Resources
  static final PdfName bBox = PdfName.intern('BBox');

  // Image / Stream
  static final PdfName decodeParms = PdfName.intern('DecodeParms');
  static final PdfName width = PdfName.intern('Width');
  static final PdfName height = PdfName.intern('Height');
  static final PdfName bitsPerComponent = PdfName.intern('BitsPerComponent');
  static final PdfName indexed = PdfName.intern('Indexed');
  static final PdfName sMask = PdfName.intern('SMask');
  static final PdfName mask = PdfName.intern('Mask');
  static final PdfName decode = PdfName.intern('Decode');
  static final PdfName image = PdfName.intern('Image');

  // Document Info
  static final PdfName title = PdfName.intern('Title');
  static final PdfName author = PdfName.intern('Author');
  static final PdfName subject = PdfName.intern('Subject');
  static final PdfName keywords = PdfName.intern('Keywords');
  static final PdfName creator = PdfName.intern('Creator');
  static final PdfName producer = PdfName.intern('Producer');
  static final PdfName creationDate = PdfName.intern('CreationDate');
  static final PdfName modDate = PdfName.intern('ModDate');

  // Forms
  static final PdfName acroForm = PdfName.intern("AcroForm");
  static final PdfName fields = PdfName.intern("Fields");
  static final PdfName xfa = PdfName.intern("XFA");
  static final PdfName tu = PdfName.intern("TU");
  static final PdfName tm = PdfName.intern("TM");
  static final PdfName ff = PdfName.intern("Ff");
  static final PdfName ds = PdfName.intern("DS");
  static final PdfName rv = PdfName.intern("RV");
  static final PdfName maxLen = PdfName.intern("MaxLen");
  static final PdfName ti = PdfName.intern("TI");
  static final PdfName lock = PdfName.intern("Lock");
  static final PdfName sv = PdfName.intern("SV");
  static final PdfName sigFieldLock = PdfName.intern("SigFieldLock");
  static final PdfName action = PdfName.intern("Action");
  static final PdfName all = PdfName.intern("All");
  static final PdfName include = PdfName.intern("Include");
  static final PdfName exclude = PdfName.intern("Exclude");
  // Field Types
  // tx, btn, ch, sig are defined below around line 350
  static final PdfName needAppearances = PdfName.intern("NeedAppearances");
  static final PdfName sigFlags = PdfName.intern("SigFlags");
  static final PdfName co = PdfName.intern("CO");
  static final PdfName dr = PdfName.intern("DR");
  // da and font removed due to duplication

  // Annotations
  static final PdfName annot = PdfName.intern('Annot');
  static final PdfName annots = PdfName.intern('Annots');
  static final PdfName rect = PdfName.intern('Rect');
  static final PdfName nm = PdfName.intern('NM');
  static final PdfName m = PdfName.intern('M');
  static final PdfName f = PdfName.intern('F');
  static final PdfName ap = PdfName.intern('AP');
  static final PdfName as = PdfName.intern('AS');
  static final PdfName border = PdfName.intern('Border');
  static final PdfName c = PdfName.intern('C');
  static final PdfName oc = PdfName.intern('OC');

  // Annotation Subtypes
  static final PdfName widget = PdfName.intern('Widget');
  static final PdfName link = PdfName.intern('Link');
  static final PdfName popup = PdfName.intern('Popup');
  static final PdfName screen = PdfName.intern('Screen');
  static final PdfName printerMark = PdfName.intern('PrinterMark');
  static final PdfName trapNet = PdfName.intern('TrapNet');
  static final PdfName watermark = PdfName.intern('Watermark');
  static final PdfName text = PdfName.intern('Text');
  static final PdfName highlight = PdfName.intern('Highlight');
  static final PdfName underline = PdfName.intern('Underline');
  static final PdfName squiggly = PdfName.intern('Squiggly');
  static final PdfName strikeOut = PdfName.intern('StrikeOut');
  static final PdfName caret = PdfName.intern('Caret');
  static final PdfName sound = PdfName.intern('Sound');
  static final PdfName stamp = PdfName.intern('Stamp');
  static final PdfName fileAttachment = PdfName.intern('FileAttachment');
  static final PdfName ink = PdfName.intern('Ink');
  static final PdfName freeText = PdfName.intern('FreeText');
  static final PdfName square = PdfName.intern('Square');
  static final PdfName circle = PdfName.intern('Circle');
  static final PdfName line = PdfName.intern('Line');
  static final PdfName polygon = PdfName.intern('Polygon');
  static final PdfName polyLine = PdfName.intern('PolyLine');
  static final PdfName redact = PdfName.intern('Redact');
  static final PdfName threeD = PdfName.intern('3D');

  // Widget / Form / Actions
  // static final PdfName parent = PdfName.intern('Parent'); // Already exists? Check
  // static final PdfName kids = PdfName.intern('Kids'); // Already exists? Check
  static final PdfName mk = PdfName.intern('MK'); // Appearance Characteristics
  static final PdfName bs = PdfName.intern('BS'); // Border Style
  static final PdfName a = PdfName.intern('A'); // Action
  static final PdfName aa = PdfName.intern('AA'); // Additional Action
  static final PdfName ft = PdfName.intern('FT'); // Field Type
  static final PdfName tx = PdfName.intern('Tx');
  static final PdfName btn = PdfName.intern('Btn');
  static final PdfName ch = PdfName.intern('Ch');
  static final PdfName sig = PdfName.intern('Sig');
  static final PdfName da = PdfName.intern('DA'); // Default Appearance
  static final PdfName q = PdfName.intern('Q'); // Quadding (Alignment)

  // Flags & Enums
  static final PdfName i = PdfName.intern('I');
  static final PdfName t = PdfName.intern('T');
  static final PdfName b = PdfName.intern('B');
  static final PdfName s = PdfName.intern('S');

  static final PdfName dv = PdfName.intern('DV'); // Default Value
  static final PdfName opt = PdfName.intern('Opt');

  // Signature-related names
  static final PdfName byteRange = PdfName.intern('ByteRange');
  static final PdfName cert = PdfName.intern('Cert');
  static final PdfName name = PdfName.intern('Name');
  static final PdfName location = PdfName.intern('Location');
  static final PdfName reason = PdfName.intern('Reason');
  static final PdfName contactInfo = PdfName.intern('ContactInfo');
  static final PdfName propBuild = PdfName.intern('Prop_Build');
  static final PdfName app = PdfName.intern('App');
  static final PdfName subFilter = PdfName.intern('SubFilter');
  static final PdfName adbePkcs7Detached =
      PdfName.intern('adbe.pkcs7.detached');
  static final PdfName adbePkcs7Sha1 = PdfName.intern('adbe.pkcs7.sha1');
  static final PdfName adbeX509RsaSha1 = PdfName.intern('adbe.x509.rsa_sha1');
  static final PdfName etsiCadesDetached =
      PdfName.intern('ETSI.CAdES.detached');
  static final PdfName etsiRfc3161 = PdfName.intern('ETSI.RFC3161');
  static final PdfName docTimeStamp = PdfName.intern('DocTimeStamp');
  static final PdfName reference = PdfName.intern('Reference');
  static final PdfName transformMethod = PdfName.intern('TransformMethod');
  static final PdfName transformParams = PdfName.intern('TransformParams');
  static final PdfName docMDP = PdfName.intern('DocMDP');
  static final PdfName ur = PdfName.intern('UR');
  static final PdfName ur3 = PdfName.intern('UR3');
  static final PdfName fieldMDP = PdfName.intern('FieldMDP');
}
