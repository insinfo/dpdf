import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import '../../kernel/pdf/action/pdf_action.dart';

import 'abstract_pdf_form_field.dart';

import 'pdf_text_form_field.dart';
import 'pdf_button_form_field.dart';
import 'pdf_choice_form_field.dart';
import 'pdf_signature_form_field.dart';

class CraftPdfFormField extends CraftAbstractPdfFormField {
  static const int ffReadOnly = 1 << 0; // Bit 1
  static const int ffRequired = 1 << 1; // Bit 2
  static const int ffNoExport = 1 << 2; // Bit 3
  static const int ffMultiline = 1 << 12; // Bit 13
  static const int ffPassword = 1 << 13; // Bit 14

  final List<CraftAbstractPdfFormField> childFields = [];

  CraftPdfFormField(CraftPdfDictionary pdfObject) : super(pdfObject);

  static Future<CraftPdfFormField> makeFormField(
      CraftPdfObject pdfObject, CraftPdfDocument? document) async {
    if (!pdfObject.isDictionary()) {
      throw ArgumentError("PdfObject must be a dictionary");
    }
    CraftPdfDictionary dict = pdfObject as CraftPdfDictionary;
    CraftPdfName? ft = await dict.nameEntry(CraftPdfName.ft);

    CraftPdfFormField field;
    if (CraftPdfName.tx == ft) {
      field = CraftPdfTextFormField(dict);
    } else if (CraftPdfName.btn == ft) {
      field = CraftPdfButtonFormField(dict);
    } else if (CraftPdfName.ch == ft) {
      field = CraftPdfChoiceFormField(dict);
    } else if (CraftPdfName.sig == ft) {
      field = CraftPdfSignatureFormField(dict);
    } else {
      field = CraftPdfFormField(dict);
    }

    if (document != null) {
      field.attachToDocument(document);
    }
    await field.loadStyles();
    return field;
  }

  // Helper for flags
  Future<bool> getFieldFlag(int flag) async {
    CraftPdfNumber? n = await pdfRepresentation().numberEntry(CraftPdfName.ff);
    int flags = n != null ? n.getValue().toInt() : 0;
    return (flags & flag) != 0;
  }

  Future<void> setFieldFlag(int flag, bool value) async {
    CraftPdfNumber? n = await pdfRepresentation().numberEntry(CraftPdfName.ff);
    int flags = n != null ? n.getValue().toInt() : 0;
    if (value) {
      flags |= flag;
    } else {
      flags &= ~flag;
    }
    put(CraftPdfName.ff, CraftPdfNumber(flags.toDouble()));
  }

  @override
  Future<CraftPdfString?> getDefaultAppearance() async {
    CraftPdfString? da = await pdfRepresentation().stringEntry(CraftPdfName.da);
    if (da != null) return da;
    return super.getDefaultAppearance();
  }

  @override
  Future<List<String>> getAppearanceStates() async {
    final ap = await pdfRepresentation().dictionaryEntry(CraftPdfName.ap);
    if (ap == null) return [];
    final n = await ap.dictionaryEntry(CraftPdfName.n);
    if (n == null) return [];
    return n.keySet().map((e) => e.getValue()).toList();
  }

  @override
  Future<bool> regenerateField() async {
    // Default implementation does not regenerate appearance.
    return false;
  }

  Future<void> addKid(CraftPdfWidgetAnnotation widget) async {
    widget.pdfRepresentation().put(CraftPdfName.parent, pdfRepresentation());

    CraftPdfArray? kids = await getKids();
    if (kids == null) {
      kids = CraftPdfArray();
      put(CraftPdfName.kids, kids);
    }
    kids.add(widget.pdfRepresentation());
  }

  Future<void> removeChild(CraftPdfFormField child) async {
    CraftPdfArray? kids = await getKids();
    if (kids != null) {
      kids.remove(child.pdfRepresentation());
    }
  }

  Future<void> addChildField(CraftPdfFormField child) async {
    child.pdfRepresentation().put(CraftPdfName.parent, pdfRepresentation());

    CraftPdfArray? kids = await getKids();
    if (kids == null) {
      kids = CraftPdfArray();
      put(CraftPdfName.kids, kids);
    }
    kids.add(child.pdfRepresentation());
  }

  Future<CraftPdfArray?> getKids() async {
    return await pdfRepresentation().arrayEntry(CraftPdfName.kids);
  }

  void setValue(Object value) {
    if (value is String) {
      put(CraftPdfName.v, CraftPdfString(value));
    } else if (value is CraftPdfObject) {
      put(CraftPdfName.v, value);
    } else {
      throw ArgumentError("Value must be value PdfObject or String");
    }
  }

  Future<CraftPdfName?> getFormType() async {
    return pdfRepresentation().nameEntry(CraftPdfName.ft);
  }

  void setFieldName(String name) {
    put(CraftPdfName.t, CraftPdfString(name));
  }

  Future<List<CraftPdfWidgetAnnotation>> getWidgets() async {
    List<CraftPdfWidgetAnnotation> widgets = [];

    CraftPdfArray? kids = await getKids();
    if (kids != null) {
      for (int i = 0; i < kids.size(); i++) {
        CraftPdfDictionary? kid = await kids.dictionaryEntry(i);
        if (kid != null) {
          CraftPdfFormField kidField = CraftPdfFormField(kid);
          widgets.addAll(await kidField.getWidgets());
        }
      }
    }

    // If no kids found (or even if they were?), check if self is a widget.
    // Typically, if there are kids, they represent the instances.
    // But if the list is empty so far, we definitely check self.
    // To be safe, we always check self, but usually a node with Kids isn't a terminal widget.
    if (widgets.isEmpty) {
      if (await pdfRepresentation().nameEntry(CraftPdfName.subtype) ==
          CraftPdfName.widget) {
        widgets.add(CraftPdfWidgetAnnotation(pdfRepresentation()));
      }
    }

    return widgets;
  }

  Future<String> getFieldNameValue() async {
    CraftPdfString? s = await getFieldName();
    return s?.decodeMappingText() ?? "";
  }

  bool _regenerationDisabled = false;

  /// Disables regeneration of the field and its children appearance stream.
  /// After this method is called field will be regenerated only during
  /// enableFieldRegeneration() call.
  Future<void> disableFieldRegeneration() async {
    _regenerationDisabled = true;
    for (var child in childFields) {
      if (child is CraftPdfFormField) {
        await child.disableFieldRegeneration();
      }
    }
  }

  /// Enables regeneration of the field appearance stream.
  /// This method also regenerates the field appearance.
  Future<void> enableFieldRegeneration() async {
    _regenerationDisabled = false;
    await regenerateField();
    for (var child in childFields) {
      if (child is CraftPdfFormField) {
        await child.enableFieldRegeneration();
      }
    }
  }

  /// Disables regeneration of only this field's appearance stream.
  void disableCurrentFieldRegeneration() {
    _regenerationDisabled = true;
  }

  /// Enables regeneration of only this field's appearance stream.
  void enableCurrentFieldRegeneration() {
    _regenerationDisabled = false;
  }

  /// Checks if field regeneration is disabled.
  bool isFieldRegenerationDisabled() => _regenerationDisabled;

  /// Gets a child field by name.
  Future<CraftPdfFormField?> getChildField(String name) async {
    CraftPdfArray? kids = await getKids();
    if (kids == null) return null;

    for (int i = 0; i < kids.size(); i++) {
      CraftPdfDictionary? kidDict = await kids.dictionaryEntry(i);
      if (kidDict != null) {
        CraftPdfString? fieldName = await kidDict.stringEntry(CraftPdfName.t);
        if (fieldName != null && fieldName.decodeMappingText() == name) {
          return CraftPdfFormField.makeFormField(kidDict, getDocument());
        }
      }
    }
    return null;
  }

  /// Gets all child form fields (non-annotation children).
  List<CraftAbstractPdfFormField> getChildFields() => childFields;

  /// Returns the value of the field.
  Future<CraftPdfObject?> getValue() async {
    return await pdfRepresentation().get(CraftPdfName.v, true);
  }

  /// Returns the value as a string.
  Future<String?> getValueAsString() async {
    CraftPdfObject? v = await getValue();
    if (v is CraftPdfString) {
      return v.decodeMappingText();
    } else if (v is CraftPdfName) {
      return v.getValue();
    }
    return null;
  }

  /// Checks if this field is read only.
  Future<bool> isReadOnly() async => await getFieldFlag(ffReadOnly);

  /// Sets the read only flag.
  Future<void> setReadOnly(bool readOnly) async =>
      await setFieldFlag(ffReadOnly, readOnly);

  /// Checks if this field is required.
  Future<bool> isRequired() async => await getFieldFlag(ffRequired);

  /// Sets the required flag.
  Future<void> setRequired(bool required) async =>
      await setFieldFlag(ffRequired, required);

  /// Checks if this field should not be exported.
  Future<bool> isNoExport() async => await getFieldFlag(ffNoExport);

  /// Sets the no export flag.
  Future<void> setNoExport(bool noExport) async =>
      await setFieldFlag(ffNoExport, noExport);

  /// Checks if the field can contain multiple lines of text.
  Future<bool> isMultiline() async => await getFieldFlag(ffMultiline);

  /// Sets the multiline flag.
  Future<void> setMultiline(bool multiline) async =>
      await setFieldFlag(ffMultiline, multiline);

  /// Checks if the field is a password field.
  Future<bool> isPassword() async => await getFieldFlag(ffPassword);

  /// Sets the password flag.
  Future<void> setPassword(bool password) async =>
      await setFieldFlag(ffPassword, password);

  /// Gets the current field partial name.
  Future<CraftPdfString?> getPartialFieldName() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.t);
  }

  /// Changes the alternate name of the field to the specified value.
  /// The alternate is a descriptive name to be used by status messages etc.
  void setAlternativeName(String name) {
    put(CraftPdfName.tu, CraftPdfString(name));
  }

  /// Gets the current alternate name.
  /// The alternate is a descriptive name to be used by status messages etc.
  Future<CraftPdfString?> getAlternativeName() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.tu);
  }

  /// Changes the mapping name of the field to the specified value.
  /// The mapping name can be used when exporting the form data in the document.
  void setMappingName(String name) {
    put(CraftPdfName.tm, CraftPdfString(name));
  }

  /// Gets the current mapping name.
  /// The mapping name can be used when exporting the form data in the document.
  Future<CraftPdfString?> getMappingName() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.tm);
  }

  /// Retrieves string value from PdfObject representing text string or text stream.
  static Future<String?> getStringValue(CraftPdfObject? value) async {
    if (value == null) return null;
    if (value is CraftPdfString) {
      return value.decodeMappingText();
    } else if (value is CraftPdfName) {
      return value.getValue();
    }
    return null;
  }

  /// Gets the raw flags value of this field.
  Future<int> getFieldFlags() async {
    CraftPdfNumber? n = await pdfRepresentation().numberEntry(CraftPdfName.ff);
    return n?.intValue() ?? 0;
  }

  /// Sets the raw flags value of this field.
  void setFieldFlags(int flags) {
    put(CraftPdfName.ff, CraftPdfNumber(flags.toDouble()));
  }

  /// Removes all children from the current field.
  Future<void> removeChildren() async {
    pdfRepresentation().remove(CraftPdfName.kids);
    childFields.clear();
  }

  /// Gets all child form fields of this form field (annotations are not returned).
  Future<List<CraftPdfFormField>> getChildFormFields() async {
    List<CraftPdfFormField> result = [];
    CraftPdfArray? kids = await getKids();
    if (kids == null) return result;

    for (int i = 0; i < kids.size(); i++) {
      CraftPdfDictionary? kidDict = await kids.dictionaryEntry(i);
      if (kidDict != null) {
        // Check if it's a form field (has FT or T) and not just a widget
        if (kidDict.containsKey(CraftPdfName.ft) ||
            kidDict.containsKey(CraftPdfName.t)) {
          CraftPdfFormField field =
              await CraftPdfFormField.makeFormField(kidDict, getDocument());
          result.add(field);
        }
      }
    }
    return result;
  }

  /// Returns descendant fields, including nested descendants.
  /// but not annotations.
  Future<List<CraftPdfFormField>> getAllChildFormFields() async {
    List<CraftPdfFormField> result = [];
    await _collectAllChildFormFields(result);
    return result;
  }

  Future<void> _collectAllChildFormFields(
      List<CraftPdfFormField> result) async {
    for (var child in await getChildFormFields()) {
      result.add(child);
      await child._collectAllChildFormFields(result);
    }
  }

  /// Makes a field flag by bit position (1-32).
  /// Bit positions are numbered 1 to 32 from the PDF specification.
  static int makeFieldFlag(int bitPosition) {
    if (bitPosition < 1 || bitPosition > 32) {
      throw ArgumentError('Bit position must be between 1 and 32');
    }
    return 1 << (bitPosition - 1);
  }

  /// Detects whether a dictionary has field-specific entries.
  static bool isFormField(CraftPdfDictionary dict) {
    return dict.containsKey(CraftPdfName.ft) ||
        dict.containsKey(CraftPdfName.t) ||
        dict.containsKey(CraftPdfName.kids) ||
        dict.containsKey(CraftPdfName.v);
  }

  /// Gets a set of all possible form field keys.
  static Set<CraftPdfName> getFormFieldKeys() {
    return {
      CraftPdfName.ft, // Field type
      CraftPdfName.t, // Partial field name
      CraftPdfName.tu, // Alternate field name
      CraftPdfName.tm, // Mapping name
      CraftPdfName.ff, // Field flags
      CraftPdfName.v, // Field value
      CraftPdfName.dv, // Default value
      CraftPdfName.aa, // Additional actions
      CraftPdfName.da, // Default appearance
      CraftPdfName.q, // Quadding
      CraftPdfName.ds, // Default style
      CraftPdfName.rv, // Rich text value
      CraftPdfName.opts, // Options (for choice fields)
    };
  }

  /// Gets the default value of this field.
  Future<CraftPdfObject?> getDefaultValue() async {
    return await pdfRepresentation().get(CraftPdfName.dv, true);
  }

  /// Sets the default value of this field.
  void setDefaultValue(CraftPdfObject value) {
    put(CraftPdfName.dv, value);
  }

  /// Sets the default value of this field as a string.
  void setDefaultValueString(String value) {
    put(CraftPdfName.dv, CraftPdfString(value));
  }

  /// Gets the quadding (justification) of this field.
  /// 0 = Left-justified, 1 = Centered, 2 = Right-justified.
  Future<int> getQuadding() async {
    CraftPdfNumber? q = await pdfRepresentation().numberEntry(CraftPdfName.q);
    return q?.intValue() ?? 0;
  }

  /// Sets the quadding (justification) of this field.
  /// 0 = Left-justified, 1 = Centered, 2 = Right-justified.
  void setQuadding(int justification) {
    put(CraftPdfName.q, CraftPdfNumber(justification.toDouble()));
  }

  void release() {
    // Clean up resources
    childFields.clear();
    // super.release(); // Not defined
  }

  /// Sets the action for this field.
  void setAction(CraftPdfAction action) {
    put(CraftPdfName.a, action.pdfRepresentation());
  }

  /// Gets the action for this field.
  Future<CraftPdfAction?> getAction() async {
    CraftPdfDictionary? action =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.a);
    if (action != null) {
      return CraftPdfAction.makeAction(action);
    }
    return null;
  }

  /// Sets the additional action for this field.
  Future<void> setAdditionalAction(
      CraftPdfName key, CraftPdfAction action) async {
    CraftPdfDictionary? aa =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.aa);
    if (aa == null) {
      aa = CraftPdfDictionary();
      put(CraftPdfName.aa, aa);
    }
    aa.put(key, action.pdfRepresentation());
    markChanged();
  }

  /// Gets the additional action for this field.
  Future<CraftPdfAction?> getAdditionalAction(CraftPdfName key) async {
    CraftPdfDictionary? aa =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.aa);
    if (aa != null) {
      CraftPdfDictionary? action = await aa.dictionaryEntry(key);
      if (action != null) {
        return CraftPdfAction.makeAction(action);
      }
    }
    return null;
  }
}
