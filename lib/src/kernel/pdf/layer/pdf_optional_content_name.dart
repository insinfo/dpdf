import 'package:dpdf/src/kernel/pdf/pdf_name.dart';

/// Dictionary keys and constant names used by optional content (layers),
/// ISO 32000-1, clause 8.11.
///
/// They are interned here instead of in [PdfName] so that the layer package
/// stays self contained, the same way [PdfFunctionName] does for functions.
class PdfOcName {
  PdfOcName._();

  // --- Object types (tables 98 and 99) ---------------------------------
  static final PdfName type = PdfName.intern('Type');
  static final PdfName ocg = PdfName.intern('OCG');
  static final PdfName ocmd = PdfName.intern('OCMD');

  // --- Optional content group entries (table 98) -----------------------
  static final PdfName name = PdfName.intern('Name');
  static final PdfName intent = PdfName.intern('Intent');
  static final PdfName usage = PdfName.intern('Usage');

  // --- Intents (clause 8.11.2.3) ---------------------------------------
  static final PdfName view = PdfName.intern('View');
  static final PdfName design = PdfName.intern('Design');
  static final PdfName all = PdfName.intern('All');

  // --- Membership dictionary entries (table 99) ------------------------
  static final PdfName ocgs = PdfName.intern('OCGs');
  static final PdfName p = PdfName.intern('P');
  static final PdfName ve = PdfName.intern('VE');

  // --- Visibility policies (table 99) ----------------------------------
  static final PdfName allOn = PdfName.intern('AllOn');
  static final PdfName anyOn = PdfName.intern('AnyOn');
  static final PdfName anyOff = PdfName.intern('AnyOff');
  static final PdfName allOff = PdfName.intern('AllOff');

  // --- Visibility expression operators (clause 8.11.2.2) ---------------
  static final PdfName and = PdfName.intern('And');
  static final PdfName or = PdfName.intern('Or');
  static final PdfName not = PdfName.intern('Not');

  // --- Optional content properties dictionary (table 100) --------------
  static final PdfName ocProperties = PdfName.intern('OCProperties');
  static final PdfName d = PdfName.intern('D');
  static final PdfName configs = PdfName.intern('Configs');

  // --- Configuration dictionary (table 101) ----------------------------
  static final PdfName creator = PdfName.intern('Creator');
  static final PdfName baseState = PdfName.intern('BaseState');
  static final PdfName on = PdfName.intern('ON');
  static final PdfName off = PdfName.intern('OFF');
  static final PdfName unchanged = PdfName.intern('Unchanged');
  static final PdfName autoStates = PdfName.intern('AS');
  static final PdfName order = PdfName.intern('Order');
  static final PdfName listMode = PdfName.intern('ListMode');
  static final PdfName allPages = PdfName.intern('AllPages');
  static final PdfName visiblePages = PdfName.intern('VisiblePages');
  static final PdfName rbGroups = PdfName.intern('RBGroups');
  static final PdfName locked = PdfName.intern('Locked');

  // --- Usage dictionary (table 102) ------------------------------------
  static final PdfName creatorInfo = PdfName.intern('CreatorInfo');
  static final PdfName language = PdfName.intern('Language');
  static final PdfName lang = PdfName.intern('Lang');
  static final PdfName preferred = PdfName.intern('Preferred');
  static final PdfName export = PdfName.intern('Export');
  static final PdfName exportState = PdfName.intern('ExportState');
  static final PdfName zoom = PdfName.intern('Zoom');
  static final PdfName min = PdfName.intern('min');
  static final PdfName max = PdfName.intern('max');
  static final PdfName print = PdfName.intern('Print');
  static final PdfName printState = PdfName.intern('PrintState');
  static final PdfName viewState = PdfName.intern('ViewState');
  static final PdfName user = PdfName.intern('User');
  static final PdfName pageElement = PdfName.intern('PageElement');
  static final PdfName subtype = PdfName.intern('Subtype');

  // --- Usage application dictionary (table 103) ------------------------
  static final PdfName event = PdfName.intern('Event');
  static final PdfName category = PdfName.intern('Category');

  // --- Making content optional (clauses 8.11.3.2 and 8.11.3.3) ---------
  static final PdfName oc = PdfName.intern('OC');
  static final PdfName properties = PdfName.intern('Properties');
}
