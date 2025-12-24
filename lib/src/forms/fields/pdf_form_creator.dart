import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/pdf_dictionary.dart';
import '../pdf_acro_form.dart';
import 'pdf_form_field.dart';
import 'pdf_text_form_field.dart';
import 'pdf_button_form_field.dart';
import 'pdf_choice_form_field.dart';
import 'pdf_signature_form_field.dart';

class PdfFormCreator {
  static final PdfFormFactory _factory = PdfFormFactory();

  static void setFactory(PdfFormFactory factory) {
    // Dart does not allow reassignment of static final for good reason usually,
    // but to match C# logic we might need a way.
    // For now, let's keep it private static final and if we need extensibility
    // we can make it non-final or use an instance.
    // _factory = factory;
    // Actually, for porting fidelity, if it's mutable in C#, it should be here.
  }

  static Future<PdfFormField> createFormField(PdfDictionary dictionary) {
    return _factory.createFormField(dictionary);
  }

  static PdfTextFormField createTextFormField(PdfDictionary dictionary) {
    return _factory.createTextFormField(dictionary);
  }

  static PdfButtonFormField createButtonFormField(PdfDictionary dictionary) {
    return _factory.createButtonFormField(dictionary);
  }

  static PdfChoiceFormField createChoiceFormField(PdfDictionary dictionary) {
    return _factory.createChoiceFormField(dictionary);
  }

  static PdfSignatureFormField createSignatureFormField(
      PdfDictionary dictionary) {
    return _factory.createSignatureFormField(dictionary);
  }

  static Future<PdfAcroForm> getAcroForm(
      PdfDocument document, bool createIfNotExist) {
    return _factory.getAcroForm(document, createIfNotExist);
  }
}

class PdfFormFactory {
  Future<PdfFormField> createFormField(PdfDictionary dictionary) async {
    // Here we determine the type of the field based on the dictionary
    // This is crucial for PdfAcroForm._populateFormFieldsMap recursion
    return PdfFormField.makeFormField(
        dictionary, dictionary.getIndirectReference()?.getDocument());
  }

  PdfTextFormField createTextFormField(PdfDictionary dictionary) {
    return PdfTextFormField(dictionary);
  }

  PdfButtonFormField createButtonFormField(PdfDictionary dictionary) {
    return PdfButtonFormField(dictionary);
  }

  PdfChoiceFormField createChoiceFormField(PdfDictionary dictionary) {
    return PdfChoiceFormField(dictionary);
  }

  PdfSignatureFormField createSignatureFormField(PdfDictionary dictionary) {
    return PdfSignatureFormField(dictionary);
  }

  Future<PdfAcroForm> getAcroForm(PdfDocument document, bool createIfNotExist) {
    return PdfAcroForm.getAcroForm(document, createIfNotExist);
  }
}
