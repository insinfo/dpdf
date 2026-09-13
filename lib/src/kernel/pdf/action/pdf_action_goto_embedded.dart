import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'package:dpdf/src/kernel/pdf/navigation/pdf_destination.dart';
import 'pdf_action.dart';

/// Target dictionary of an embedded go-to action.
///
/// See ISO 32000-1:2008, 12.6.4.4, Table 202.
class PdfTargetDictionary extends PdfObjectWrapper<PdfDictionary> {
  /// `/R` value: the target is the parent of the current document.
  static final PdfName relationshipParent = PdfName.intern('P');

  /// `/R` value: the target is a child of the current document.
  static final PdfName relationshipChild = PdfName.intern('C');

  PdfTargetDictionary(super.pdfObject);

  PdfTargetDictionary._(PdfName relationship) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.r, relationship);
  }

  /// Creates a target dictionary pointing at the parent document (`/R /P`).
  factory PdfTargetDictionary.parent() =>
      PdfTargetDictionary._(relationshipParent);

  /// Creates a target dictionary pointing at a child embedded in the
  /// `EmbeddedFiles` name tree under [name] (`/R /C` with `/N`).
  factory PdfTargetDictionary.childByName(String name) {
    final target = PdfTargetDictionary._(relationshipChild);
    target.pdfRepresentation().put(PdfName.n, PdfString(name));
    return target;
  }

  /// Creates a target dictionary pointing at a child attached to a file
  /// attachment annotation identified by page [pageIndex] (zero based) and
  /// annotation [annotationIndex] in the page's `/Annots` array.
  factory PdfTargetDictionary.childByAnnotationIndex(
      int pageIndex, int annotationIndex) {
    final target = PdfTargetDictionary._(relationshipChild);
    target.pdfRepresentation().put(PdfName.p, PdfNumber.fromInt(pageIndex));
    target
        .pdfRepresentation()
        .put(PdfName.a, PdfNumber.fromInt(annotationIndex));
    return target;
  }

  /// Creates a target dictionary pointing at a child attached to a file
  /// attachment annotation identified by the named destination [destination]
  /// and the annotation's `/NM` value [annotationName].
  factory PdfTargetDictionary.childByAnnotationName(
      String destination, String annotationName) {
    final target = PdfTargetDictionary._(relationshipChild);
    target.pdfRepresentation().put(PdfName.p, PdfString(destination));
    target.pdfRepresentation().put(PdfName.a, PdfString(annotationName));
    return target;
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/R`, the relationship between the current document and the target.
  Future<PdfName?> getRelationship() async =>
      await pdfRepresentation().nameEntry(PdfName.r);

  /// Gets `/N`, the name of the file in the `EmbeddedFiles` name tree.
  Future<String?> getEmbeddedFileName() async =>
      (await pdfRepresentation().stringEntry(PdfName.n))?.getValue();

  /// Sets `/T`, a nested target dictionary adding another path element.
  PdfTargetDictionary setTarget(PdfTargetDictionary nested) {
    pdfRepresentation().put(PdfName.t, nested.pdfRepresentation());
    return this;
  }

  /// Gets `/T`.
  Future<PdfTargetDictionary?> getTarget() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.t);
    return dictionary == null ? null : PdfTargetDictionary(dictionary);
  }
}

/// Embedded go-to action, jumping to or from a PDF file embedded in another.
///
/// See ISO 32000-1:2008, 12.6.4.4, Table 201.
class PdfActionGoToEmbedded extends PdfAction {
  PdfActionGoToEmbedded(super.pdfObject);

  /// Creates a `/GoToE` action. `/D` is required; Table 201 makes `/T`
  /// required whenever `/F` is absent, which this constructor enforces.
  PdfActionGoToEmbedded.create(PdfDestination destination,
      {PdfFileSpec? file, PdfTargetDictionary? target, bool? newWindow})
      : super.ofType(PdfName.goToE) {
    if (file == null && target == null) {
      throw ArgumentError(
          'Embedded go-to actions require /T when /F is absent (Table 201)');
    }
    setDestination(destination);
    if (file != null) setFile(file);
    if (target != null) setTarget(target);
    if (newWindow != null) setNewWindow(newWindow);
  }

  /// Sets `/D`, the destination in the target document.
  PdfActionGoToEmbedded setDestination(PdfDestination destination) {
    pdfRepresentation().put(PdfName.d, destination.pdfRepresentation());
    return this;
  }

  /// Gets `/D` as written.
  Future<PdfObject?> getDestination() async =>
      await pdfRepresentation().get(PdfName.d, true);

  /// Sets `/F`, the root document of the target relative to the source root.
  PdfActionGoToEmbedded setFile(PdfFileSpec file) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
    return this;
  }

  /// Gets `/F` as written.
  Future<PdfObject?> getFile() async =>
      await pdfRepresentation().get(PdfName.f, true);

  /// Sets `/T`, the target dictionary giving the path to the target document.
  PdfActionGoToEmbedded setTarget(PdfTargetDictionary target) {
    pdfRepresentation().put(PdfName.t, target.pdfRepresentation());
    return this;
  }

  /// Gets `/T`.
  Future<PdfTargetDictionary?> getTarget() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.t);
    return dictionary == null ? null : PdfTargetDictionary(dictionary);
  }

  /// Sets `/NewWindow`.
  PdfActionGoToEmbedded setNewWindow(bool newWindow) {
    pdfRepresentation().put(PdfName.intern('NewWindow'), PdfBoolean(newWindow));
    return this;
  }

  /// Gets `/NewWindow`; null means the reader follows its own preference.
  Future<bool?> getNewWindow() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('NewWindow')))
          ?.getValue();
}
