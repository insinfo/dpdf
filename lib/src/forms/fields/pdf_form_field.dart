import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';

import 'abstract_pdf_form_field.dart';

import 'pdf_text_form_field.dart';
import 'pdf_button_form_field.dart';
import 'pdf_choice_form_field.dart';
import 'pdf_signature_form_field.dart';

class PdfFormField extends AbstractPdfFormField {
  static const int ffReadOnly = 1 << 0; // Bit 1
  static const int ffRequired = 1 << 1; // Bit 2
  static const int ffNoExport = 1 << 2; // Bit 3
  static const int ffMultiline = 1 << 12; // Bit 13
  static const int ffPassword = 1 << 13; // Bit 14

  final List<AbstractPdfFormField> childFields = [];

  PdfFormField(PdfDictionary pdfObject) : super(pdfObject);

  static Future<PdfFormField> makeFormField(
      PdfObject pdfObject, PdfDocument? document) async {
    if (!pdfObject.isDictionary()) {
      throw ArgumentError("PdfObject must be a dictionary");
    }
    PdfDictionary dict = pdfObject as PdfDictionary;
    PdfName? ft = await dict.getAsName(PdfName.ft);

    PdfFormField field;
    if (PdfName.tx == ft) {
      field = PdfTextFormField(dict);
    } else if (PdfName.btn == ft) {
      field = PdfButtonFormField(dict);
    } else if (PdfName.ch == ft) {
      field = PdfChoiceFormField(dict);
    } else if (PdfName.sig == ft) {
      field = PdfSignatureFormField(dict);
    } else {
      field = PdfFormField(dict);
    }

    if (document != null) {
      field.makeIndirect(document);
    }
    return field;
  }

  // Helper for flags
  Future<bool> getFieldFlag(int flag) async {
    PdfNumber? n = await getPdfObject().getAsNumber(PdfName.ff);
    int flags = n != null ? n.getValue().toInt() : 0;
    return (flags & flag) != 0;
  }

  Future<void> setFieldFlag(int flag, bool value) async {
    PdfNumber? n = await getPdfObject().getAsNumber(PdfName.ff);
    int flags = n != null ? n.getValue().toInt() : 0;
    if (value) {
      flags |= flag;
    } else {
      flags &= ~flag;
    }
    put(PdfName.ff, PdfNumber(flags.toDouble()));
  }

  @override
  Future<PdfString?> getDefaultAppearance() async {
    PdfString? da = await getPdfObject().getAsString(PdfName.da);
    if (da != null) return da;
    return super.getDefaultAppearance();
  }

  @override
  Future<List<String>> getAppearanceStates() async {
    // TODO
    return [];
  }

  @override
  Future<bool> regenerateField() async {
    // TODO
    return false;
  }

  Future<void> addKid(PdfWidgetAnnotation widget) async {
    widget.getPdfObject().put(PdfName.parent, getPdfObject());

    PdfArray? kids = await getKids();
    if (kids == null) {
      kids = PdfArray();
      put(PdfName.kids, kids);
    }
    kids.add(widget.getPdfObject());
  }

  Future<PdfArray?> getKids() async {
    return await getPdfObject().getAsArray(PdfName.kids);
  }

  void setValue(Object value) {
    if (value is String) {
      put(PdfName.v, PdfString(value));
    } else if (value is PdfObject) {
      put(PdfName.v, value);
    } else {
      throw ArgumentError("Value must be value PdfObject or String");
    }
  }

  Future<PdfName?> getFormType() async {
    return getPdfObject().getAsName(PdfName.ft);
  }

  void setFieldName(String name) {
    put(PdfName.t, PdfString(name));
  }

  Future<String> getFieldNameValue() async {
    PdfString? s = await getFieldName();
    return s?.toUnicodeString() ?? "";
  }

  void makeIndirect(PdfDocument document) {
    if (!getPdfObject().isIndirect()) {
      getPdfObject().makeIndirect(document);
    }
  }
}
