import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'pdf_action.dart';

/// Windows launch parameter dictionary.
///
/// See ISO 32000-1:2008, 12.6.4.5, Table 204.
class PdfWindowsLaunchParameters extends PdfObjectWrapper<PdfDictionary> {
  /// `/O` value: open a document.
  static const String operationOpen = 'open';

  /// `/O` value: print a document.
  static const String operationPrint = 'print';

  PdfWindowsLaunchParameters(super.pdfObject);

  /// Creates the dictionary with the required `/F` file name. Table 204
  /// states that this value is a simple string, not a file specification.
  PdfWindowsLaunchParameters.create(String fileName) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.f, PdfString(fileName));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/F`.
  Future<String?> getFileName() async =>
      (await pdfRepresentation().stringEntry(PdfName.f))?.getValue();

  /// Sets `/D`, the default directory in standard DOS syntax.
  PdfWindowsLaunchParameters setDirectory(String directory) {
    pdfRepresentation().put(PdfName.d, PdfString(directory));
    return this;
  }

  /// Sets `/O`, the operation to perform ([operationOpen] or
  /// [operationPrint]).
  PdfWindowsLaunchParameters setOperation(String operation) {
    if (operation != operationOpen && operation != operationPrint) {
      throw ArgumentError.value(operation, 'operation',
          'Windows launch /O shall be "open" or "print"');
    }
    pdfRepresentation().put(PdfName.o, PdfString(operation));
    return this;
  }

  /// Gets `/O`; the default is [operationOpen] per Table 204.
  Future<String> getOperation() async =>
      (await pdfRepresentation().stringEntry(PdfName.o))?.getValue() ??
      operationOpen;

  /// Sets `/P`, the parameter string passed to the application.
  PdfWindowsLaunchParameters setParameters(String parameters) {
    pdfRepresentation().put(PdfName.p, PdfString(parameters));
    return this;
  }
}

/// Launch action, launching an application or opening/printing a document.
///
/// See ISO 32000-1:2008, 12.6.4.5, Table 203.
class PdfActionLaunch extends PdfAction {
  PdfActionLaunch(super.pdfObject);

  /// Creates a `/Launch` action with the `/F` file specification, required
  /// whenever none of `/Win`, `/Mac` or `/Unix` is present.
  PdfActionLaunch.create(PdfFileSpec file, {bool? newWindow})
      : super.ofType(PdfName.launch) {
    setFile(file);
    if (newWindow != null) setNewWindow(newWindow);
  }

  /// Creates a `/Launch` action carrying only Windows-specific parameters.
  PdfActionLaunch.windows(PdfWindowsLaunchParameters parameters)
      : super.ofType(PdfName.launch) {
    setWindowsParameters(parameters);
  }

  /// Sets `/F`, the application launched or the document opened or printed.
  PdfActionLaunch setFile(PdfFileSpec file) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
    return this;
  }

  /// Gets `/F` as written.
  Future<PdfObject?> getFile() async =>
      await pdfRepresentation().get(PdfName.f, true);

  /// Sets `/Win`, the Windows-specific launch parameters (Table 204).
  PdfActionLaunch setWindowsParameters(PdfWindowsLaunchParameters parameters) {
    pdfRepresentation()
        .put(PdfName.intern('Win'), parameters.pdfRepresentation());
    return this;
  }

  /// Gets `/Win`.
  Future<PdfWindowsLaunchParameters?> getWindowsParameters() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('Win'));
    return dictionary == null ? null : PdfWindowsLaunchParameters(dictionary);
  }

  /// Sets `/NewWindow`.
  PdfActionLaunch setNewWindow(bool newWindow) {
    pdfRepresentation().put(PdfName.intern('NewWindow'), PdfBoolean(newWindow));
    return this;
  }

  /// Gets `/NewWindow`; null means the reader follows its own preference.
  Future<bool?> getNewWindow() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('NewWindow')))
          ?.getValue();
}
