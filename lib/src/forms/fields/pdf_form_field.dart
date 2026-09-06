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
    final ap = await getPdfObject().getAsDictionary(PdfName.ap);
    if (ap == null) return [];
    final n = await ap.getAsDictionary(PdfName.n);
    if (n == null) return [];
    return n.keySet().map((e) => e.getValue()).toList();
  }

  @override
  Future<bool> regenerateField() async {
    // Default implementation does not regenerate appearance.
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

  Future<void> removeChild(PdfFormField child) async {
    PdfArray? kids = await getKids();
    if (kids != null) {
      kids.remove(child.getPdfObject());
    }
  }

  Future<void> addChildField(PdfFormField child) async {
    child.getPdfObject().put(PdfName.parent, getPdfObject());

    PdfArray? kids = await getKids();
    if (kids == null) {
      kids = PdfArray();
      put(PdfName.kids, kids);
    }
    kids.add(child.getPdfObject());
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

  Future<List<PdfWidgetAnnotation>> getWidgets() async {
    List<PdfWidgetAnnotation> widgets = [];
    
    PdfArray? kids = await getKids();
    if (kids != null) {
      for (int i = 0; i < kids.size(); i++) {
        PdfDictionary? kid = await kids.getAsDictionary(i);
        if (kid != null) {
          PdfFormField kidField = PdfFormField(kid);
          widgets.addAll(await kidField.getWidgets());
        }
      }
    }
    
    // If no kids found (or even if they were?), check if self is a widget.
    // Typically, if there are kids, they represent the instances.
    // But if the list is empty so far, we definitely check self.
    // To be safe, we always check self, but usually a node with Kids isn't a terminal widget.
    if (widgets.isEmpty) {
      if (await getPdfObject().getAsName(PdfName.subtype) == PdfName.widget) {
        widgets.add(PdfWidgetAnnotation(getPdfObject()));
      }
    }
    
    return widgets;
  }

  Future<String> getFieldNameValue() async {
    PdfString? s = await getFieldName();
    return s?.toUnicodeString() ?? "";
  }
  
  bool _regenerationDisabled = false;
  
  /// Disables regeneration of the field and its children appearance stream.
  /// After this method is called field will be regenerated only during
  /// enableFieldRegeneration() call.
  Future<void> disableFieldRegeneration() async {
    _regenerationDisabled = true;
    for (var child in childFields) {
      if (child is PdfFormField) {
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
      if (child is PdfFormField) {
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
  Future<PdfFormField?> getChildField(String name) async {
    PdfArray? kids = await getKids();
    if (kids == null) return null;
    
    for (int i = 0; i < kids.size(); i++) {
      PdfDictionary? kidDict = await kids.getAsDictionary(i);
      if (kidDict != null) {
        PdfString? fieldName = await kidDict.getAsString(PdfName.t);
        if (fieldName != null && fieldName.toUnicodeString() == name) {
          return PdfFormField.makeFormField(kidDict, getDocument());
        }
      }
    }
    return null;
  }
  
  /// Gets all child form fields (non-annotation children).
  List<AbstractPdfFormField> getChildFields() => childFields;
  
  /// Returns the value of the field.
  Future<PdfObject?> getValue() async {
    return await getPdfObject().get(PdfName.v, true);
  }
  
  /// Returns the value as a string.
  Future<String?> getValueAsString() async {
    PdfObject? v = await getValue();
    if (v is PdfString) {
      return v.toUnicodeString();
    } else if (v is PdfName) {
      return v.getValue();
    }
    return null;
  }
  
  /// Checks if this field is read only.
  Future<bool> isReadOnly() async => await getFieldFlag(ffReadOnly);
  
  /// Sets the read only flag.
  Future<void> setReadOnly(bool readOnly) async => await setFieldFlag(ffReadOnly, readOnly);
  
  /// Checks if this field is required.
  Future<bool> isRequired() async => await getFieldFlag(ffRequired);
  
  /// Sets the required flag.
  Future<void> setRequired(bool required) async => await setFieldFlag(ffRequired, required);
  
  /// Checks if this field should not be exported.
  Future<bool> isNoExport() async => await getFieldFlag(ffNoExport);
  
  /// Sets the no export flag.
  Future<void> setNoExport(bool noExport) async => await setFieldFlag(ffNoExport, noExport);
  
  /// Checks if the field can contain multiple lines of text.
  Future<bool> isMultiline() async => await getFieldFlag(ffMultiline);
  
  /// Sets the multiline flag.
  Future<void> setMultiline(bool multiline) async => await setFieldFlag(ffMultiline, multiline);
  
  /// Checks if the field is a password field.
  Future<bool> isPassword() async => await getFieldFlag(ffPassword);
  
  /// Sets the password flag.
  Future<void> setPassword(bool password) async => await setFieldFlag(ffPassword, password);
  
  /// Gets the current field partial name.
  Future<PdfString?> getPartialFieldName() async {
    return await getPdfObject().getAsString(PdfName.t);
  }
  
  /// Changes the alternate name of the field to the specified value.
  /// The alternate is a descriptive name to be used by status messages etc.
  void setAlternativeName(String name) {
    put(PdfName.tu, PdfString(name));
  }
  
  /// Gets the current alternate name.
  /// The alternate is a descriptive name to be used by status messages etc.
  Future<PdfString?> getAlternativeName() async {
    return await getPdfObject().getAsString(PdfName.tu);
  }
  
  /// Changes the mapping name of the field to the specified value.
  /// The mapping name can be used when exporting the form data in the document.
  void setMappingName(String name) {
    put(PdfName.tm, PdfString(name));
  }
  
  /// Gets the current mapping name.
  /// The mapping name can be used when exporting the form data in the document.
  Future<PdfString?> getMappingName() async {
    return await getPdfObject().getAsString(PdfName.tm);
  }
  
  /// Retrieves string value from PdfObject representing text string or text stream.
  static Future<String?> getStringValue(PdfObject? value) async {
    if (value == null) return null;
    if (value is PdfString) {
      return value.toUnicodeString();
    } else if (value is PdfName) {
      return value.getValue();
    }
    return null;
  }
  
  /// Gets the raw flags value of this field.
  Future<int> getFieldFlags() async {
    PdfNumber? n = await getPdfObject().getAsNumber(PdfName.ff);
    return n?.intValue() ?? 0;
  }
  
  /// Sets the raw flags value of this field.
  void setFieldFlags(int flags) {
    put(PdfName.ff, PdfNumber(flags.toDouble()));
  }
  
  /// Removes all children from the current field.
  Future<void> removeChildren() async {
    getPdfObject().remove(PdfName.kids);
    childFields.clear();
  }
  
  /// Gets all child form fields of this form field (annotations are not returned).
  Future<List<PdfFormField>> getChildFormFields() async {
    List<PdfFormField> result = [];
    PdfArray? kids = await getKids();
    if (kids == null) return result;
    
    for (int i = 0; i < kids.size(); i++) {
      PdfDictionary? kidDict = await kids.getAsDictionary(i);
      if (kidDict != null) {
        // Check if it's a form field (has FT or T) and not just a widget
        if (kidDict.containsKey(PdfName.ft) || kidDict.containsKey(PdfName.t)) {
          PdfFormField field = await PdfFormField.makeFormField(kidDict, getDocument());
          result.add(field);
        }
      }
    }
    return result;
  }
  
  /// Gets all childFields of this object, including the children of the children
  /// but not annotations.
  Future<List<PdfFormField>> getAllChildFormFields() async {
    List<PdfFormField> result = [];
    await _collectAllChildFormFields(result);
    return result;
  }
  
  Future<void> _collectAllChildFormFields(List<PdfFormField> result) async {
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
  
  /// Checks if dictionary contains any of the form field keys.
  static bool isFormField(PdfDictionary dict) {
    return dict.containsKey(PdfName.ft) || 
           dict.containsKey(PdfName.t) || 
           dict.containsKey(PdfName.kids) ||
           dict.containsKey(PdfName.v);
  }
  
  /// Gets a set of all possible form field keys.
  static Set<PdfName> getFormFieldKeys() {
    return {
      PdfName.ft,  // Field type
      PdfName.t,   // Partial field name
      PdfName.tu,  // Alternate field name
      PdfName.tm,  // Mapping name
      PdfName.ff,  // Field flags
      PdfName.v,   // Field value
      PdfName.dv,  // Default value
      PdfName.aa,  // Additional actions
      PdfName.da,  // Default appearance
      PdfName.q,   // Quadding
      PdfName.ds,  // Default style
      PdfName.rv,  // Rich text value
      PdfName.opts, // Options (for choice fields)
    };
  }
  
  /// Gets the default value of this field.
  Future<PdfObject?> getDefaultValue() async {
    return await getPdfObject().get(PdfName.dv, true);
  }
  
  /// Sets the default value of this field.
  void setDefaultValue(PdfObject value) {
    put(PdfName.dv, value);
  }
  
  /// Sets the default value of this field as a string.
  void setDefaultValueString(String value) {
    put(PdfName.dv, PdfString(value));
  }
  
  /// Gets the quadding (justification) of this field.
  /// 0 = Left-justified, 1 = Centered, 2 = Right-justified.
  Future<int> getQuadding() async {
    PdfNumber? q = await getPdfObject().getAsNumber(PdfName.q);
    return q?.intValue() ?? 0;
  }
  
  /// Sets the quadding (justification) of this field.
  /// 0 = Left-justified, 1 = Centered, 2 = Right-justified.
  void setQuadding(int justification) {
    put(PdfName.q, PdfNumber(justification.toDouble()));
  }
  void release() {
      // Clean up resources
      childFields.clear();
      // super.release(); // Not defined
  }

  /// Sets the action for this field.
  void setAction(PdfAction action) {
    put(PdfName.a, action.getPdfObject());
  }

  /// Gets the action for this field.
  Future<PdfAction?> getAction() async {
    PdfDictionary? action = await getPdfObject().getAsDictionary(PdfName.a);
    if (action != null) {
      return PdfAction.makeAction(action);
    }
    return null;
  }

  /// Sets the additional action for this field.
  Future<void> setAdditionalAction(PdfName key, PdfAction action) async {
    PdfDictionary? aa = await getPdfObject().getAsDictionary(PdfName.aa);
    if (aa == null) {
      aa = PdfDictionary();
      put(PdfName.aa, aa);
    }
    aa.put(key, action.getPdfObject());
    setModified();
  }

  /// Gets the additional action for this field.
  Future<PdfAction?> getAdditionalAction(PdfName key) async {
    PdfDictionary? aa = await getPdfObject().getAsDictionary(PdfName.aa);
    if (aa != null) {
      PdfDictionary? action = await aa.getAsDictionary(key);
      if (action != null) {
        return PdfAction.makeAction(action);
      }
    }
    return null;
  }
}
