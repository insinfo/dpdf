import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';

/// Represents a PDF name object.
///
/// Names are used as keys in dictionaries and to identify operators.
/// They are written with a leading slash: /Name
class CraftPdfName extends CraftPdfPrimitiveObject {
  /// Cache for interned names.
  static final Map<String, CraftPdfName> _staticNames = {};

  /// The name value (without leading slash).
  final String _value;

  /// Creates a PdfName from a string.
  CraftPdfName(String name) : _value = name;

  /// Creates a PdfName from bytes.
  factory CraftPdfName.fromBytes(Uint8List bytes) {
    final value = _decodeName(bytes);
    return CraftPdfName(value);
  }

  /// Gets or creates an interned (cached) name.
  factory CraftPdfName.intern(String name) {
    return _staticNames.putIfAbsent(name, () => CraftPdfName(name));
  }

  @override
  int objectKind() => PdfObjectType.name;

  @override
  CraftPdfObject clone() {
    return CraftPdfName(_value);
  }

  @override
  CraftPdfObject newInstance() {
    return CraftPdfName('');
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
    if (other is! CraftPdfName) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;

  // Encryption
  static final CraftPdfName standard = CraftPdfName.intern('Standard');
  static final CraftPdfName encryptMetadata =
      CraftPdfName.intern('EncryptMetadata');
  static final CraftPdfName cf = CraftPdfName.intern('CF');
  static final CraftPdfName stdCF = CraftPdfName.intern('StdCF');
  static final CraftPdfName authEvent = CraftPdfName.intern('AuthEvent');
  static final CraftPdfName docOpen = CraftPdfName.intern('DocOpen');
  static final CraftPdfName efOpen = CraftPdfName.intern('EFOpen');
  static final CraftPdfName eff = CraftPdfName.intern('EFF');
  static final CraftPdfName strF = CraftPdfName.intern('StrF');
  static final CraftPdfName stmF = CraftPdfName.intern('StmF');
  static final CraftPdfName cfm = CraftPdfName.intern('CFM');
  static final CraftPdfName identity = CraftPdfName.intern('Identity');
  static final CraftPdfName v2 = CraftPdfName.intern('V2');
  static final CraftPdfName aesV2 = CraftPdfName.intern('AESV2');
  static final CraftPdfName aesV3 = CraftPdfName.intern('AESV3');
  static final CraftPdfName aesV4 = CraftPdfName.intern('AESV4');
  static final CraftPdfName o = CraftPdfName.intern('O');
  static final CraftPdfName u = CraftPdfName.intern('U');

  // Basic properties used by crypto
  static final CraftPdfName filter = CraftPdfName.intern('Filter');
  static final CraftPdfName p = CraftPdfName.intern('P');
  static final CraftPdfName r = CraftPdfName.intern('R');
  static final CraftPdfName v = CraftPdfName.intern('V');
  static final CraftPdfName length = CraftPdfName.intern('Length');
  static final CraftPdfName oe = CraftPdfName.intern('OE');
  static final CraftPdfName ue = CraftPdfName.intern('UE');
  static final CraftPdfName perms = CraftPdfName.intern('Perms');

  // Object Streams
  static final CraftPdfName type = CraftPdfName.intern('Type');
  static final CraftPdfName xref = CraftPdfName.intern('XRef');
  static final CraftPdfName objStm = CraftPdfName.intern('ObjStm');
  static final CraftPdfName n = CraftPdfName.intern('N');
  static final CraftPdfName first = CraftPdfName.intern('First');

  // Page / Resources
  static final CraftPdfName contents = CraftPdfName.intern('Contents');
  static final CraftPdfName resources = CraftPdfName.intern('Resources');
  static final CraftPdfName mediaBox = CraftPdfName.intern('MediaBox');
  static final CraftPdfName parent = CraftPdfName.intern('Parent');
  static final CraftPdfName kids = CraftPdfName.intern('Kids');
  static final CraftPdfName count = CraftPdfName.intern('Count');

  // Fonts
  static final CraftPdfName subtype = CraftPdfName.intern('Subtype');
  static final CraftPdfName baseFont = CraftPdfName.intern('BaseFont');
  static final CraftPdfName type1 = CraftPdfName.intern('Type1');
  static final CraftPdfName type3 = CraftPdfName.intern('Type3');
  static final CraftPdfName mMType1 = CraftPdfName.intern('MMType1');
  static final CraftPdfName trueType = CraftPdfName.intern('TrueType');
  static final CraftPdfName fontFile = CraftPdfName.intern('FontFile');
  static final CraftPdfName fontFile2 = CraftPdfName.intern('FontFile2');
  static final CraftPdfName fontFile3 = CraftPdfName.intern('FontFile3');
  static final CraftPdfName encoding = CraftPdfName.intern('Encoding');
  static final CraftPdfName fontDescriptor =
      CraftPdfName.intern('FontDescriptor');
  static final CraftPdfName fontName = CraftPdfName.intern('FontName');
  static final CraftPdfName flags = CraftPdfName.intern('Flags');
  static final CraftPdfName fontBBox = CraftPdfName.intern('FontBBox');
  static final CraftPdfName italicAngle = CraftPdfName.intern('ItalicAngle');
  static final CraftPdfName ascent = CraftPdfName.intern('Ascent');
  static final CraftPdfName descent = CraftPdfName.intern('Descent');
  static final CraftPdfName capHeight = CraftPdfName.intern('CapHeight');
  static final CraftPdfName stemV = CraftPdfName.intern('StemV');
  static final CraftPdfName xHeight = CraftPdfName.intern('XHeight');
  static final CraftPdfName avgWidth = CraftPdfName.intern('AvgWidth');
  static final CraftPdfName maxWidth = CraftPdfName.intern('MaxWidth');
  static final CraftPdfName missingWidth = CraftPdfName.intern('MissingWidth');
  static final CraftPdfName widths = CraftPdfName.intern('Widths');
  static final CraftPdfName firstChar = CraftPdfName.intern('FirstChar');
  static final CraftPdfName lastChar = CraftPdfName.intern('LastChar');
  static final CraftPdfName charProcs = CraftPdfName.intern('CharProcs');
  static final CraftPdfName fontMatrix = CraftPdfName.intern('FontMatrix');

  // Graphics
  static final CraftPdfName relativeColorimetric =
      CraftPdfName.intern('RelativeColorimetric');
  static final CraftPdfName normal = CraftPdfName.intern('Normal');
  static final CraftPdfName none = CraftPdfName.intern('None');

  // Color Spaces
  static final CraftPdfName deviceGray = CraftPdfName.intern('DeviceGray');
  static final CraftPdfName deviceRgb = CraftPdfName.intern('DeviceRGB');
  static final CraftPdfName deviceCmyk = CraftPdfName.intern('DeviceCMYK');
  static final CraftPdfName pattern = CraftPdfName.intern('Pattern');
  static final CraftPdfName calGray = CraftPdfName.intern('CalGray');
  static final CraftPdfName calRgb = CraftPdfName.intern('CalRGB');
  static final CraftPdfName lab = CraftPdfName.intern('Lab');
  static final CraftPdfName iccBased = CraftPdfName.intern('ICCBased');
  static final CraftPdfName separation = CraftPdfName.intern('Separation');
  static final CraftPdfName deviceN = CraftPdfName.intern('DeviceN');

  // Filters
  static final CraftPdfName flateDecodeFilter =
      CraftPdfName.intern('FlateDecode');
  static final CraftPdfName asciiHexDecodeFilter =
      CraftPdfName.intern('ASCIIHexDecode');
  static final CraftPdfName ascii85DecodeFilter =
      CraftPdfName.intern('ASCII85Decode');
  static final CraftPdfName lzwDecodeFilter = CraftPdfName.intern('LZWDecode');
  static final CraftPdfName runLengthDecodeFilter =
      CraftPdfName.intern('RunLengthDecode');
  static final CraftPdfName ccittFaxDecode =
      CraftPdfName.intern('CCITTFaxDecode');
  static final CraftPdfName jbig2Decode = CraftPdfName.intern('JBIG2Decode');
  static final CraftPdfName dctDecode = CraftPdfName.intern('DCTDecode');
  static final CraftPdfName jpxDecode = CraftPdfName.intern('JPXDecode');
  static final CraftPdfName crypt = CraftPdfName.intern('Crypt');

  // ExtGState
  static final CraftPdfName extGState = CraftPdfName.intern('ExtGState');
  static final CraftPdfName lw = CraftPdfName.intern('LW');
  static final CraftPdfName lc = CraftPdfName.intern('LC');
  static final CraftPdfName lj = CraftPdfName.intern('LJ');
  static final CraftPdfName ml = CraftPdfName.intern('ML');
  static final CraftPdfName d = CraftPdfName.intern('D');
  static final CraftPdfName ri = CraftPdfName.intern('RI');
  static final CraftPdfName op = CraftPdfName.intern('op');
  static final CraftPdfName opUppercase = CraftPdfName.intern('OP');
  static final CraftPdfName opm = CraftPdfName.intern('OPM');
  static final CraftPdfName font = CraftPdfName.intern('Font');
  static final CraftPdfName bg = CraftPdfName.intern('BG');
  static final CraftPdfName bg2 = CraftPdfName.intern('bg');
  static final CraftPdfName ucr = CraftPdfName.intern('UCR');
  static final CraftPdfName ucr2 = CraftPdfName.intern('UCR2'); // Corrected
  static final CraftPdfName tr = CraftPdfName.intern('TR');
  static final CraftPdfName tr2 = CraftPdfName.intern('TR2');
  static final CraftPdfName ht = CraftPdfName.intern('HT');
  static final CraftPdfName fl = CraftPdfName.intern('FL');
  static final CraftPdfName sm = CraftPdfName.intern('SM');
  static final CraftPdfName sa = CraftPdfName.intern('SA');
  static final CraftPdfName bm = CraftPdfName.intern('BM');
  static final CraftPdfName smaskG = CraftPdfName.intern('SMask');
  static final CraftPdfName ca = CraftPdfName.intern('ca');
  static final CraftPdfName caUppercase = CraftPdfName.intern('CA');
  static final CraftPdfName ais = CraftPdfName.intern('AIS');
  static final CraftPdfName tk = CraftPdfName.intern('TK');
  static final CraftPdfName fontG = CraftPdfName.intern('Font');

  // Catalog / Page
  static final CraftPdfName catalog = CraftPdfName.intern('Catalog');
  static final CraftPdfName pageMode = CraftPdfName.intern('PageMode');
  static final CraftPdfName pageLayout = CraftPdfName.intern('PageLayout');
  static final CraftPdfName page = CraftPdfName.intern('Page');
  static final CraftPdfName pages = CraftPdfName.intern('Pages');
  static final CraftPdfName rotate = CraftPdfName.intern('Rotate');
  static final CraftPdfName cropBox = CraftPdfName.intern('CropBox');
  static final CraftPdfName root = CraftPdfName.intern('Root');

  // Reader / Trailer
  static final CraftPdfName prev = CraftPdfName.intern('Prev');
  static final CraftPdfName size = CraftPdfName.intern('Size');
  static final CraftPdfName w = CraftPdfName.intern('W');
  static final CraftPdfName index = CraftPdfName.intern('Index');
  static final CraftPdfName encrypt = CraftPdfName.intern('Encrypt');
  static final CraftPdfName info = CraftPdfName.intern('Info');
  static final CraftPdfName id = CraftPdfName.intern('ID');
  static final CraftPdfName metadata = CraftPdfName.intern('Metadata');
  static final CraftPdfName xml = CraftPdfName.intern('XML');
  static final CraftPdfName xrefStm = CraftPdfName.intern('XRefStm');

  // Resources
  static final CraftPdfName xObject = CraftPdfName.intern('XObject');
  static final CraftPdfName properties = CraftPdfName.intern('Properties');
  static final CraftPdfName colorSpace = CraftPdfName.intern('ColorSpace');
  static final CraftPdfName shading = CraftPdfName.intern('Shading');
  static final CraftPdfName form = CraftPdfName.intern('Form');
  // Resources
  static final CraftPdfName bBox = CraftPdfName.intern('BBox');
  static final CraftPdfName matrix = CraftPdfName.intern('Matrix');
  static final CraftPdfName shadingType = CraftPdfName.intern('ShadingType');
  static final CraftPdfName function = CraftPdfName.intern('Function');
  static final CraftPdfName coords = CraftPdfName.intern('Coords');

  // Image / Stream
  static final CraftPdfName decodeParms = CraftPdfName.intern('DecodeParms');
  static final CraftPdfName width = CraftPdfName.intern('Width');
  static final CraftPdfName height = CraftPdfName.intern('Height');
  static final CraftPdfName bitsPerComponent =
      CraftPdfName.intern('BitsPerComponent');
  static final CraftPdfName indexed = CraftPdfName.intern('Indexed');
  static final CraftPdfName sMask = CraftPdfName.intern('SMask');
  static final CraftPdfName mask = CraftPdfName.intern('Mask');
  static final CraftPdfName decode = CraftPdfName.intern('Decode');
  static final CraftPdfName image = CraftPdfName.intern('Image');
  static final CraftPdfName imageMask = CraftPdfName.intern('ImageMask');
  static final CraftPdfName interpolate = CraftPdfName.intern('Interpolate');

  static final CraftPdfName type0 = CraftPdfName.intern('Type0');
  static final CraftPdfName descendantFonts =
      CraftPdfName.intern('DescendantFonts');
  static final CraftPdfName cidFontType2 = CraftPdfName.intern('CIDFontType2');
  static final CraftPdfName cidFontType0 = CraftPdfName.intern('CIDFontType0');
  static final CraftPdfName identityH = CraftPdfName.intern('Identity-H');
  static final CraftPdfName identityV = CraftPdfName.intern('Identity-V');
  static final CraftPdfName toUnicode = CraftPdfName.intern('ToUnicode');
  static final CraftPdfName cidSystemInfo =
      CraftPdfName.intern('CIDSystemInfo');
  static final CraftPdfName cidToGIDMap = CraftPdfName.intern('CIDToGIDMap');
  static final CraftPdfName dw = CraftPdfName.intern('DW');
  // W is already defined as 'W' for stream dictionary, we can reuse it or define CIDFont version

  // Document Info
  static final CraftPdfName title = CraftPdfName.intern('Title');
  static final CraftPdfName author = CraftPdfName.intern('Author');
  static final CraftPdfName subject = CraftPdfName.intern('Subject');
  static final CraftPdfName keywords = CraftPdfName.intern('Keywords');
  static final CraftPdfName creator = CraftPdfName.intern('Creator');
  static final CraftPdfName producer = CraftPdfName.intern('Producer');
  static final CraftPdfName creationDate = CraftPdfName.intern('CreationDate');
  static final CraftPdfName modDate = CraftPdfName.intern('ModDate');

  // Forms
  static final CraftPdfName acroForm = CraftPdfName.intern("AcroForm");
  static final CraftPdfName fields = CraftPdfName.intern("Fields");
  static final CraftPdfName xfa = CraftPdfName.intern("XFA");
  static final CraftPdfName tm = CraftPdfName.intern("TM");
  static final CraftPdfName ff = CraftPdfName.intern("Ff");
  static final CraftPdfName ds = CraftPdfName.intern("DS");
  static final CraftPdfName rv = CraftPdfName.intern("RV");
  static final CraftPdfName maxLen = CraftPdfName.intern("MaxLen");
  static final CraftPdfName ti = CraftPdfName.intern("TI");
  static final CraftPdfName lock = CraftPdfName.intern("Lock");
  static final CraftPdfName sv = CraftPdfName.intern("SV");
  static final CraftPdfName sigFieldLock = CraftPdfName.intern("SigFieldLock");
  static final CraftPdfName action = CraftPdfName.intern("Action");
  static final CraftPdfName all = CraftPdfName.intern("All");
  static final CraftPdfName include = CraftPdfName.intern("Include");
  static final CraftPdfName exclude = CraftPdfName.intern("Exclude");
  // Field Types
  // tx, btn, ch, sig are defined below around line 350
  static final CraftPdfName needAppearances =
      CraftPdfName.intern("NeedAppearances");
  static final CraftPdfName sigFlags = CraftPdfName.intern("SigFlags");
  static final CraftPdfName co = CraftPdfName.intern("CO");
  static final CraftPdfName dr = CraftPdfName.intern("DR");
  // da and font removed due to duplication

  // Annotations
  static final CraftPdfName annot = CraftPdfName.intern('Annot');
  static final CraftPdfName annots = CraftPdfName.intern('Annots');
  static final CraftPdfName rect = CraftPdfName.intern('Rect');
  static final CraftPdfName nm = CraftPdfName.intern('NM');
  static final CraftPdfName m = CraftPdfName.intern('M');
  static final CraftPdfName f = CraftPdfName.intern('F');
  static final CraftPdfName ap = CraftPdfName.intern('AP');
  static final CraftPdfName as = CraftPdfName.intern('AS');
  static final CraftPdfName border = CraftPdfName.intern('Border');
  static final CraftPdfName c = CraftPdfName.intern('C');
  static final CraftPdfName oc = CraftPdfName.intern('OC');

  // Annotation Subtypes
  static final CraftPdfName widget = CraftPdfName.intern('Widget');
  static final CraftPdfName link = CraftPdfName.intern('Link');
  static final CraftPdfName popup = CraftPdfName.intern('Popup');
  static final CraftPdfName screen = CraftPdfName.intern('Screen');
  static final CraftPdfName printerMark = CraftPdfName.intern('PrinterMark');
  static final CraftPdfName trapNet = CraftPdfName.intern('TrapNet');
  static final CraftPdfName watermark = CraftPdfName.intern('Watermark');
  static final CraftPdfName text = CraftPdfName.intern('Text');
  static final CraftPdfName highlight = CraftPdfName.intern('Highlight');
  static final CraftPdfName underline = CraftPdfName.intern('Underline');
  static final CraftPdfName squiggly = CraftPdfName.intern('Squiggly');
  static final CraftPdfName strikeOut = CraftPdfName.intern('StrikeOut');
  static final CraftPdfName caret = CraftPdfName.intern('Caret');
  static final CraftPdfName sound = CraftPdfName.intern('Sound');
  static final CraftPdfName stamp = CraftPdfName.intern('Stamp');
  static final CraftPdfName fileAttachment =
      CraftPdfName.intern('FileAttachment');
  static final CraftPdfName ink = CraftPdfName.intern('Ink');
  static final CraftPdfName freeText = CraftPdfName.intern('FreeText');
  static final CraftPdfName square = CraftPdfName.intern('Square');
  static final CraftPdfName circle = CraftPdfName.intern('Circle');
  static final CraftPdfName line = CraftPdfName.intern('Line');
  static final CraftPdfName polygon = CraftPdfName.intern('Polygon');
  static final CraftPdfName polyLine = CraftPdfName.intern('PolyLine');
  static final CraftPdfName redact = CraftPdfName.intern('Redact');
  static final CraftPdfName threeD = CraftPdfName.intern('3D');

  // Widget / Form / Actions
  // static final PdfName parent = PdfName.intern('Parent'); // Already exists? Check
  // static final PdfName kids = PdfName.intern('Kids'); // Already exists? Check
  static final CraftPdfName mk =
      CraftPdfName.intern('MK'); // Appearance Characteristics
  static final CraftPdfName bs = CraftPdfName.intern('BS'); // Border Style
  static final CraftPdfName a = CraftPdfName.intern('A'); // Action
  static final CraftPdfName aa = CraftPdfName.intern('AA'); // Additional Action
  static final CraftPdfName ft = CraftPdfName.intern('FT'); // Field Type
  static final CraftPdfName tx = CraftPdfName.intern('Tx');
  static final CraftPdfName btn = CraftPdfName.intern('Btn');
  static final CraftPdfName ch = CraftPdfName.intern('Ch');
  static final CraftPdfName tabs = CraftPdfName.intern('Tabs');
  static final CraftPdfName viewerPreferences =
      CraftPdfName.intern('ViewerPreferences');
  static final CraftPdfName displayDocTitle =
      CraftPdfName.intern('DisplayDocTitle');
  static final CraftPdfName tu = CraftPdfName.intern('TU');
  static final CraftPdfName s = CraftPdfName.intern('S');
  static final CraftPdfName sig = CraftPdfName.intern('Sig');
  static final CraftPdfName da =
      CraftPdfName.intern('DA'); // Default Appearance
  static final CraftPdfName q =
      CraftPdfName.intern('Q'); // Quadding (Alignment)

  // Flags & Enums
  static final CraftPdfName i = CraftPdfName.intern('I');
  static final CraftPdfName t = CraftPdfName.intern('T');
  static final CraftPdfName b = CraftPdfName.intern('B');

  static final CraftPdfName dv = CraftPdfName.intern('DV'); // Default Value
  static final CraftPdfName opt = CraftPdfName.intern('Opt');
  static final CraftPdfName opts = CraftPdfName.intern('Opts');

  // Signature-related names
  static final CraftPdfName byteRange = CraftPdfName.intern('ByteRange');
  static final CraftPdfName cert = CraftPdfName.intern('Cert');
  static final CraftPdfName name = CraftPdfName.intern('Name');
  static final CraftPdfName location = CraftPdfName.intern('Location');
  static final CraftPdfName reason = CraftPdfName.intern('Reason');
  static final CraftPdfName contactInfo = CraftPdfName.intern('ContactInfo');
  static final CraftPdfName propBuild = CraftPdfName.intern('Prop_Build');
  static final CraftPdfName app = CraftPdfName.intern('App');
  static final CraftPdfName subFilter = CraftPdfName.intern('SubFilter');
  static final CraftPdfName adbePkcs7Detached =
      CraftPdfName.intern('adbe.pkcs7.detached');
  static final CraftPdfName adbePkcs7Sha1 =
      CraftPdfName.intern('adbe.pkcs7.sha1');
  static final CraftPdfName adbeX509RsaSha1 =
      CraftPdfName.intern('adbe.x509.rsa_sha1');
  static final CraftPdfName etsiCadesDetached =
      CraftPdfName.intern('ETSI.CAdES.detached');
  static final CraftPdfName etsiRfc3161 = CraftPdfName.intern('ETSI.RFC3161');
  static final CraftPdfName docTimeStamp = CraftPdfName.intern('DocTimeStamp');
  static final CraftPdfName reference = CraftPdfName.intern('Reference');
  static final CraftPdfName transformMethod =
      CraftPdfName.intern('TransformMethod');
  static final CraftPdfName transformParams =
      CraftPdfName.intern('TransformParams');
  static final CraftPdfName docMDP = CraftPdfName.intern('DocMDP');
  static final CraftPdfName ur = CraftPdfName.intern('UR');
  static final CraftPdfName ur3 = CraftPdfName.intern('UR3');
  static final CraftPdfName fieldMDP = CraftPdfName.intern('FieldMDP');

  // Actions
  static final CraftPdfName uri = CraftPdfName.intern('URI');
  static final CraftPdfName goTo = CraftPdfName.intern('GoTo');
  static final CraftPdfName goToR = CraftPdfName.intern('GoToR');
  static final CraftPdfName goToE = CraftPdfName.intern('GoToE');
  static final CraftPdfName launch = CraftPdfName.intern('Launch');
  static final CraftPdfName structTreeRoot =
      CraftPdfName.intern('StructTreeRoot');
  static final CraftPdfName thread = CraftPdfName.intern('Thread');
  static final CraftPdfName importData = CraftPdfName.intern('ImportData');
  static final CraftPdfName javaScript = CraftPdfName.intern('JavaScript');
  static final CraftPdfName js = CraftPdfName.intern('JS');
  static final CraftPdfName named = CraftPdfName.intern('Named');
  static final CraftPdfName submitForm = CraftPdfName.intern('SubmitForm');
  static final CraftPdfName resetForm = CraftPdfName.intern('ResetForm');

  // Tagged PDF / Structure
  static final CraftPdfName roleMap = CraftPdfName.intern('RoleMap');
  static final CraftPdfName k = CraftPdfName.intern('K');
  // PdfName.p is already defined
  static final CraftPdfName parentTree = CraftPdfName.intern('ParentTree');
  static final CraftPdfName parentTreeNextKey =
      CraftPdfName.intern('ParentTreeNextKey');
  static final CraftPdfName classMap = CraftPdfName.intern('ClassMap');
  static final CraftPdfName structElem = CraftPdfName.intern('StructElem');
  static final CraftPdfName structParent = CraftPdfName.intern('StructParent');
  static final CraftPdfName structParents =
      CraftPdfName.intern('StructParents');
  static final CraftPdfName idTree = CraftPdfName.intern('IDTree');
  static final CraftPdfName namespace = CraftPdfName.intern('Namespace');
  static final CraftPdfName ns = CraftPdfName.intern('NS');
  static final CraftPdfName schema = CraftPdfName.intern('Schema');
  static final CraftPdfName roleMapNS = CraftPdfName.intern('RoleMapNS');
  static final CraftPdfName namespaces = CraftPdfName.intern('Namespaces');

  // Additional Names for Catalog/Document
  static final CraftPdfName names = CraftPdfName.intern('Names');
  static final CraftPdfName dests = CraftPdfName.intern('Dests');
  static final CraftPdfName outlines = CraftPdfName.intern('Outlines');
  static final CraftPdfName embeddedFiles =
      CraftPdfName.intern('EmbeddedFiles');
  static final CraftPdfName af = CraftPdfName.intern('AF');
  static final CraftPdfName afRelationship =
      CraftPdfName.intern('AFRelationship');
  static final CraftPdfName collection = CraftPdfName.intern('Collection');
  static final CraftPdfName outputIntents =
      CraftPdfName.intern('OutputIntents');
  static final CraftPdfName markInfo = CraftPdfName.intern('MarkInfo');
  static final CraftPdfName marked = CraftPdfName.intern('Marked');
  static final CraftPdfName userProperties =
      CraftPdfName.intern('UserProperties');
  static final CraftPdfName ocProperties = CraftPdfName.intern('OCProperties');
  static final CraftPdfName pageLabels = CraftPdfName.intern('PageLabels');
  static final CraftPdfName pieceInfo = CraftPdfName.intern('PieceInfo');
  static final CraftPdfName version = CraftPdfName.intern('Version');
  static final CraftPdfName start = CraftPdfName.intern(
      'Start'); // St is 2 chars usually but let's check standard
  static final CraftPdfName st = CraftPdfName.intern('St'); // For PageLabels

  // Destinations
  static final CraftPdfName fit = CraftPdfName.intern('Fit');
  static final CraftPdfName xyz = CraftPdfName.intern('XYZ');
  static final CraftPdfName fitH = CraftPdfName.intern('FitH');
  static final CraftPdfName fitV = CraftPdfName.intern('FitV');
  static final CraftPdfName fitR = CraftPdfName.intern('FitR');
  static final CraftPdfName fitB = CraftPdfName.intern('FitB');
  static final CraftPdfName fitBH = CraftPdfName.intern('FitBH');
  static final CraftPdfName fitBV = CraftPdfName.intern('FitBV');
  static final CraftPdfName dest = CraftPdfName.intern('Dest');
  static final CraftPdfName next = CraftPdfName.intern('Next');
  static final CraftPdfName last = CraftPdfName.intern('Last');
  static final CraftPdfName limits = CraftPdfName.intern('Limits');
  static final CraftPdfName nums = CraftPdfName.intern('Nums'); // Added
  static final CraftPdfName outputIntent = CraftPdfName.intern('OutputIntent');
  static final CraftPdfName gts_pdfa1 = CraftPdfName.intern('GTS_PDFA1');
  static final CraftPdfName outputCondition =
      CraftPdfName.intern('OutputCondition');
  static final CraftPdfName outputConditionIdentifier =
      CraftPdfName.intern('OutputConditionIdentifier');
  static final CraftPdfName registryName = CraftPdfName.intern('RegistryName');
  static final CraftPdfName destOutputProfile =
      CraftPdfName.intern('DestOutputProfile');

  // Font related (non-duplicates)
  static final CraftPdfName baseEncoding = CraftPdfName.intern('BaseEncoding');
  static final CraftPdfName differences = CraftPdfName.intern('Differences');
  static final CraftPdfName winAnsiEncoding =
      CraftPdfName.intern('WinAnsiEncoding');
  static final CraftPdfName macRomanEncoding =
      CraftPdfName.intern('MacRomanEncoding');
  static final CraftPdfName macExpertEncoding =
      CraftPdfName.intern('MacExpertEncoding');
  static final CraftPdfName pdfDocEncoding =
      CraftPdfName.intern('PdfDocEncoding');
  static final CraftPdfName standardEncoding =
      CraftPdfName.intern('StandardEncoding');
}
