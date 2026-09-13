import '../../exceptions/pdf_exception.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// The integer valued entries of a legal attestation dictionary
/// (ISO 32000-1:2008, 12.8.5, Table 259). Each counts occurrences of a
/// construct that may make the rendered appearance of the document vary.
enum PdfLegalAttestationEntry {
  /// `/JavaScriptActions`.
  javaScriptActions('JavaScriptActions'),

  /// `/LaunchActions`.
  launchActions('LaunchActions'),

  /// `/URIActions`.
  uriActions('URIActions'),

  /// `/MovieActions`.
  movieActions('MovieActions'),

  /// `/SoundActions`.
  soundActions('SoundActions'),

  /// `/HideAnnotationActions`.
  hideAnnotationActions('HideAnnotationActions'),

  /// `/GoToRemoteActions`.
  goToRemoteActions('GoToRemoteActions'),

  /// `/AlternateImages`.
  alternateImages('AlternateImages'),

  /// `/ExternalStreams`.
  externalStreams('ExternalStreams'),

  /// `/TrueTypeFonts`.
  trueTypeFonts('TrueTypeFonts'),

  /// `/ExternalRefXobjects`.
  externalRefXobjects('ExternalRefXobjects'),

  /// `/ExternalOPIdicts`.
  externalOPIdicts('ExternalOPIdicts'),

  /// `/NonEmbeddedFonts`.
  nonEmbeddedFonts('NonEmbeddedFonts'),

  /// `/DevDepGS_OP`, device dependent overprint settings.
  devDepGsOP('DevDepGS_OP'),

  /// `/DevDepGS_HT`, device dependent halftone settings.
  devDepGsHT('DevDepGS_HT'),

  /// `/DevDepGS_TR`, device dependent transfer functions.
  devDepGsTR('DevDepGS_TR'),

  /// `/DevDepGS_UCR`, device dependent undercolour removal.
  devDepGsUCR('DevDepGS_UCR'),

  /// `/DevDepGS_BG`, device dependent black generation.
  devDepGsBG('DevDepGS_BG'),

  /// `/DevDepGS_FL`, device dependent flatness tolerance.
  devDepGsFL('DevDepGS_FL'),

  /// `/Annotations`.
  annotations('Annotations');

  const PdfLegalAttestationEntry(this.pdfName);

  /// The key written to the PDF file.
  final String pdfName;

  /// The entry key as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);
}

/// The legal attestation dictionary of ISO 32000-1:2008, 12.8.5, Table 259.
///
/// It is the value of `/Legal` in the document catalog (Table 28) and records
/// all content that may result in unexpected rendering of the document, so a
/// recipient of a certification signature can review it.
class PdfLegalAttestation extends PdfObjectWrapper<PdfDictionary> {
  /// `/OptionalContent`.
  static final PdfName optionalContent = PdfName.intern('OptionalContent');

  /// `/Attestation`.
  static final PdfName attestation = PdfName.intern('Attestation');

  /// Wraps [dictionary], or starts an empty legal attestation dictionary.
  PdfLegalAttestation([PdfDictionary? dictionary])
      : super(dictionary ?? PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets one of the Table 259 counters. A count is a number of occurrences,
  /// so a negative value is rejected.
  PdfLegalAttestation setCount(PdfLegalAttestationEntry entry, int count) {
    if (count < 0) {
      throw PdfException(
          '/${entry.pdfName} counts occurrences and cannot be $count.');
    }
    pdfRepresentation().put(entry.toPdfName(), PdfNumber.fromInt(count));
    markChanged();
    return this;
  }

  /// Gets one of the Table 259 counters, or `null` when the entry is absent.
  Future<int?> getCount(PdfLegalAttestationEntry entry) async {
    return (await pdfRepresentation().numberEntry(entry.toPdfName()))
        ?.intValue();
  }

  /// Sets `/OptionalContent`: the document contains optional content.
  PdfLegalAttestation setOptionalContent(bool value) {
    pdfRepresentation().put(optionalContent, PdfBoolean(value));
    markChanged();
    return this;
  }

  /// Gets `/OptionalContent`, defaulting to `false`.
  Future<bool> getOptionalContent() async {
    return (await pdfRepresentation().booleanEntry(optionalContent))
            ?.getValue() ??
        false;
  }

  /// Sets `/Attestation`, the author's clarification of the listed content.
  PdfLegalAttestation setAttestation(String text) {
    pdfRepresentation().put(attestation, PdfString(text));
    markChanged();
    return this;
  }

  /// Gets `/Attestation`, or `null` when the entry is absent.
  Future<String?> getAttestation() async {
    return (await pdfRepresentation().stringEntry(attestation))
        ?.decodeMappingText();
  }
}
