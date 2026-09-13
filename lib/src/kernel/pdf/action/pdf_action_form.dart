import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'pdf_action.dart';

/// Flags of a submit-form action.
///
/// See ISO 32000-1:2008, 12.7.5.2, Table 237. Bit positions are numbered
/// from 1, so every constant is `1 << (bit - 1)`.
abstract final class PdfSubmitFormFlags {
  /// Bit 1: the `/Fields` array excludes instead of includes.
  static const int exclude = 1;

  /// Bit 2: submit fields that carry no value.
  static const int includeNoValueFields = 1 << 1;

  /// Bit 3: submit in HTML Form format instead of FDF.
  static const int exportFormat = 1 << 2;

  /// Bit 4: submit with HTTP GET instead of POST.
  static const int getMethod = 1 << 3;

  /// Bit 5: submit the coordinates of the mouse click.
  static const int submitCoordinates = 1 << 4;

  /// Bit 6: submit as XFDF.
  static const int xfdf = 1 << 5;

  /// Bit 7: include incremental updates in the submitted FDF.
  static const int includeAppendSaves = 1 << 6;

  /// Bit 8: include markup annotations in the submitted FDF.
  static const int includeAnnotations = 1 << 7;

  /// Bit 9: submit the whole document as PDF.
  static const int submitPdf = 1 << 8;

  /// Bit 10: convert submitted date values to the standard format.
  static const int canonicalFormat = 1 << 9;

  /// Bit 11: include only the current user's markup annotations.
  static const int excludeNonUserAnnotations = 1 << 10;

  /// Bit 12: exclude the `/F` entry from the submitted FDF.
  static const int excludeFKey = 1 << 11;

  /// Bit 14: embed the source PDF in the submitted FDF's `/F` entry.
  static const int embedForm = 1 << 13;
}

/// Flag of a reset-form action.
///
/// See ISO 32000-1:2008, 12.7.5.3, Table 239.
abstract final class PdfResetFormFlags {
  /// Bit 1: the `/Fields` array excludes instead of includes.
  static const int exclude = 1;
}

/// Shared `/Fields` handling of the submit-form and reset-form actions.
abstract class PdfFormAction extends PdfAction {
  PdfFormAction(super.pdfObject);

  PdfFormAction.ofType(super.actionType) : super.ofType();

  /// Sets `/Fields`. Every element is either an indirect reference to a field
  /// dictionary or a text string with a fully qualified field name; both
  /// kinds may be mixed in the same array (Tables 236 and 238).
  PdfFormAction setFields(List<PdfObject> fields) {
    pdfRepresentation().put(PdfName.fields, PdfArray.fromList(fields));
    return this;
  }

  /// Sets `/Fields` from fully qualified field names.
  PdfFormAction setFieldNames(List<String> names) {
    return setFields([for (final name in names) PdfString(name)]);
  }

  /// Gets `/Fields`.
  Future<PdfArray?> getFields() async =>
      await pdfRepresentation().arrayEntry(PdfName.fields);

  /// Sets `/Flags`.
  PdfFormAction setFlags(int flags) {
    if (flags < 0) {
      throw ArgumentError.value(
          flags, 'flags', 'Form action /Flags shall be non-negative');
    }
    pdfRepresentation().put(PdfName.flags, PdfNumber.fromInt(flags));
    return this;
  }

  /// Gets `/Flags`; the default is 0.
  Future<int> getFlags() async =>
      await pdfRepresentation().integerEntry(PdfName.flags) ?? 0;

  /// True when [flag] is set in `/Flags`.
  Future<bool> hasFlag(int flag) async => (await getFlags()) & flag != 0;
}

/// Submit-form action.
///
/// See ISO 32000-1:2008, 12.7.5.2, Table 236.
class PdfActionSubmitForm extends PdfFormAction {
  PdfActionSubmitForm(super.pdfObject);

  /// Creates a `/SubmitForm` action. `/F` is required by Table 236 and shall
  /// be a URL file specification (7.11.5).
  PdfActionSubmitForm.create(String url, {List<String>? fieldNames, int? flags})
      : super.ofType(PdfName.submitForm) {
    pdfRepresentation()
        .put(PdfName.f, PdfFileSpec.url(url).pdfRepresentation());
    if (fieldNames != null) setFieldNames(fieldNames);
    if (flags != null) setFlags(flags);
  }

  /// Sets `/F`, the URL of the script processing the submission.
  PdfActionSubmitForm setFile(PdfFileSpec file) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
    return this;
  }

  /// Gets `/F` as written.
  Future<PdfObject?> getFile() async =>
      await pdfRepresentation().get(PdfName.f, true);

  /// Gets the URL of `/F`, accepting the string and dictionary forms.
  Future<String?> getUrl() async =>
      await readFileSpecificationName(await getFile());
}

/// Reset-form action.
///
/// See ISO 32000-1:2008, 12.7.5.3, Table 238.
class PdfActionResetForm extends PdfFormAction {
  PdfActionResetForm(super.pdfObject);

  /// Creates a `/ResetForm` action. With no `/Fields` entry, Table 238 makes
  /// the action reset every field of the document's interactive form.
  PdfActionResetForm.create({List<String>? fieldNames, int? flags})
      : super.ofType(PdfName.resetForm) {
    if (fieldNames != null) setFieldNames(fieldNames);
    if (flags != null) setFlags(flags);
  }
}

/// Import-data action.
///
/// See ISO 32000-1:2008, 12.7.5.4, Table 240.
class PdfActionImportData extends PdfAction {
  PdfActionImportData(super.pdfObject);

  /// Creates an `/ImportData` action. `/F`, the FDF file the data is
  /// imported from, is required by Table 240.
  PdfActionImportData.create(PdfFileSpec file)
      : super.ofType(PdfName.importData) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
  }

  /// Creates an `/ImportData` action from a plain FDF file name.
  PdfActionImportData.fromFileName(String fileName)
      : super.ofType(PdfName.importData) {
    pdfRepresentation()
        .put(PdfName.f, PdfFileSpec.external(fileName).pdfRepresentation());
  }

  /// Gets `/F` as written.
  Future<PdfObject?> getFile() async =>
      await pdfRepresentation().get(PdfName.f, true);

  /// Gets the file name of `/F`.
  Future<String?> getFileName() async =>
      await readFileSpecificationName(await getFile());
}
