import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_string.dart';
import 'pdf_stream.dart';
import 'pdf_object_wrapper.dart';

/// An output intent dictionary.
///
/// ISO 32000-1:2008, 14.11.5 "Output Intents", Table 365. The document
/// catalogue holds an array of them in `/OutputIntents`; each one describes the
/// colour reproduction characteristics of one target output device or
/// production condition.
class PdfOutputIntent extends PdfObjectWrapper<PdfDictionary> {
  /// `/S` for the PDF/X family of ISO 15930.
  static final PdfName gtsPdfX = PdfName.intern('GTS_PDFX');

  /// `/S` for PDF/A as defined by ISO 19005.
  static final PdfName gtsPdfA1 = PdfName.intern('GTS_PDFA1');

  /// `/S` for PDF/E as defined by ISO 24517.
  static final PdfName isoPdfE1 = PdfName.intern('ISO_PDFE1');

  /// The three output intent subtypes ISO 32000-1 defines. "Other subtypes may
  /// be added in the future", so an unlisted name is not by itself an error.
  static List<PdfName> get standardSubtypes => [gtsPdfX, gtsPdfA1, isoPdfE1];

  /// `/Info`.
  static final PdfName info = PdfName.intern('Info');

  PdfOutputIntent(super.pdfObject);

  factory PdfOutputIntent.create(
    String outputConditionIdentifier,
    String? outputCondition,
    String? registryName,
    String? info,
    PdfStream? destOutputProfile, {
    PdfName? subtype,
  }) {
    final dict = PdfDictionary();
    dict.put(PdfName.type, PdfName.outputIntent);
    dict.put(PdfName.s, subtype ?? PdfName.gts_pdfa1);
    dict.put(PdfName.outputConditionIdentifier,
        PdfString(outputConditionIdentifier));

    if (outputCondition != null) {
      dict.put(PdfName.outputCondition, PdfString(outputCondition));
    }
    if (registryName != null) {
      dict.put(PdfName.registryName, PdfString(registryName));
    }
    if (info != null) {
      dict.put(PdfName.intern('Info'), PdfString(info));
    }
    if (destOutputProfile != null) {
      dict.put(PdfName.destOutputProfile, destOutputProfile);
    }

    return PdfOutputIntent(dict);
  }

  /// Creates a PDF/X output intent, `/S /GTS_PDFX`.
  factory PdfOutputIntent.pdfX(
    String outputConditionIdentifier, {
    String? outputCondition,
    String? registryName,
    String? info,
    PdfStream? destOutputProfile,
  }) =>
      PdfOutputIntent.create(outputConditionIdentifier, outputCondition,
          registryName, info, destOutputProfile,
          subtype: gtsPdfX);

  /// Creates a PDF/A output intent, `/S /GTS_PDFA1`.
  factory PdfOutputIntent.pdfA1(
    String outputConditionIdentifier, {
    String? outputCondition,
    String? registryName,
    String? info,
    PdfStream? destOutputProfile,
  }) =>
      PdfOutputIntent.create(outputConditionIdentifier, outputCondition,
          registryName, info, destOutputProfile,
          subtype: gtsPdfA1);

  /// Creates a PDF/E output intent, `/S /ISO_PDFE1`.
  factory PdfOutputIntent.pdfE1(
    String outputConditionIdentifier, {
    String? outputCondition,
    String? registryName,
    String? info,
    PdfStream? destOutputProfile,
  }) =>
      PdfOutputIntent.create(outputConditionIdentifier, outputCondition,
          registryName, info, destOutputProfile,
          subtype: isoPdfE1);

  @override
  bool requiresIndirectStorage() => true;

  /// Sets `/S`, the output intent subtype.
  PdfOutputIntent setSubtype(PdfName subtype) {
    pdfRepresentation().put(PdfName.s, subtype);
    markChanged();
    return this;
  }

  /// Gets `/S`.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Sets `/OutputConditionIdentifier`, the required identifier of the
  /// intended output device or production condition.
  PdfOutputIntent setOutputConditionIdentifier(String identifier) {
    pdfRepresentation()
        .put(PdfName.outputConditionIdentifier, PdfString(identifier));
    markChanged();
    return this;
  }

  /// Gets `/OutputConditionIdentifier`.
  Future<String?> getOutputConditionIdentifier() async =>
      (await pdfRepresentation().stringEntry(PdfName.outputConditionIdentifier))
          ?.decodeMappingText();

  /// Sets `/OutputCondition`, the human-readable description of the condition.
  PdfOutputIntent setOutputCondition(String condition) {
    pdfRepresentation().put(PdfName.outputCondition, PdfString(condition));
    markChanged();
    return this;
  }

  /// Gets `/OutputCondition`.
  Future<String?> getOutputCondition() async =>
      (await pdfRepresentation().stringEntry(PdfName.outputCondition))
          ?.decodeMappingText();

  /// Sets `/RegistryName`, "conventionally a uniform resource identifier"
  /// naming the registry that defines the output condition.
  PdfOutputIntent setRegistryName(String registry) {
    pdfRepresentation().put(PdfName.registryName, PdfString(registry));
    markChanged();
    return this;
  }

  /// Gets `/RegistryName`.
  Future<String?> getRegistryName() async =>
      (await pdfRepresentation().stringEntry(PdfName.registryName))
          ?.decodeMappingText();

  /// Sets `/Info`, further human-readable identification of the target.
  PdfOutputIntent setInfo(String value) {
    pdfRepresentation().put(info, PdfString(value));
    markChanged();
    return this;
  }

  /// Gets `/Info`.
  Future<String?> getInfo() async =>
      (await pdfRepresentation().stringEntry(info))?.decodeMappingText();

  /// Sets `/DestOutputProfile`, the ICC profile stream in the format of an
  /// ICCBased colour space (8.6.5.5).
  PdfOutputIntent setDestOutputProfile(PdfStream profile) {
    pdfRepresentation().put(PdfName.destOutputProfile, profile);
    markChanged();
    return this;
  }

  /// Gets `/DestOutputProfile`.
  Future<PdfStream?> getDestOutputProfile() async =>
      await pdfRepresentation().streamEntry(PdfName.destOutputProfile);

  /// Whether `/OutputConditionIdentifier` names a standard production
  /// condition.
  ///
  /// Table 365 keys the two conditional requirements on this: when the
  /// identifier is not a standard condition, `/Info` and `/DestOutputProfile`
  /// become required. The specification gives `Custom` as the value used for a
  /// condition that is not a recognised standard, and
  /// [nonStandardConditionIdentifiers] lists the identifiers treated that way.
  Future<bool> namesStandardCondition() async {
    final identifier = await getOutputConditionIdentifier();
    if (identifier == null) return false;
    return !nonStandardConditionIdentifiers
        .contains(identifier.trim().toLowerCase());
  }

  /// The `/OutputConditionIdentifier` values that mean "not a recognized
  /// standard" in Table 365, compared case-insensitively.
  static const Set<String> nonStandardConditionIdentifiers = {'custom'};

  /// Reports every way in which this dictionary departs from Table 365.
  ///
  /// An empty list means the dictionary conforms. The two conditional entries
  /// are required only when `/OutputConditionIdentifier` does not name a
  /// standard production condition, which is decided by
  /// [namesStandardCondition].
  Future<List<String>> validate() async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    final type = await dictionary.nameEntry(PdfName.type);
    if (dictionary.containsKey(PdfName.type) &&
        (type == null || type.getValue() != 'OutputIntent')) {
      problems.add('/Type shall be /OutputIntent when present (Table 365)');
    }

    final subtype = await getSubtype();
    if (subtype == null) {
      problems.add('/S is required in an output intent dictionary (Table 365)');
    }

    final identifier = await getOutputConditionIdentifier();
    if (identifier == null) {
      problems.add('/OutputConditionIdentifier is required in an output intent '
          'dictionary (Table 365)');
    }

    for (final key in [PdfName.outputCondition, PdfName.registryName, info]) {
      if (dictionary.containsKey(key) &&
          await dictionary.stringEntry(key) == null) {
        problems.add('/${key.getValue()} shall be a text string (Table 365)');
      }
    }

    if (dictionary.containsKey(PdfName.destOutputProfile) &&
        await getDestOutputProfile() == null) {
      problems.add('/DestOutputProfile shall be an ICC profile stream '
          '(Table 365)');
    }

    if (identifier != null && !await namesStandardCondition()) {
      if (await getInfo() == null) {
        problems.add('/Info is required when /OutputConditionIdentifier does '
            'not name a standard production condition (Table 365)');
      }
      if (await getDestOutputProfile() == null) {
        problems.add('/DestOutputProfile is required when '
            '/OutputConditionIdentifier does not name a standard production '
            'condition (Table 365)');
      }
    }

    return problems;
  }
}
