import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import 'fields/pdf_form_field.dart';

class PdfAcroForm extends PdfObjectWrapper<PdfDictionary> {
  final Map<String, PdfFormField> _fields = {};
  bool _fieldsLoaded = false;
  final PdfDocument _document;

  PdfAcroForm(PdfDictionary pdfObject, PdfDocument pdfDocument)
      : _document = pdfDocument,
        super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  static Future<PdfAcroForm> getAcroForm(
      PdfDocument document, bool createIfNotExist) async {
    PdfDictionary? catalogDict = await document.getCatalog().getPdfObject();
    PdfDictionary? acroFormDict =
        await catalogDict.getAsDictionary(PdfName.acroForm);

    if (acroFormDict == null && createIfNotExist) {
      acroFormDict = PdfDictionary();
      catalogDict.put(PdfName.acroForm, acroFormDict);
      acroFormDict.makeIndirect(document);
    }

    if (acroFormDict == null) {
      // Return a dummy/empty or throw? iText returns null if not exist and not create.
      // But here we might need a wrapped object.
      throw StateError("AcroForm not found");
    }

    return PdfAcroForm(acroFormDict, document);
  }

  Future<void> _populateFormFieldsMap() async {
    if (_fieldsLoaded) return;
    _fields.clear();
    PdfArray? fields = await getPdfObject().getAsArray(PdfName.fields);
    if (fields != null) {
      await _iterateFields(fields, "");
    }
    _fieldsLoaded = true;
  }

  Future<void> _iterateFields(PdfArray fields, String parentName) async {
    for (int i = 0; i < fields.size(); i++) {
      PdfObject? obj = await fields.get(i);
      if (obj is PdfDictionary) {
        await _addFieldToMap(obj, parentName);
      }
    }
  }

  Future<void> _addFieldToMap(
      PdfDictionary fieldDict, String parentName) async {
    PdfFormField field = await PdfFormField.makeFormField(fieldDict, _document);
    String partialName = await field.getFieldNameValue();
    String fullName =
        parentName.isEmpty ? partialName : "$parentName.$partialName";

    if (partialName.isNotEmpty) {
      _fields[fullName] = field;
    }

    PdfArray? kids = await fieldDict.getAsArray(PdfName.kids);
    if (kids != null) {
      await _iterateFields(kids, fullName);
    }
  }

  Future<Map<String, PdfFormField>> getFormFields() async {
    if (!_fieldsLoaded) await _populateFormFieldsMap();
    return _fields;
  }

  Future<void> addField(PdfFormField field, PdfPage page) async {
    PdfString? name = await field.getFieldName();
    if (name == null) {
      throw ArgumentError("Form field must have a name");
    }

    PdfArray? fields = await getPdfObject().getAsArray(PdfName.fields);
    if (fields == null) {
      fields = PdfArray();
      getPdfObject().put(PdfName.fields, fields);
    }

    // Check if duplicate
    bool exists = false;
    for (int i = 0; i < fields.size(); i++) {
      if (await fields.get(i) == field.getPdfObject()) {
        exists = true;
        break;
      }
    }

    if (!exists) {
      fields.add(field.getPdfObject());
    }

    // Add to internal map
    if (!_fieldsLoaded) await _populateFormFieldsMap();
    String fullName = await field.getFieldNameValue(); // Simplified for now
    _fields[fullName] = field;
  }
}
