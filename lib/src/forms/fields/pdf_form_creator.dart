import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/pdf_dictionary.dart';
import '../pdf_acro_form.dart';
import 'pdf_form_field.dart';
import 'pdf_text_form_field.dart';
import 'pdf_button_form_field.dart';
import 'pdf_choice_form_field.dart';
import 'pdf_signature_form_field.dart';

class CraftPdfFormCreator {
  static final CraftPdfFormFactory _factory = CraftPdfFormFactory();

  static void setFactory(CraftPdfFormFactory factory) {
    // Dart does not allow reassignment of static final for good reason usually,
    // but to match C# logic we might need a way.
    // For now, let's keep it private static final and if we need extensibility
    // we can make it non-final or use an instance.
    // _factory = factory;
    // Actually, for porting fidelity, if it's mutable in C#, it should be here.
  }

  static Future<CraftPdfFormField> createFormField(
      CraftPdfDictionary dictionary) {
    return _factory.createFormField(dictionary);
  }

  static CraftPdfTextFormField createTextFormField(
      CraftPdfDictionary dictionary) {
    return _factory.createTextFormField(dictionary);
  }

  static CraftPdfButtonFormField createButtonFormField(
      CraftPdfDictionary dictionary) {
    return _factory.createButtonFormField(dictionary);
  }

  static CraftPdfChoiceFormField createChoiceFormField(
      CraftPdfDictionary dictionary) {
    return _factory.createChoiceFormField(dictionary);
  }

  static CraftPdfSignatureFormField createSignatureFormField(
      CraftPdfDictionary dictionary) {
    return _factory.createSignatureFormField(dictionary);
  }

  static Future<CraftPdfAcroForm> getAcroForm(
      CraftPdfDocument document, bool createIfNotExist) {
    return _factory.getAcroForm(document, createIfNotExist);
  }
}

class CraftPdfFormFactory {
  Future<CraftPdfFormField> createFormField(
      CraftPdfDictionary dictionary) async {
    // Here we determine the type of the field based on the dictionary
    // This is crucial for PdfAcroForm._populateFormFieldsMap recursion
    return CraftPdfFormField.makeFormField(
        dictionary, dictionary.indirectHandle()?.getDocument());
  }

  CraftPdfTextFormField createTextFormField(CraftPdfDictionary dictionary) {
    return CraftPdfTextFormField(dictionary);
  }

  CraftPdfButtonFormField createButtonFormField(CraftPdfDictionary dictionary) {
    return CraftPdfButtonFormField(dictionary);
  }

  CraftPdfChoiceFormField createChoiceFormField(CraftPdfDictionary dictionary) {
    return CraftPdfChoiceFormField(dictionary);
  }

  CraftPdfSignatureFormField createSignatureFormField(
      CraftPdfDictionary dictionary) {
    return CraftPdfSignatureFormField(dictionary);
  }

  Future<CraftPdfAcroForm> getAcroForm(
      CraftPdfDocument document, bool createIfNotExist) {
    return CraftPdfAcroForm.getAcroForm(document, createIfNotExist);
  }
}
