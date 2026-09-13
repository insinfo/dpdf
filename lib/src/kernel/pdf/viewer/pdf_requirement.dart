import '../../exceptions/pdf_exception.dart';
import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// Values of `/S` in a requirement handler dictionary (ISO 32000-1:2008,
/// 12.10.2, Table 265).
enum PdfRequirementHandlerType {
  /// `/JS`, a JavaScript requirement handler. It names the segment to disable
  /// through `/Script`.
  javaScript('JS'),

  /// `/NoOp`, which lets older conforming readers ignore a requirement they do
  /// not recognize. It adds no further entry.
  noOp('NoOp');

  const PdfRequirementHandlerType(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The handler type as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves an `/S` value, or `null` when unrecognized.
  static PdfRequirementHandlerType? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// A requirement handler dictionary of ISO 32000-1:2008, 12.10.2, Table 265.
///
/// A requirement handler is a program, normally a JavaScript segment, that
/// verifies a requirement itself. A reader that understands the parent
/// requirement disables the handlers the requirement lists, so the check does
/// not happen twice.
class PdfRequirementHandler extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a requirement handler dictionary.
  static final PdfName reqHandler = PdfName.intern('ReqHandler');

  /// `/S`, the handler type.
  static final PdfName handlerType = PdfName.intern('S');

  /// `/Script`, the name of a document level JavaScript action.
  static final PdfName script = PdfName.intern('Script');

  /// Wraps an existing requirement handler dictionary.
  PdfRequirementHandler(super.pdfObject);

  /// Creates a handler of the given type, with `/Type /ReqHandler` and the
  /// required `/S`.
  PdfRequirementHandler.create(PdfRequirementHandlerType type)
      : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, reqHandler);
    pdfRepresentation().put(handlerType, type.toPdfName());
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/S`, or `null` when the required entry is missing or unrecognized.
  Future<PdfRequirementHandlerType?> getHandlerType() async {
    return PdfRequirementHandlerType.fromPdfName(
        await pdfRepresentation().nameEntry(handlerType));
  }

  /// Sets `/Script`, the name under which the JavaScript segment is registered
  /// in the document name dictionary (7.7.4).
  ///
  /// Table 265 allows `/Script` only when `/S` is `/JS`.
  Future<PdfRequirementHandler> setScript(String name) async {
    final type = await getHandlerType();
    if (type != PdfRequirementHandlerType.javaScript) {
      throw PdfException(
          '/Script is valid only when /S is /JS, not /${type?.pdfName}.');
    }
    pdfRepresentation().put(script, PdfString(name));
    markChanged();
    return this;
  }

  /// Gets `/Script`, or `null` when absent.
  Future<String?> getScript() async {
    return (await pdfRepresentation().stringEntry(script))?.decodeMappingText();
  }
}

/// A requirement dictionary of ISO 32000-1:2008, 12.10.1, Table 264.
///
/// The `/Requirements` array of the document catalog lists what a conforming
/// reader shall provide for the document to function properly. PDF 1.7 defines
/// exactly one requirement type, `/EnableJavaScripts`.
class PdfRequirement extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a requirement dictionary.
  static final PdfName requirement = PdfName.intern('Requirement');

  /// `/S`, the type of requirement.
  static final PdfName requirementType = PdfName.intern('S');

  /// `/RH`, the requirement handlers to disable.
  static final PdfName handlers = PdfName.intern('RH');

  /// `/EnableJavaScripts`, the only requirement type defined in PDF 1.7.
  static final PdfName enableJavaScripts = PdfName.intern('EnableJavaScripts');

  /// `/Requirements`, the catalog key holding the array of requirements.
  static final PdfName requirementsKey = PdfName.intern('Requirements');

  /// Wraps an existing requirement dictionary.
  PdfRequirement(super.pdfObject);

  /// Creates a requirement of the given `/S` type, with `/Type /Requirement`.
  PdfRequirement.ofType(PdfName type) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, requirement);
    pdfRepresentation().put(requirementType, type);
  }

  /// Creates the `/EnableJavaScripts` requirement, the only type 12.10.1
  /// defines: the document needs JavaScript execution enabled.
  PdfRequirement.forJavaScripts() : this.ofType(enableJavaScripts);

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/S`, or `null` when the required entry is missing.
  Future<PdfName?> getRequirementType() =>
      pdfRepresentation().nameEntry(requirementType);

  /// Adds a handler to `/RH`, the array of requirement handlers a reader that
  /// checks this requirement itself shall disable.
  ///
  /// 12.10.1 states that `/RH` shall not be used in PDF 1.7: the only
  /// requirement defined there is `/EnableJavaScripts`, and a JavaScript
  /// segment cannot meaningfully verify that JavaScript is enabled. Adding a
  /// handler to that requirement is therefore rejected.
  Future<PdfRequirement> addHandler(PdfRequirementHandler handler) async {
    final type = await getRequirementType();
    if (type == enableJavaScripts) {
      throw PdfException(
          '12.10.1 forbids /RH on the /EnableJavaScripts requirement: a '
          'JavaScript segment cannot verify that JavaScript is enabled.');
    }
    var array = await pdfRepresentation().arrayEntry(handlers);
    if (array == null) {
      array = PdfArray();
      pdfRepresentation().put(handlers, array);
    }
    array.add(handler.pdfRepresentation());
    array.markChanged();
    markChanged();
    return this;
  }

  /// Gets the handlers listed in `/RH`, in order. An empty list means the
  /// requirement disables no handler.
  Future<List<PdfRequirementHandler>> getHandlers() async {
    final array = await pdfRepresentation().arrayEntry(handlers);
    if (array == null) return const [];
    final result = <PdfRequirementHandler>[];
    for (var index = 0; index < array.size(); index++) {
      final entry = await array.dictionaryEntry(index);
      if (entry != null) result.add(PdfRequirementHandler(entry));
    }
    return result;
  }

  /// Checks the requirement against Table 264: `/S` shall be present, and an
  /// `/EnableJavaScripts` requirement shall carry no `/RH`.
  Future<void> validate() async {
    final type = await getRequirementType();
    if (type == null) {
      throw PdfException(
          'Table 264 requires /S, the type of requirement described.');
    }
    if (type == enableJavaScripts &&
        pdfRepresentation().containsKey(handlers)) {
      throw PdfException(
          '12.10.1 forbids /RH on the /EnableJavaScripts requirement.');
    }
  }
}
