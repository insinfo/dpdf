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

class PdfAcroForm extends PdfObjectWrapper<PdfDictionary> {
  final Map<String, PdfFormField> _fields = {};
  final Set<PdfFormField> _fieldsForFlattening = {};
  bool _fieldsLoaded = false;
  static const int SIGNATURE_EXIST = 1;
  static const int APPEND_ONLY = 2;

  final PdfDocument _document;
  bool _generateAppearance = true;
  XfaForm? _xfaForm;

  PdfAcroForm(PdfDictionary pdfObject, PdfDocument pdfDocument)
      : _document = pdfDocument,
        super(pdfObject);

  PdfDocument getPdfDocument() => _document;

  static Future<PdfAcroForm> makeAcroForm(PdfDocument document) =>
      getAcroForm(document, true);

  static Future<PdfAcroForm> getAcroForm(
      PdfDocument document, bool createIfNotExist) async {
    PdfDictionary? catalogDict = document.rootCatalog().pdfRepresentation();
    PdfDictionary? acroFormDict =
        await catalogDict.dictionaryEntry(PdfName.acroForm);

    if (acroFormDict == null && createIfNotExist) {
      acroFormDict = PdfDictionary();
      catalogDict.put(PdfName.acroForm, acroFormDict);
      acroFormDict.attachToDocument(document);
      catalogDict.markChanged();
    }

    if (acroFormDict == null) {
      throw StateError("AcroForm not found");
    }

    return PdfAcroForm(acroFormDict, document);
  }

  @override
  bool requiresIndirectStorage() => true;

  Future<void> addField(PdfFormField field, [PdfPage? page]) async {
    await _addFieldInternal(field);
    if (page != null) {
      for (final widget in await field.getWidgets()) {
        await _defineWidgetPageAndAddToIt(page, widget.pdfRepresentation());
      }
    }
  }

  Future<void> _addFieldInternal(PdfFormField field) async {
    PdfString? name = await field.getFieldName();
    if (name == null) {
      throw ArgumentError("Form field must have a name");
    }

    PdfArray? fields = await pdfRepresentation().arrayEntry(PdfName.fields);
    if (fields == null) {
      fields = PdfArray();
      pdfRepresentation().put(PdfName.fields, fields);
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
      PdfPage page, PdfDictionary widgetDict) async {
    // Add 'P' (Page) reference to the widget dictionary
    widgetDict.put(PdfName.p, page.pdfRepresentation().indirectHandle()!);

    // Wrap it in a PdfWidgetAnnotation and add to page
    // We assume widgetDict IS the annotation dictionary for terminal fields
    final widgetAnnot = PdfWidgetAnnotation(widgetDict);
    await page.addAnnotation(widgetAnnot);
  }

  Future<XfaForm?> getXfaForm() async {
    if (_xfaForm == null) {
      PdfObject? xfa = await pdfRepresentation().get(PdfName.xfa);
      if (xfa != null) {
        _xfaForm = await XfaForm.createFromPdfDictionary(pdfRepresentation());
      }
    }
    return _xfaForm;
  }

  /// Sets the [XfaForm].
  Future<void> setXfaForm(XfaForm xfaForm) async {
    _xfaForm = xfaForm;
    await XfaForm.setXfaFormWithAcroForm(xfaForm, this);
  }

  Future<bool> removeField(String fieldName) async {
    PdfFormField? field = await getField(fieldName);
    if (field == null) {
      return false;
    }

    PdfDictionary fieldObject = field.pdfRepresentation();
    PdfPage? page = await _getFieldPage(fieldObject);

    // Remove annotation from page
    if (page != null) {
      PdfArray? annots =
          await page.pdfRepresentation().arrayEntry(PdfName.annots);
      if (annots != null) {
        await annots.remove(fieldObject);
      }
    }

    PdfDictionary? parent = await field.getParent();
    PdfFormField? parentField = field.getParentField();

    if (parentField != null) {
      await parentField.removeChild(field);
    } else if (parent != null) {
      PdfArray? kids = await parent.arrayEntry(PdfName.kids);
      if (kids != null) {
        await kids.remove(fieldObject);
        kids.markChanged();
      }
      parent.markChanged();
      return true;
    }

    PdfArray? fieldsArray = await getFields();
    if (fieldsArray != null && await fieldsArray.containsObject(fieldObject)) {
      await fieldsArray.remove(fieldObject);
      _fields.remove(fieldName);
      fieldsArray.markChanged();
      markChanged();
      return true;
    }

    return false;
  }

  Future<void> replaceField(String name, PdfFormField field) async {
    // PdfFormField? oldField = await getField(name);
    await removeField(name);
    int lastDot = name.lastIndexOf('.');
    if (lastDot == -1) {
      await addField(field);
    } else {
      String parentName = name.substring(0, lastDot);
      PdfFormField? parent = await getField(parentName);
      if (parent == null) {
        await addField(field);
      } else {
        await parent.addChildField(field);
      }
    }
  }

  Future<bool> renameField(String oldName, String newName) async {
    PdfFormField? field = await getField(oldName);
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

  Future<PdfFormField?> copyField(String name) async {
    PdfFormField? field = await getField(name);
    if (field == null) return null;
    PdfObject cloned = field.pdfRepresentation().clone();
    if (cloned is PdfDictionary) {
      return PdfFormField.makeFormField(cloned, _document);
    }
    return null;
  }

  Future<void> flattenFields() async {
    if (_document.usesIncrementalRevision()) {
      throw Exception(
          "Flattening fields requires rewriting the document instead of appending a revision.");
    }

    Set<PdfFormField> fieldsToFlatten = {};
    if (_fieldsForFlattening.isEmpty) {
      if (!_fieldsLoaded) {
        await getFormFields();
      }
      // Se não especificou campos, achata todos.
      // Precisamos de todos, incluindo os sem nome e filhos.
      fieldsToFlatten
          .addAll(await getAllFormFieldsAndAnnotations() as Set<PdfFormField>);
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
      List<PdfWidgetAnnotation> widgets = await formField.getWidgets();

      for (var widget in widgets) {
        PdfDictionary fieldObject = widget.pdfRepresentation();
        PdfPage? page = await widget.pageAt();
        page ??= await _getFieldPage(fieldObject);

        if (page == null) continue;

        PdfDictionary? appDic = await fieldObject.dictionaryEntry(PdfName.ap);
        PdfObject? asNormal;

        if (appDic != null) {
          asNormal = await appDic.streamEntry(PdfName.n);
          asNormal ??= await appDic.dictionaryEntry(PdfName.n);
        }

        if (_generateAppearance) {
          if (appDic == null || asNormal == null) {
            await formField.regenerateField();
            appDic = await fieldObject.dictionaryEntry(PdfName.ap);
            if (appDic != null) {
              asNormal = await appDic.get(PdfName.n);
            }
          }
        }

        PdfObject? normal = appDic != null ? await appDic.get(PdfName.n) : null;

        if (normal != null) {
          PdfFormXObject? xObject;
          if (normal is PdfStream) {
            xObject = PdfFormXObject.fromStream(normal);
          } else if (normal is PdfDictionary) {
            PdfName? asName = await fieldObject.nameEntry(PdfName.as);
            if (asName != null) {
              PdfStream? stream = await normal.streamEntry(asName);
              if (stream != null) {
                xObject = PdfFormXObject.fromStream(stream);
                xObject.attachToDocument(_document);
              }
            }
          }

          if (xObject != null) {
            // xObject.getPdfObject() deve ser um PdfStream, que suporta put se fizermos cast ou usarmos o helper do wrapper se existir.
            // Mas PdfObjectWrapper geralmente expõe getPdfObject().
            // Streams são dicionários tb.
            xObject.pdfRepresentation().put(PdfName.subtype, PdfName.form);
            PdfArray? rectArr = await fieldObject.arrayEntry(PdfName.rect);

            if (rectArr != null) {
              // Check if page flushed?
              // if (page.isFlushed()) throw ...

              PdfCanvas canvas = await PdfCanvas.fromPage(page);

              Rectangle annotRect = (await Rectangle.fromPdfArray(rectArr)) ??
                  Rectangle(0, 0, 0, 0);
              AffineTransform at =
                  await PdfFormXObject.calcAppearanceTransformToAnnotRect(
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
        PdfArray? annots =
            await page.pdfRepresentation().arrayEntry(PdfName.annots);
        if (annots != null) {
          annots.remove(widget.pdfRepresentation());
        }

        // Remove field from AcroForm
        PdfArray? fFields = await getFields();
        if (fFields != null) {
          await _removeFieldFromParentAndAcroForm(fFields, fieldObject);
        }
      }
    }

    pdfRepresentation().remove(PdfName.needAppearances);

    if (_fieldsForFlattening.isEmpty) {
      (await getFields())?.clear();
    }

    PdfArray? fields = await getFields();
    if (fields == null || fields.isEmpty()) {
      _document.rootCatalog().pdfRepresentation().remove(PdfName.acroForm);
    }
  }

  Future<Map<String, PdfFormField>> getFormFields() async {
    if (_fieldsLoaded) return _fields;

    PdfArray? fields = await getFields();
    if (fields != null) {
      await _iterateFields(fields, "");
    }
    _fieldsLoaded = true;
    return _fields;
  }

  Future<void> _iterateFields(PdfArray fields, String parentName) async {
    for (int i = 0; i < fields.size(); i++) {
      PdfObject? obj = await fields.get(i);
      if (obj is PdfIndirectReference) {
        obj = await obj.targetObject();
      }
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

    PdfArray? kids = await fieldDict.arrayEntry(PdfName.kids);
    if (kids != null) {
      await _iterateFields(kids, fullName);
    }
  }

  Future<PdfFormField?> getField(String name) async {
    if (!_fieldsLoaded) await getFormFields();
    return _fields[name];
  }

  Set<PdfFormField> getFieldsForFlattening() {
    return _fieldsForFlattening;
  }

  Future<void> addFieldAppearanceToPage(
      PdfFormField field, PdfPage page) async {
    PdfDictionary fieldDict = field.pdfRepresentation();
    PdfArray? kids = await field.getKids();

    if (kids == null) return;

    if (kids.size() == 1) {
      PdfDictionary? kidDict = await kids.dictionaryEntry(0);
      if (kidDict != null &&
          await PdfFormAnnotationUtil.isPureWidget(kidDict)) {
        await PdfFormAnnotationUtil.mergeWidgetWithParentField(field);
        await _defineWidgetPageAndAddToIt(page, fieldDict);
        return;
      }
    }

    for (int i = 0; i < kids.size(); i++) {
      PdfDictionary? kidDict = await kids.dictionaryEntry(i);
      if (kidDict != null &&
          await PdfFormAnnotationUtil.isPureWidgetOrMergedField(kidDict)) {
        await _defineWidgetPageAndAddToIt(page, kidDict);
      }
    }
  }

  Future<Map<String, PdfFormField>> getRootFormFields() async {
    if (!_fieldsLoaded) await getFormFields();
    Map<String, PdfFormField> rootFields = {};
    for (var entry in _fields.entries) {
      if (await entry.value.getParent() == null) {
        rootFields[entry.key] = entry.value;
      }
    }
    return rootFields;
  }

  Future<Map<String, PdfFormField>> getAllFormFields() async {
    return getFormFields();
  }

  Future<PdfArray?> getFields() async {
    return await pdfRepresentation().arrayEntry(PdfName.fields);
  }

  Future<PdfPage?> _getFieldPage(PdfDictionary annotDict) async {
    PdfDictionary? pageDic = await annotDict.dictionaryEntry(PdfName.p);
    if (pageDic != null) {
      return _document.findPageObject(pageDic);
    }
    // Search in pages (expensive)
    for (int i = 1; i <= _document.pageTotal(); i++) {
      PdfPage? page = await _document.pageAt(i);
      if (page == null) continue;
      // Check if page contains this annotation
      PdfArray? annots =
          await page.pdfRepresentation().arrayEntry(PdfName.annots);
      if (annots != null && await annots.containsObject(annotDict)) {
        return page;
      }
    }
    return null;
  }

  Future<void> setNeedAppearances(bool needAppearances) async {
    pdfRepresentation()
        .put(PdfName.needAppearances, PdfBoolean(needAppearances));
    markChanged();
  }

  Future<bool> getNeedAppearances() async {
    final b = await pdfRepresentation().booleanEntry(PdfName.needAppearances);
    return b?.getValue() ?? false;
  }

  Future<void> setSigFlags(int sigFlags) async {
    pdfRepresentation().put(PdfName.sigFlags, PdfNumber(sigFlags.toDouble()));
    markChanged();
  }

  Future<void> setSignatureFlags(int flags) async {
    setSigFlags(flags);
  }

  Future<void> setGenerateAppearance(bool generateAppearance) async {
    if (generateAppearance) {
      pdfRepresentation().remove(PdfName.needAppearances);
      markChanged();
    }
    _generateAppearance = generateAppearance;
  }

  bool isGenerateAppearance() => _generateAppearance;

  Future<void> setCalculationOrder(PdfArray calculationOrder) async {
    pdfRepresentation().put(PdfName.co, calculationOrder);
    markChanged();
  }

  Future<PdfArray?> getCalculationOrder() async {
    return pdfRepresentation().arrayEntry(PdfName.co);
  }

  Future<void> setDefaultResources(PdfDictionary defaultResources) async {
    pdfRepresentation().put(PdfName.dr, defaultResources);
    markChanged();
  }

  Future<PdfDictionary?> getDefaultResources() async {
    return pdfRepresentation().dictionaryEntry(PdfName.dr);
  }

  Future<void> setDefaultAppearance(String appearance) async {
    pdfRepresentation().put(PdfName.da, PdfString(appearance));
    markChanged();
  }

  Future<PdfString?> getDefaultAppearance() async {
    return pdfRepresentation().stringEntry(PdfName.da);
  }

  Future<void> setDefaultJustification(int justification) async {
    pdfRepresentation().put(PdfName.q, PdfNumber.fromInt(justification));
    markChanged();
  }

  Future<PdfNumber?> getDefaultJustification() async {
    return pdfRepresentation().numberEntry(PdfName.q);
  }

  Future<void> setXfaResource(PdfObject xfaResource) async {
    pdfRepresentation().put(PdfName.xfa, xfaResource);
    markChanged();
  }

  Future<PdfObject?> getXfaResource() async {
    return pdfRepresentation().get(PdfName.xfa);
  }

  Future<bool> hasXfaForm() async {
    return (await getXfaResource()) != null;
  }

  Future<void> removeXfaForm() async {
    pdfRepresentation().remove(PdfName.xfa);
    markChanged();
  }

  /// Adds a form field, identified by name, to the list of fields to be flattened.
  /// Does not perform a flattening operation in itself.
  Future<void> partialFormFlattening(String fieldName) async {
    PdfFormField? field = await getField(fieldName);
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
    PdfNumber? n = pdfRepresentation().getNumberSync(PdfName.sigFlags);
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
  PdfAcroForm put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  /// Gets all form fields as a Set including fields kids and nameless fields.
  Future<Set<AbstractPdfFormField>> getAllFormFieldsAndAnnotations() async {
    Set<AbstractPdfFormField> allFields = {};
    if (!_fieldsLoaded) await getFormFields();

    for (var field in _fields.values) {
      allFields.add(field);
      await _collectChildFields(field, allFields);
    }
    return allFields;
  }

  Future<void> _collectChildFields(
      PdfFormField field, Set<AbstractPdfFormField> allFields) async {
    PdfArray? kids = await field.getKids();
    if (kids == null) return;

    for (int i = 0; i < kids.size(); i++) {
      PdfDictionary? kidDict = await kids.dictionaryEntry(i);
      if (kidDict != null) {
        PdfFormField childField =
            await PdfFormField.makeFormField(kidDict, _document);
        allFields.add(childField);
        await _collectChildFields(childField, allFields);
      }
    }
  }

  /// Disables appearance stream regeneration for all the root fields in the Acroform,
  /// so all of its children in the hierarchy will also not be regenerated.
  Future<void> disableRegenerationForAllFields() async {
    Map<String, PdfFormField> rootFields = await getRootFormFields();
    for (var field in rootFields.values) {
      await field.disableFieldRegeneration();
    }
  }

  /// Turns on field appearance generation and requests regeneration.
  Future<void> enableRegenerationForAllFields() async {
    Map<String, PdfFormField> rootFields = await getRootFormFields();
    for (var field in rootFields.values) {
      await field.enableFieldRegeneration();
    }
  }

  /// Gets the field page from a field dictionary.
  Future<PdfPage?> getFieldPage(PdfDictionary fieldDict) async {
    return _getFieldPage(fieldDict);
  }

  /// Removes a field from its parent and from the AcroForm fields array.
  Future<void> _removeFieldFromParentAndAcroForm(
      PdfArray formFields, PdfDictionary fieldObject) async {
    formFields.remove(fieldObject);
    PdfDictionary? parent = await fieldObject.dictionaryEntry(PdfName.parent);
    if (parent != null) {
      PdfArray? kids = await parent.arrayEntry(PdfName.kids);
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
  Future<List<PdfFormField>> _prepareFieldsForFlattening(
      PdfFormField field) async {
    List<PdfFormField> result = [];

    PdfArray? kids = await field.getKids();
    if (kids == null || kids.isEmpty()) {
      result.add(field);
    } else {
      for (int i = 0; i < kids.size(); i++) {
        PdfDictionary? kidDict = await kids.dictionaryEntry(i);
        if (kidDict != null) {
          PdfFormField childField =
              await PdfFormField.makeFormField(kidDict, _document);
          result.addAll(await _prepareFieldsForFlattening(childField));
        }
      }
    }

    return result;
  }

  /// Checks if this AcroForm needs appearances to be generated.
  bool needsAppearances() {
    PdfBoolean? na =
        pdfRepresentation().getBooleanSync(PdfName.needAppearances);
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
    PdfArray? fields = await getFields();
    return fields?.size() ?? 0;
  }

  /// Clears the internal fields cache, forcing a reload on next access.
  void clearFieldsCache() {
    _fields.clear();
    _fieldsLoaded = false;
  }
}
