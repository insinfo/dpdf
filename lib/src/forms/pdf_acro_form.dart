import 'dart:async';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_boolean.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import 'fields/pdf_form_field.dart';
import 'fields/abstract_pdf_form_field.dart';
import '../kernel/pdf/annot/pdf_widget_annotation.dart';

import 'fields/pdf_form_annotation_util.dart';
import '../kernel/pdf/xobject/pdf_form_x_object.dart';
import '../kernel/geom/affine_transform.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/geom/rectangle.dart';
import 'xfa_form.dart';

class CraftPdfAcroForm extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  final Map<String, CraftPdfFormField> _fields = {};
  final Set<CraftPdfFormField> _fieldsForFlattening = {};
  bool _fieldsLoaded = false;
  static const int SIGNATURE_EXIST = 1;
  static const int APPEND_ONLY = 2;

  final CraftPdfDocument _document;
  bool _generateAppearance = true;
  CraftXfaForm? _xfaForm;

  CraftPdfAcroForm(CraftPdfDictionary pdfObject, CraftPdfDocument pdfDocument)
      : _document = pdfDocument,
        super(pdfObject);

  CraftPdfDocument getPdfDocument() => _document;

  static Future<CraftPdfAcroForm> makeAcroForm(CraftPdfDocument document) =>
      getAcroForm(document, true);

  static Future<CraftPdfAcroForm> getAcroForm(
      CraftPdfDocument document, bool createIfNotExist) async {
    CraftPdfDictionary? catalogDict =
        await document.rootCatalog().pdfRepresentation();
    CraftPdfDictionary? acroFormDict =
        await catalogDict.dictionaryEntry(CraftPdfName.acroForm);

    if (acroFormDict == null && createIfNotExist) {
      acroFormDict = CraftPdfDictionary();
      catalogDict.put(CraftPdfName.acroForm, acroFormDict);
      acroFormDict.attachToDocument(document);
      catalogDict.markChanged();
    }

    if (acroFormDict == null) {
      throw StateError("AcroForm not found");
    }

    return CraftPdfAcroForm(acroFormDict, document);
  }

  @override
  bool requiresIndirectStorage() => true;

  Future<void> addField(CraftPdfFormField field, [CraftPdfPage? page]) async {
    await _addFieldInternal(field);
    if (page != null) {
      for (final widget in await field.getWidgets()) {
        await _defineWidgetPageAndAddToIt(page, widget.pdfRepresentation());
      }
    }
  }

  Future<void> _addFieldInternal(CraftPdfFormField field) async {
    CraftPdfString? name = await field.getFieldName();
    if (name == null) {
      throw ArgumentError("Form field must have a name");
    }

    CraftPdfArray? fields =
        await pdfRepresentation().arrayEntry(CraftPdfName.fields);
    if (fields == null) {
      fields = CraftPdfArray();
      pdfRepresentation().put(CraftPdfName.fields, fields);
    }

    // Check if duplicate (by reference) - simplified
    bool contains = false;
    for (int i = 0; i < fields.size(); i++) {
      if (await fields.get(i) == field.pdfRepresentation()) {
        contains = true;
        break;
      }
    }
    if (!contains) {
      fields.add(field.pdfRepresentation());
      fields.markChanged();
      markChanged();
    }

    if (!_fieldsLoaded) await _populateFormFieldsMap();
    String fullName = await field.getFieldNameValue();
    _fields[fullName] = field;
  }

  Future<void> _defineWidgetPageAndAddToIt(
      CraftPdfPage page, CraftPdfDictionary widgetDict) async {
    // Add 'P' (Page) reference to the widget dictionary
    widgetDict.put(CraftPdfName.p, page.pdfRepresentation().indirectHandle()!);

    // Wrap it in a PdfWidgetAnnotation and add to page
    // We assume widgetDict IS the annotation dictionary for terminal fields
    final widgetAnnot = CraftPdfWidgetAnnotation(widgetDict);
    await page.addAnnotation(widgetAnnot);
  }

  Future<CraftXfaForm?> getXfaForm() async {
    if (_xfaForm == null) {
      CraftPdfObject? xfa = await pdfRepresentation().get(CraftPdfName.xfa);
      if (xfa != null) {
        _xfaForm =
            await CraftXfaForm.createFromPdfDictionary(pdfRepresentation());
      }
    }
    return _xfaForm;
  }

  /// Sets the [XfaForm].
  Future<void> setXfaForm(CraftXfaForm xfaForm) async {
    _xfaForm = xfaForm;
    await CraftXfaForm.setXfaFormWithAcroForm(xfaForm, this);
  }

  Future<bool> removeField(String fieldName) async {
    CraftPdfFormField? field = await getField(fieldName);
    if (field == null) {
      return false;
    }

    CraftPdfDictionary fieldObject = field.pdfRepresentation();
    CraftPdfPage? page = await _getFieldPage(fieldObject);

    // Remove annotation from page
    if (page != null) {
      CraftPdfArray? annots =
          await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
      if (annots != null) {
        await annots.remove(fieldObject);
      }
    }

    CraftPdfDictionary? parent = await field.getParent();
    CraftPdfFormField? parentField = field.getParentField();

    if (parentField != null) {
      await parentField.removeChild(field);
    } else if (parent != null) {
      CraftPdfArray? kids = await parent.arrayEntry(CraftPdfName.kids);
      if (kids != null) {
        await kids.remove(fieldObject);
        kids.markChanged();
      }
      parent.markChanged();
      return true;
    }

    CraftPdfArray? fieldsArray = await getFields();
    if (fieldsArray != null && await fieldsArray.containsObject(fieldObject)) {
      await fieldsArray.remove(fieldObject);
      _fields.remove(fieldName);
      fieldsArray.markChanged();
      markChanged();
      return true;
    }

    return false;
  }

  Future<void> replaceField(String name, CraftPdfFormField field) async {
    // PdfFormField? oldField = await getField(name);
    await removeField(name);
    int lastDot = name.lastIndexOf('.');
    if (lastDot == -1) {
      await addField(field);
    } else {
      String parentName = name.substring(0, lastDot);
      CraftPdfFormField? parent = await getField(parentName);
      if (parent == null) {
        await addField(field);
      } else {
        await parent.addChildField(field);
      }
    }
  }

  Future<bool> renameField(String oldName, String newName) async {
    CraftPdfFormField? field = await getField(oldName);
    if (field == null) return false;

    field.setFieldName(newName);
    _removeFieldFromMap(oldName);
    _fields[newName] = field;
    markChanged();
    return true;
  }

  void _removeFieldFromMap(String name) {
    _fields.remove(name);
  }

  Future<CraftPdfFormField?> copyField(String name) async {
    CraftPdfFormField? field = await getField(name);
    if (field == null) return null;
    CraftPdfObject cloned = field.pdfRepresentation().clone();
    if (cloned is CraftPdfDictionary) {
      return CraftPdfFormField.makeFormField(cloned, _document);
    }
    return null;
  }

  Future<void> flattenFields() async {
    if (_document.usesIncrementalRevision()) {
      throw Exception(
          "Flattening fields requires rewriting the document instead of appending a revision.");
    }

    Set<CraftPdfFormField> fieldsToFlatten = {};
    if (_fieldsForFlattening.isEmpty) {
      if (!_fieldsLoaded) {
        await getFormFields();
      }
      // Se não especificou campos, achata todos.
      // Precisamos de todos, incluindo os sem nome e filhos.
      fieldsToFlatten.addAll(
          await getAllFormFieldsAndAnnotations() as Set<CraftPdfFormField>);
    } else {
      for (var field in _fieldsForFlattening) {
        fieldsToFlatten.addAll(await _prepareFieldsForFlattening(field));
      }
    }

    // Para evitar problemas de referência circular, poderíamos clonar recursos da página
    // como no C#, mas vamos tentar implementação direta primeiro e ver se testes passam.

    // Itera sobre cópia para permitir modificação
    for (var formField in fieldsToFlatten.toList()) {
      // Em vez de GetChildFormAnnotations, usamos getWidgets e processamos.
      // Um field pode ser ele mesmo um widget ou ter kids widgets.
      List<CraftPdfWidgetAnnotation> widgets = await formField.getWidgets();

      for (var widget in widgets) {
        CraftPdfDictionary fieldObject = widget.pdfRepresentation();
        CraftPdfPage? page = await widget.pageAt();
        if (page == null) {
          page = await _getFieldPage(fieldObject);
        }

        if (page == null) continue;

        CraftPdfDictionary? appDic =
            await fieldObject.dictionaryEntry(CraftPdfName.ap);
        CraftPdfObject? asNormal;

        if (appDic != null) {
          asNormal = await appDic.streamEntry(CraftPdfName.n);
          if (asNormal == null) {
            asNormal = await appDic.dictionaryEntry(CraftPdfName.n);
          }
        }

        if (_generateAppearance) {
          if (appDic == null || asNormal == null) {
            await formField.regenerateField();
            appDic = await fieldObject.dictionaryEntry(CraftPdfName.ap);
            if (appDic != null) {
              asNormal = await appDic.get(CraftPdfName.n);
            }
          }
        }

        CraftPdfObject? normal =
            appDic != null ? await appDic.get(CraftPdfName.n) : null;

        if (normal != null) {
          CraftPdfFormXObject? xObject;
          if (normal is CraftPdfStream) {
            xObject = CraftPdfFormXObject.fromStream(normal);
          } else if (normal is CraftPdfDictionary) {
            CraftPdfName? asName = await fieldObject.nameEntry(CraftPdfName.as);
            if (asName != null) {
              CraftPdfStream? stream = await normal.streamEntry(asName);
              if (stream != null) {
                xObject = CraftPdfFormXObject.fromStream(stream);
                xObject.attachToDocument(_document);
              }
            }
          }

          if (xObject != null) {
            // xObject.getPdfObject() deve ser um PdfStream, que suporta put se fizermos cast ou usarmos o helper do wrapper se existir.
            // Mas PdfObjectWrapper geralmente expõe getPdfObject().
            // Streams são dicionários tb.
            xObject
                .pdfRepresentation()
                .put(CraftPdfName.subtype, CraftPdfName.form);
            CraftPdfArray? rectArr =
                await fieldObject.arrayEntry(CraftPdfName.rect);

            if (rectArr != null) {
              // Check if page flushed?
              // if (page.isFlushed()) throw ...

              CraftPdfCanvas canvas = await CraftPdfCanvas.fromPage(page);

              CraftRectangle annotRect =
                  (await CraftRectangle.fromPdfArray(rectArr)) ??
                      CraftRectangle(0, 0, 0, 0);
              CraftAffineTransform at =
                  await CraftPdfFormXObject.calcAppearanceTransformToAnnotRect(
                      xObject, annotRect);

              await canvas.addXObjectWithTransformationMatrix(
                  xObject.pdfRepresentation(),
                  at.m00,
                  at.m10,
                  at.m01,
                  at.m11,
                  at.m02,
                  at.m12);
            }
          }
        }

        // Remove annotation from page
        CraftPdfArray? annots =
            await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
        if (annots != null) {
          annots.remove(widget.pdfRepresentation());
        }

        // Remove field from AcroForm
        CraftPdfArray? fFields = await getFields();
        if (fFields != null) {
          await _removeFieldFromParentAndAcroForm(fFields, fieldObject);
        }
      }
    }

    pdfRepresentation().remove(CraftPdfName.needAppearances);

    if (_fieldsForFlattening.isEmpty) {
      (await getFields())?.clear();
    }

    CraftPdfArray? fields = await getFields();
    if (fields == null || fields.isEmpty()) {
      _document.rootCatalog().pdfRepresentation().remove(CraftPdfName.acroForm);
    }
  }

  Future<Map<String, CraftPdfFormField>> getFormFields() async {
    if (_fieldsLoaded) return _fields;

    CraftPdfArray? fields = await getFields();
    if (fields != null) {
      await _iterateFields(fields, "");
    }
    _fieldsLoaded = true;
    return _fields;
  }

  Future<void> _iterateFields(CraftPdfArray fields, String parentName) async {
    for (int i = 0; i < fields.size(); i++) {
      CraftPdfObject? obj = await fields.get(i);
      if (obj is CraftPdfIndirectReference) {
        obj = await obj.targetObject();
      }
      if (obj is CraftPdfDictionary) {
        await _addFieldToMap(obj, parentName);
      }
    }
  }

  Future<void> _addFieldToMap(
      CraftPdfDictionary fieldDict, String parentName) async {
    CraftPdfFormField field =
        await CraftPdfFormField.makeFormField(fieldDict, _document);
    String partialName = await field.getFieldNameValue();
    String fullName =
        parentName.isEmpty ? partialName : "$parentName.$partialName";

    if (partialName.isNotEmpty) {
      _fields[fullName] = field;
    }

    CraftPdfArray? kids = await fieldDict.arrayEntry(CraftPdfName.kids);
    if (kids != null) {
      await _iterateFields(kids, fullName);
    }
  }

  Future<CraftPdfFormField?> getField(String name) async {
    if (!_fieldsLoaded) await getFormFields();
    return _fields[name];
  }

  Set<CraftPdfFormField> getFieldsForFlattening() {
    return _fieldsForFlattening;
  }

  Future<void> addFieldAppearanceToPage(
      CraftPdfFormField field, CraftPdfPage page) async {
    CraftPdfDictionary fieldDict = field.pdfRepresentation();
    CraftPdfArray? kids = await field.getKids();

    if (kids == null) return;

    if (kids.size() == 1) {
      CraftPdfDictionary? kidDict = await kids.dictionaryEntry(0);
      if (kidDict != null &&
          await CraftPdfFormAnnotationUtil.isPureWidget(kidDict)) {
        await CraftPdfFormAnnotationUtil.mergeWidgetWithParentField(field);
        await _defineWidgetPageAndAddToIt(page, fieldDict);
        return;
      }
    }

    for (int i = 0; i < kids.size(); i++) {
      CraftPdfDictionary? kidDict = await kids.dictionaryEntry(i);
      if (kidDict != null &&
          await CraftPdfFormAnnotationUtil.isPureWidgetOrMergedField(kidDict)) {
        await _defineWidgetPageAndAddToIt(page, kidDict);
      }
    }
  }

  Future<Map<String, CraftPdfFormField>> getRootFormFields() async {
    if (!_fieldsLoaded) await getFormFields();
    Map<String, CraftPdfFormField> rootFields = {};
    for (var entry in _fields.entries) {
      if (await entry.value.getParent() == null) {
        rootFields[entry.key] = entry.value;
      }
    }
    return rootFields;
  }

  Future<Map<String, CraftPdfFormField>> getAllFormFields() async {
    return getFormFields();
  }

  Future<CraftPdfArray?> getFields() async {
    return await pdfRepresentation().arrayEntry(CraftPdfName.fields);
  }

  Future<CraftPdfPage?> _getFieldPage(CraftPdfDictionary annotDict) async {
    CraftPdfDictionary? pageDic =
        await annotDict.dictionaryEntry(CraftPdfName.p);
    if (pageDic != null) {
      return _document.findPageObject(pageDic);
    }
    // Search in pages (expensive)
    for (int i = 1; i <= _document.pageTotal(); i++) {
      CraftPdfPage? page = await _document.pageAt(i);
      if (page == null) continue;
      // Check if page contains this annotation
      CraftPdfArray? annots =
          await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
      if (annots != null && await annots.containsObject(annotDict)) {
        return page;
      }
    }
    return null;
  }

  Future<void> setNeedAppearances(bool needAppearances) async {
    pdfRepresentation()
        .put(CraftPdfName.needAppearances, CraftPdfBoolean(needAppearances));
    markChanged();
  }

  Future<bool> getNeedAppearances() async {
    final b =
        await pdfRepresentation().booleanEntry(CraftPdfName.needAppearances);
    return b?.getValue() ?? false;
  }

  Future<void> setSigFlags(int sigFlags) async {
    pdfRepresentation()
        .put(CraftPdfName.sigFlags, CraftPdfNumber(sigFlags.toDouble()));
    markChanged();
  }

  Future<void> setSignatureFlags(int flags) async {
    setSigFlags(flags);
  }

  Future<void> setGenerateAppearance(bool generateAppearance) async {
    if (generateAppearance) {
      pdfRepresentation().remove(CraftPdfName.needAppearances);
      markChanged();
    }
    _generateAppearance = generateAppearance;
  }

  bool isGenerateAppearance() => _generateAppearance;

  Future<void> setCalculationOrder(CraftPdfArray calculationOrder) async {
    pdfRepresentation().put(CraftPdfName.co, calculationOrder);
    markChanged();
  }

  Future<CraftPdfArray?> getCalculationOrder() async {
    return pdfRepresentation().arrayEntry(CraftPdfName.co);
  }

  Future<void> setDefaultResources(CraftPdfDictionary defaultResources) async {
    pdfRepresentation().put(CraftPdfName.dr, defaultResources);
    markChanged();
  }

  Future<CraftPdfDictionary?> getDefaultResources() async {
    return pdfRepresentation().dictionaryEntry(CraftPdfName.dr);
  }

  Future<void> setDefaultAppearance(String appearance) async {
    pdfRepresentation().put(CraftPdfName.da, CraftPdfString(appearance));
    markChanged();
  }

  Future<CraftPdfString?> getDefaultAppearance() async {
    return pdfRepresentation().stringEntry(CraftPdfName.da);
  }

  Future<void> setDefaultJustification(int justification) async {
    pdfRepresentation()
        .put(CraftPdfName.q, CraftPdfNumber.fromInt(justification));
    markChanged();
  }

  Future<CraftPdfNumber?> getDefaultJustification() async {
    return pdfRepresentation().numberEntry(CraftPdfName.q);
  }

  Future<void> setXfaResource(CraftPdfObject xfaResource) async {
    pdfRepresentation().put(CraftPdfName.xfa, xfaResource);
    markChanged();
  }

  Future<CraftPdfObject?> getXfaResource() async {
    return pdfRepresentation().get(CraftPdfName.xfa);
  }

  Future<bool> hasXfaForm() async {
    return (await getXfaResource()) != null;
  }

  Future<void> removeXfaForm() async {
    pdfRepresentation().remove(CraftPdfName.xfa);
    markChanged();
  }

  /// Adds a form field, identified by name, to the list of fields to be flattened.
  /// Does not perform a flattening operation in itself.
  Future<void> partialFormFlattening(String fieldName) async {
    CraftPdfFormField? field = await getField(fieldName);
    if (field != null) {
      _fieldsForFlattening.add(field);
    }
  }

  Future<void> _populateFormFieldsMap() async {
    await getFormFields();
  }

  /// Gets the SigFlags integer property on the AcroForm.
  /// SigFlags describes signature-related properties of the document;
  /// characteristics related to signature fields.
  int getSignatureFlags() {
    CraftPdfNumber? n =
        pdfRepresentation().getNumberSync(CraftPdfName.sigFlags);
    if (n == null) return 0;
    return n.intValue();
  }

  /// Changes the SigFlags integer property on the AcroForm.
  /// Existing flag bits remain set when additional bits are supplied.
  Future<void> setSignatureFlag(int sigFlag) async {
    int flags = getSignatureFlags();
    flags = flags | sigFlag;
    await setSigFlags(flags);
  }

  /// Assigns a dictionary entry, replacing an earlier value for the same key.
  CraftPdfAcroForm put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  /// Gets all form fields as a Set including fields kids and nameless fields.
  Future<Set<CraftAbstractPdfFormField>>
      getAllFormFieldsAndAnnotations() async {
    Set<CraftAbstractPdfFormField> allFields = {};
    if (!_fieldsLoaded) await getFormFields();

    for (var field in _fields.values) {
      allFields.add(field);
      await _collectChildFields(field, allFields);
    }
    return allFields;
  }

  Future<void> _collectChildFields(
      CraftPdfFormField field, Set<CraftAbstractPdfFormField> allFields) async {
    CraftPdfArray? kids = await field.getKids();
    if (kids == null) return;

    for (int i = 0; i < kids.size(); i++) {
      CraftPdfDictionary? kidDict = await kids.dictionaryEntry(i);
      if (kidDict != null) {
        CraftPdfFormField childField =
            await CraftPdfFormField.makeFormField(kidDict, _document);
        allFields.add(childField);
        await _collectChildFields(childField, allFields);
      }
    }
  }

  /// Disables appearance stream regeneration for all the root fields in the Acroform,
  /// so all of its children in the hierarchy will also not be regenerated.
  Future<void> disableRegenerationForAllFields() async {
    Map<String, CraftPdfFormField> rootFields = await getRootFormFields();
    for (var field in rootFields.values) {
      await field.disableFieldRegeneration();
    }
  }

  /// Turns on field appearance generation and requests regeneration.
  Future<void> enableRegenerationForAllFields() async {
    Map<String, CraftPdfFormField> rootFields = await getRootFormFields();
    for (var field in rootFields.values) {
      await field.enableFieldRegeneration();
    }
  }

  /// Gets the field page from a field dictionary.
  Future<CraftPdfPage?> getFieldPage(CraftPdfDictionary fieldDict) async {
    return _getFieldPage(fieldDict);
  }

  /// Removes a field from its parent and from the AcroForm fields array.
  Future<void> _removeFieldFromParentAndAcroForm(
      CraftPdfArray formFields, CraftPdfDictionary fieldObject) async {
    formFields.remove(fieldObject);
    CraftPdfDictionary? parent =
        await fieldObject.dictionaryEntry(CraftPdfName.parent);
    if (parent != null) {
      CraftPdfArray? kids = await parent.arrayEntry(CraftPdfName.kids);
      if (kids == null) {
        formFields.remove(parent);
      } else {
        kids.remove(fieldObject);
        if (kids.isEmpty()) {
          await _removeFieldFromParentAndAcroForm(formFields, parent);
        }
      }
    }
  }

  /// Prepares fields for flattening by collecting all child form annotations.
  Future<List<CraftPdfFormField>> _prepareFieldsForFlattening(
      CraftPdfFormField field) async {
    List<CraftPdfFormField> result = [];

    CraftPdfArray? kids = await field.getKids();
    if (kids == null || kids.isEmpty()) {
      result.add(field);
    } else {
      for (int i = 0; i < kids.size(); i++) {
        CraftPdfDictionary? kidDict = await kids.dictionaryEntry(i);
        if (kidDict != null) {
          CraftPdfFormField childField =
              await CraftPdfFormField.makeFormField(kidDict, _document);
          result.addAll(await _prepareFieldsForFlattening(childField));
        }
      }
    }

    return result;
  }

  /// Checks if this AcroForm needs appearances to be generated.
  bool needsAppearances() {
    CraftPdfBoolean? na =
        pdfRepresentation().getBooleanSync(CraftPdfName.needAppearances);
    if (na == null) return false;
    return na.getValue();
  }

  /// Releases the PDF entities held by this wrapper.
  void release() {
    _fields.clear();
    _fieldsForFlattening.clear();
    _fieldsLoaded = false;
    pdfRepresentation().release();
  }

  /// Check if a field name already exists in the form.
  Future<bool> containsField(String fieldName) async {
    if (!_fieldsLoaded) await getFormFields();
    return _fields.containsKey(fieldName);
  }

  /// Gets the number of top-level fields in the form.
  Future<int> getFieldCount() async {
    CraftPdfArray? fields = await getFields();
    return fields?.size() ?? 0;
  }

  /// Clears the internal fields cache, forcing a reload on next access.
  void clearFieldsCache() {
    _fields.clear();
    _fieldsLoaded = false;
  }
}
