import '../pdf_name.dart';

/// Names that only the logical-structure machinery uses
/// (ISO 32000-1:2008, 14.7 "Logical Structure" and 14.8 "Tagged PDF").
///
/// They live here instead of in [PdfName] so the tagging code owns the
/// vocabulary it introduces.
class TaggingNames {
  TaggingNames._();

  /// Structure element and structure tree root keys (Tables 322 and 323).
  static final PdfName pg = PdfName.intern('Pg');
  static final PdfName alt = PdfName.intern('Alt');
  static final PdfName actualText = PdfName.intern('ActualText');
  static final PdfName e = PdfName.intern('E');
  static final PdfName lang = PdfName.intern('Lang');

  /// Marked-content reference keys (Table 324).
  static final PdfName mcr = PdfName.intern('MCR');
  static final PdfName mcid = PdfName.intern('MCID');
  static final PdfName stm = PdfName.intern('Stm');
  static final PdfName stmOwn = PdfName.intern('StmOwn');

  /// Object reference keys (Table 325).
  static final PdfName objr = PdfName.intern('OBJR');
  static final PdfName obj = PdfName.intern('Obj');

  /// Attribute object owner (Table 327).
  static final PdfName o = PdfName.intern('O');

  /// Name tree / number tree node keys (7.9.6 and 7.9.7).
  static final PdfName names = PdfName.intern('Names');
  static final PdfName nums = PdfName.intern('Nums');
  static final PdfName kids = PdfName.intern('Kids');
  static final PdfName limits = PdfName.intern('Limits');
}
