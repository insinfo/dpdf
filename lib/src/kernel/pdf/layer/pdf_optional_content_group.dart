import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_name.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_text.dart';

/// An optional content group, ISO 32000-1, clause 8.11.2 (table 98).
///
/// A group is a named collection of graphics whose visibility a reader can
/// toggle; the graphics need not be consecutive in drawing order nor live in
/// the same content stream. A group must be an indirect object because content
/// streams, XObjects and annotations refer to it by reference.
class PdfOptionalContentGroup extends PdfObjectWrapper<PdfDictionary> {
  /// Creates a new `/Type /OCG` dictionary named [name].
  PdfOptionalContentGroup(String name) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfOcName.type, PdfOcName.ocg);
    setName(name);
  }

  /// Wraps an existing group dictionary without validating it.
  PdfOptionalContentGroup.fromDictionary(super.pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  /// Reads a group from [object], which may be an indirect reference.
  ///
  /// Returns null when the object is not a dictionary whose `/Type` is `/OCG`.
  /// Clause 8.11.3.2 makes that check load bearing: `/OC` marked content is
  /// optional content only when its operand really is a group or a membership
  /// dictionary.
  static Future<PdfOptionalContentGroup?> parse(PdfObject? object) async {
    final dict = await resolveDictionary(object);
    if (dict == null) return null;
    final type = await dict.nameEntry(PdfOcName.type);
    if (type != PdfOcName.ocg) return null;
    return PdfOptionalContentGroup.fromDictionary(dict);
  }

  /// Resolves [object] to a dictionary, following one indirect reference.
  static Future<PdfDictionary?> resolveDictionary(PdfObject? object) async {
    var resolved = object;
    if (resolved is PdfIndirectReference) {
      resolved = await resolved.targetObject(true);
    }
    if (resolved is PdfDictionary) return resolved;
    return null;
  }

  /// The `/Name` entry: the label a reader shows in its layer panel.
  Future<String?> getName() async {
    final value = await pdfRepresentation().stringEntry(PdfOcName.name);
    return value == null ? null : readOcTextString(value);
  }

  void setName(String name) {
    pdfRepresentation().put(PdfOcName.name, makeOcTextString(name));
  }

  /// The `/Intent` entry as a list, defaulting to `[/View]` (table 98).
  Future<List<PdfName>> getIntents() async {
    return readIntents(pdfRepresentation());
  }

  /// Writes `/Intent`, using the single name form when only one is given.
  void setIntents(List<PdfName> intents) {
    if (intents.isEmpty) {
      pdfRepresentation().put(PdfOcName.intent, PdfArray());
      return;
    }
    if (intents.length == 1) {
      pdfRepresentation().put(PdfOcName.intent, intents.first);
      return;
    }
    pdfRepresentation()
        .put(PdfOcName.intent, PdfArray.fromList(List<PdfObject>.of(intents)));
  }

  /// Reads an `/Intent` entry of a group or of a configuration dictionary.
  ///
  /// Both tables 98 and 101 allow a single name or an array of names and both
  /// default to `/View`, so one reader serves them.
  static Future<List<PdfName>> readIntents(PdfDictionary dict) async {
    final direct = await dict.get(PdfOcName.intent, true);
    if (direct is PdfName) return <PdfName>[direct];
    if (direct is PdfArray) {
      final names = <PdfName>[];
      for (var i = 0; i < direct.size(); i++) {
        final name = await direct.nameEntry(i);
        if (name != null) names.add(name);
      }
      // An explicitly empty array is meaningful for a configuration: clause
      // 8.11.2.3 says no group is then used in determining visibility.
      return names;
    }
    return <PdfName>[PdfOcName.view];
  }

  /// The `/Usage` dictionary (table 102), or null when the group has none.
  Future<PdfOptionalContentUsage?> getUsage() async {
    final dict = await pdfRepresentation().dictionaryEntry(PdfOcName.usage);
    return dict == null ? null : PdfOptionalContentUsage.fromDictionary(dict);
  }

  /// Returns the `/Usage` dictionary, creating an empty one when absent.
  Future<PdfOptionalContentUsage> usageDirectory() async {
    final existing = await getUsage();
    if (existing != null) return existing;
    final created = PdfOptionalContentUsage();
    pdfRepresentation().put(PdfOcName.usage, created.pdfRepresentation());
    return created;
  }
}

/// A usage dictionary, ISO 32000-1, clause 8.11.4.4 (table 102).
///
/// It describes the nature of the content a group controls so that a reader
/// can set the group state automatically from outside factors: the viewing
/// magnification, the system language, whether the page is being printed, and
/// so on. The `/AS` entry of a configuration dictionary selects which of these
/// categories actually apply (table 103).
class PdfOptionalContentUsage extends PdfObjectWrapper<PdfDictionary> {
  PdfOptionalContentUsage() : super(PdfDictionary());

  PdfOptionalContentUsage.fromDictionary(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;

  // --- /CreatorInfo -----------------------------------------------------

  /// The `/CreatorInfo` `/Creator` entry: the application that made the group.
  Future<String?> getCreator() async =>
      _text(await _sub(PdfOcName.creatorInfo), PdfOcName.creator);

  /// The `/CreatorInfo` `/Subtype` entry, e.g. `/Artwork` or `/Technical`.
  Future<PdfName?> getCreatorSubtype() async =>
      (await _sub(PdfOcName.creatorInfo))?.nameEntry(PdfOcName.subtype);

  void setCreatorInfo(String creator, PdfName subtype) {
    final dict = PdfDictionary()
      ..put(PdfOcName.creator, makeOcTextString(creator))
      ..put(PdfOcName.subtype, subtype);
    pdfRepresentation().put(PdfOcName.creatorInfo, dict);
  }

  // --- /Language --------------------------------------------------------

  /// The `/Language` `/Lang` entry, e.g. `es-MX`.
  Future<String?> getLanguage() async =>
      _text(await _sub(PdfOcName.language), PdfOcName.lang);

  /// The `/Language` `/Preferred` entry; defaults to OFF, i.e. false.
  Future<bool> isLanguagePreferred() async {
    final dict = await _sub(PdfOcName.language);
    final value = await dict?.nameEntry(PdfOcName.preferred);
    return value == PdfOcName.on;
  }

  void setLanguage(String language, {bool preferred = false}) {
    final dict = PdfDictionary()
      ..put(PdfOcName.lang, makeOcTextString(language))
      ..put(PdfOcName.preferred, preferred ? PdfOcName.on : PdfOcName.off);
    pdfRepresentation().put(PdfOcName.language, dict);
  }

  // --- /Export ----------------------------------------------------------

  /// The `/Export` `/ExportState` entry, or null when it is absent.
  Future<bool?> getExportState() async =>
      _state(await _sub(PdfOcName.export), PdfOcName.exportState);

  void setExportState(bool on) {
    pdfRepresentation().put(
        PdfOcName.export,
        PdfDictionary()
          ..put(PdfOcName.exportState, on ? PdfOcName.on : PdfOcName.off));
  }

  // --- /Zoom ------------------------------------------------------------

  /// The `/Zoom` `/min` entry; defaults to 0 (table 102).
  Future<double> getZoomMin() async {
    final dict = await _sub(PdfOcName.zoom);
    return await dict?.decimalEntry(PdfOcName.min) ?? 0.0;
  }

  /// The `/Zoom` `/max` entry; defaults to infinity (table 102).
  Future<double> getZoomMax() async {
    final dict = await _sub(PdfOcName.zoom);
    return await dict?.decimalEntry(PdfOcName.max) ?? double.infinity;
  }

  void setZoom({double? min, double? max}) {
    final dict = PdfDictionary();
    if (min != null) dict.put(PdfOcName.min, PdfNumber(min));
    if (max != null && max.isFinite) dict.put(PdfOcName.max, PdfNumber(max));
    pdfRepresentation().put(PdfOcName.zoom, dict);
  }

  // --- /Print -----------------------------------------------------------

  /// The `/Print` `/Subtype` entry, e.g. `/Watermark` or `/PrintersMarks`.
  Future<PdfName?> getPrintSubtype() async =>
      (await _sub(PdfOcName.print))?.nameEntry(PdfOcName.subtype);

  /// The `/Print` `/PrintState` entry, or null when it is absent.
  ///
  /// Clause 8.11.4.4 is explicit that an absent `/PrintState` leaves the
  /// state of the group unchanged rather than forcing it OFF, which is why
  /// this returns null instead of false.
  Future<bool?> getPrintState() async =>
      _state(await _sub(PdfOcName.print), PdfOcName.printState);

  void setPrint({PdfName? subtype, bool? printState}) {
    final dict = PdfDictionary();
    if (subtype != null) dict.put(PdfOcName.subtype, subtype);
    if (printState != null) {
      dict.put(PdfOcName.printState, printState ? PdfOcName.on : PdfOcName.off);
    }
    pdfRepresentation().put(PdfOcName.print, dict);
  }

  // --- /View ------------------------------------------------------------

  /// The `/View` `/ViewState` entry, or null when it is absent.
  Future<bool?> getViewState() async =>
      _state(await _sub(PdfOcName.view), PdfOcName.viewState);

  void setViewState(bool on) {
    pdfRepresentation().put(
        PdfOcName.view,
        PdfDictionary()
          ..put(PdfOcName.viewState, on ? PdfOcName.on : PdfOcName.off));
  }

  // --- /User ------------------------------------------------------------

  /// The `/User` `/Type` entry: `/Ind`, `/Ttl` or `/Org`.
  Future<PdfName?> getUserType() async =>
      (await _sub(PdfOcName.user))?.nameEntry(PdfOcName.type);

  /// The `/User` `/Name` entry, which may be one string or an array of them.
  Future<List<String>> getUserNames() async {
    final dict = await _sub(PdfOcName.user);
    if (dict == null) return const <String>[];
    final direct = await dict.get(PdfOcName.name, true);
    if (direct is PdfString) return <String>[readOcTextString(direct)];
    if (direct is PdfArray) {
      final names = <String>[];
      for (var i = 0; i < direct.size(); i++) {
        final entry = await direct.get(i);
        if (entry is PdfString) names.add(readOcTextString(entry));
      }
      return names;
    }
    return const <String>[];
  }

  void setUser(PdfName type, List<String> names) {
    final dict = PdfDictionary()..put(PdfOcName.type, type);
    if (names.length == 1) {
      dict.put(PdfOcName.name, makeOcTextString(names.first));
    } else {
      dict.put(
          PdfOcName.name,
          PdfArray.fromList(
              names.map<PdfObject>(makeOcTextString).toList(growable: false)));
    }
    pdfRepresentation().put(PdfOcName.user, dict);
  }

  // --- /PageElement -----------------------------------------------------

  /// The `/PageElement` `/Subtype` entry: `/HF`, `/FG`, `/BG` or `/L`.
  Future<PdfName?> getPageElementSubtype() async =>
      (await _sub(PdfOcName.pageElement))?.nameEntry(PdfOcName.subtype);

  void setPageElement(PdfName subtype) {
    pdfRepresentation().put(PdfOcName.pageElement,
        PdfDictionary()..put(PdfOcName.subtype, subtype));
  }

  Future<PdfDictionary?> _sub(PdfName key) =>
      pdfRepresentation().dictionaryEntry(key);

  static Future<String?> _text(PdfDictionary? dict, PdfName key) async {
    final value = await dict?.stringEntry(key);
    return value == null ? null : readOcTextString(value);
  }

  /// Reads an ON/OFF name entry as a tri-state: true, false or absent.
  static Future<bool?> _state(PdfDictionary? dict, PdfName key) async {
    final value = await dict?.nameEntry(key);
    if (value == PdfOcName.on) return true;
    if (value == PdfOcName.off) return false;
    return null;
  }
}
