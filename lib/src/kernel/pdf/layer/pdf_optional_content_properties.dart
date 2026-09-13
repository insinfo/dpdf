import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_config.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_group.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_name.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_state.dart';

/// The `/OCProperties` dictionary of the document catalog, ISO 32000-1,
/// clause 8.11.4.2 (table 100).
///
/// It lists every optional content group of the document and carries the
/// default configuration `/D` plus any alternates in `/Configs`. A document
/// that uses optional content must have it: clause 8.11.4.2 tells readers to
/// ignore every optional content structure when it is missing.
class PdfOptionalContentProperties extends PdfObjectWrapper<PdfDictionary> {
  /// Creates an empty properties dictionary with an empty default
  /// configuration, ready for groups to be added.
  PdfOptionalContentProperties() : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfOcName.ocgs, PdfArray())
      ..put(PdfOcName.d, PdfDictionary());
  }

  PdfOptionalContentProperties.fromDictionary(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;

  /// Reads `/OCProperties` from a catalog dictionary; null when absent.
  static Future<PdfOptionalContentProperties?> fromCatalog(
      PdfDictionary catalog) async {
    final dict = await catalog.dictionaryEntry(PdfOcName.ocProperties);
    if (dict == null) return null;
    return PdfOptionalContentProperties.fromDictionary(dict);
  }

  /// Reads the `/OCProperties` of [document]; null when it has none.
  static Future<PdfOptionalContentProperties?> fromDocument(
      PdfDocument document) {
    return fromCatalog(document.rootCatalog().pdfRepresentation());
  }

  /// Returns the `/OCProperties` of [document], creating and attaching it to
  /// the catalog when the document does not have one yet.
  static Future<PdfOptionalContentProperties> forDocument(
      PdfDocument document) async {
    final existing = await fromDocument(document);
    if (existing != null) return existing;
    final created = PdfOptionalContentProperties();
    document
        .rootCatalog()
        .pdfRepresentation()
        .put(PdfOcName.ocProperties, created.pdfRepresentation());
    return created;
  }

  /// The `/OCGs` array: every group in the document.
  Future<List<PdfDictionary>> getGroups() async {
    return PdfUsageApplication.readGroupArray(
        await pdfRepresentation().arrayEntry(PdfOcName.ocgs));
  }

  /// Registers [group] in `/OCGs`, ignoring a group that is already there.
  ///
  /// The group must be an indirect object (table 100 requires references), so
  /// callers building a document should attach it first.
  Future<void> addGroup(PdfOptionalContentGroup group) async {
    var array = await pdfRepresentation().arrayEntry(PdfOcName.ocgs);
    if (array == null) {
      array = PdfArray();
      pdfRepresentation().put(PdfOcName.ocgs, array);
    }
    final key = PdfOptionalContentState.keyOf(group.pdfRepresentation());
    for (final existing in await getGroups()) {
      if (PdfOptionalContentState.keyOf(existing) == key) return;
    }
    final reference = group.pdfRepresentation().indirectHandle();
    array.add(reference ?? group.pdfRepresentation());
    markChanged();
  }

  /// The `/D` default configuration, created empty when the file omits it.
  Future<PdfOptionalContentConfiguration> getDefaultConfiguration() async {
    var dict = await pdfRepresentation().dictionaryEntry(PdfOcName.d);
    if (dict == null) {
      dict = PdfDictionary();
      pdfRepresentation().put(PdfOcName.d, dict);
    }
    return PdfOptionalContentConfiguration.fromDictionary(dict);
  }

  /// The alternate configurations of `/Configs`.
  Future<List<PdfOptionalContentConfiguration>>
      getAlternateConfigurations() async {
    final array = await pdfRepresentation().arrayEntry(PdfOcName.configs);
    if (array == null) return const <PdfOptionalContentConfiguration>[];
    final configs = <PdfOptionalContentConfiguration>[];
    for (var i = 0; i < array.size(); i++) {
      final dict = await array.dictionaryEntry(i);
      if (dict != null) {
        configs.add(PdfOptionalContentConfiguration.fromDictionary(dict));
      }
    }
    return configs;
  }

  /// Appends [configuration] to `/Configs`.
  void addAlternateConfiguration(
      PdfOptionalContentConfiguration configuration) {
    final existing = pdfRepresentation().getMap()?[PdfOcName.configs];
    PdfArray array;
    if (existing is PdfArray) {
      array = existing;
    } else {
      array = PdfArray();
      pdfRepresentation().put(PdfOcName.configs, array);
    }
    array.add(configuration.pdfRepresentation());
    markChanged();
  }

  /// Resolves the ON/OFF state of every group under [configuration], or under
  /// the default configuration when none is given (clause 8.11.4.5).
  Future<PdfOptionalContentState> resolveState(
      {PdfOptionalContentConfiguration? configuration}) async {
    final config = configuration ?? await getDefaultConfiguration();
    return PdfOptionalContentState.fromConfiguration(config, await getGroups());
  }

  /// Whether [object] is a group or a membership dictionary this document
  /// would treat as optional content.
  static Future<bool> isOptionalContent(PdfObject? object) async {
    final dict = await PdfOptionalContentGroup.resolveDictionary(object);
    if (dict == null) return false;
    final type = await dict.nameEntry(PdfOcName.type);
    return type == PdfOcName.ocg || type == PdfOcName.ocmd;
  }
}
