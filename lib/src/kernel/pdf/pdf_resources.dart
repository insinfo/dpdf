import 'pdf_object.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

/// Wrapper class that represent resource dictionary.
class CraftPdfResources extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  static const String _f = "F";
  static const String _im = "Im";
  static const String _fm = "Fm";
  static const String _gs = "Gs";
  static const String _pr = "Pr";
  static const String _cs = "Cs";
  static const String _p = "P";
  static const String _sh = "Sh";

  final Map<CraftPdfObject, CraftPdfName> _resourceToName = {};

  late final ResourceNameGenerator _fontNamesGen =
      ResourceNameGenerator(CraftPdfName.font, _f);

  late final ResourceNameGenerator _imageNamesGen =
      ResourceNameGenerator(CraftPdfName.xObject, _im);

  late final ResourceNameGenerator _formNamesGen =
      ResourceNameGenerator(CraftPdfName.xObject, _fm);

  late final ResourceNameGenerator _egsNamesGen =
      ResourceNameGenerator(CraftPdfName.extGState, _gs);

  late final ResourceNameGenerator _propNamesGen =
      ResourceNameGenerator(CraftPdfName.properties, _pr);

  late final ResourceNameGenerator _csNamesGen =
      ResourceNameGenerator(CraftPdfName.colorSpace, _cs);

  late final ResourceNameGenerator _patternNamesGen =
      ResourceNameGenerator(CraftPdfName.pattern, _p);

  late final ResourceNameGenerator _shadingNamesGen =
      ResourceNameGenerator(CraftPdfName.shading, _sh);

  bool _readOnly = false;
  bool _isModified = false;

  CraftPdfResources([CraftPdfDictionary? pdfObject])
      : super(pdfObject ?? CraftPdfDictionary());

  /// Initializes the resources by building the internal map from the dictionary.
  Future<void> init() async {
    await _buildResources(pdfRepresentation());
  }

  @override
  bool requiresIndirectStorage() => false;

  bool isReadOnly() => _readOnly;
  void setReadOnly(bool readOnly) => _readOnly = readOnly;

  bool hasChanges() => _isModified;

  @override
  CraftPdfObjectWrapper<CraftPdfDictionary> markChanged() {
    _isModified = true;
    return super.markChanged();
  }

  Future<CraftPdfName> addResource(CraftPdfObject resource,
      CraftPdfName resType, CraftPdfName resName) async {
    if (_readOnly) {
      _readOnly = false;
      final clonedDict = pdfRepresentation().clone() as CraftPdfDictionary;
      setPdfObject(clonedDict);
    }

    final category = await pdfRepresentation().dictionaryEntry(resType);
    if (category != null && category.containsKey(resName)) {
      return resName;
    }

    _resourceToName[resource] = resName;
    var resourceCategory = await pdfRepresentation().dictionaryEntry(resType);
    if (resourceCategory == null) {
      resourceCategory = CraftPdfDictionary();
      pdfRepresentation().put(resType, resourceCategory);
    } else {
      resourceCategory.markChanged();
    }
    resourceCategory.put(resName, resource);
    markChanged();
    return resName;
  }

  Future<CraftPdfName> registerTypeface(
      CraftPdfDocument document, CraftPdfFont font) async {
    document.registerTypeface(font);
    return addResource(font.pdfRepresentation(), CraftPdfName.font,
        await _fontNamesGen.generate(this));
  }

  Future<CraftPdfName> addXObject(
      CraftPdfDocument document, CraftPdfStream xObject) async {
    final subtype = await xObject.nameEntry(CraftPdfName.subtype);
    final gen = subtype == CraftPdfName.form ? _formNamesGen : _imageNamesGen;
    return addResource(xObject, CraftPdfName.xObject, await gen.generate(this));
  }

  Future<CraftPdfName> addExtGState(
      CraftPdfDocument document, CraftPdfObject gs) async {
    return addResource(
        gs, CraftPdfName.extGState, await _egsNamesGen.generate(this));
  }

  Future<CraftPdfName> addProperties(
      CraftPdfDocument document, CraftPdfObject props) async {
    return addResource(
        props, CraftPdfName.properties, await _propNamesGen.generate(this));
  }

  Future<CraftPdfName> addColorSpace(
      CraftPdfDocument document, CraftPdfObject cs) async {
    return addResource(
        cs, CraftPdfName.colorSpace, await _csNamesGen.generate(this));
  }

  Future<CraftPdfName> addShading(
      CraftPdfDocument document, CraftPdfObject shading) async {
    return addResource(
        shading, CraftPdfName.shading, await _shadingNamesGen.generate(this));
  }

  Future<CraftPdfName> addPattern(
      CraftPdfDocument document, CraftPdfObject pattern) async {
    return addResource(
        pattern, CraftPdfName.pattern, await _patternNamesGen.generate(this));
  }

  CraftPdfName getResourceName(CraftPdfObject resource) {
    var resName = _resourceToName[resource];
    return resName ?? CraftPdfName('');
  }

  Future<void> _buildResources(CraftPdfDictionary dictionary) async {
    for (final resourceType in dictionary.keySet()) {
      final resources = await dictionary.dictionaryEntry(resourceType);
      if (resources == null) continue;
      for (final resourceName in resources.keySet()) {
        final resource = await resources.get(resourceName, false);
        if (resource != null) {
          _resourceToName[resource] = resourceName;
        }
      }
    }
  }
}

/// Resource name generator.
class ResourceNameGenerator {
  final CraftPdfName resourceType;
  final String prefix;
  int _counter;

  ResourceNameGenerator(this.resourceType, this.prefix, [this._counter = 1]);

  Future<CraftPdfName> generate(CraftPdfResources resources) async {
    var newName = CraftPdfName('$prefix$_counter');
    _counter++;
    final r = resources.pdfRepresentation();
    if (r.containsKey(resourceType)) {
      final category = await r.dictionaryEntry(resourceType);
      if (category != null) {
        while (category.containsKey(newName)) {
          newName = CraftPdfName('$prefix$_counter');
          _counter++;
        }
      }
    }
    return newName;
  }
}
