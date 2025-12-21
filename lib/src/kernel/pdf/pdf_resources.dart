import 'pdf_object.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';

/// Wrapper class that represent resource dictionary.
class PdfResources extends PdfObjectWrapper<PdfDictionary> {
  static const String _f = "F";
  static const String _im = "Im";
  static const String _fm = "Fm";
  static const String _gs = "Gs";
  static const String _pr = "Pr";
  static const String _cs = "Cs";
  static const String _p = "P";
  static const String _sh = "Sh";

  final Map<PdfObject, PdfName> _resourceToName = {};

  late final ResourceNameGenerator _fontNamesGen =
      ResourceNameGenerator(PdfName.font, _f);

  late final ResourceNameGenerator _imageNamesGen =
      ResourceNameGenerator(PdfName.xObject, _im);

  late final ResourceNameGenerator _formNamesGen =
      ResourceNameGenerator(PdfName.xObject, _fm);

  late final ResourceNameGenerator _egsNamesGen =
      ResourceNameGenerator(PdfName.extGState, _gs);

  late final ResourceNameGenerator _propNamesGen =
      ResourceNameGenerator(PdfName.properties, _pr);

  late final ResourceNameGenerator _csNamesGen =
      ResourceNameGenerator(PdfName.colorSpace, _cs);

  late final ResourceNameGenerator _patternNamesGen =
      ResourceNameGenerator(PdfName.pattern, _p);

  late final ResourceNameGenerator _shadingNamesGen =
      ResourceNameGenerator(PdfName.shading, _sh);

  bool _readOnly = false;
  bool _isModified = false;

  PdfResources([PdfDictionary? pdfObject])
      : super(pdfObject ?? PdfDictionary()) {
    // Avoid unused field warnings
    _fontNamesGen;
    _imageNamesGen;
    _formNamesGen;
    _egsNamesGen;
    _propNamesGen;
    _csNamesGen;
    _patternNamesGen;
    _shadingNamesGen;
  }

  /// Initializes the resources by building the internal map from the dictionary.
  Future<void> init() async {
    await _buildResources(getPdfObject());
  }

  @override
  bool isWrappedObjectMustBeIndirect() => false;

  bool isReadOnly() => _readOnly;
  void setReadOnly(bool readOnly) => _readOnly = readOnly;

  bool isModified() => _isModified;

  @override
  PdfObjectWrapper<PdfDictionary> setModified() {
    _isModified = true;
    return super.setModified();
  }

  Future<PdfName> addResource(
      PdfObject resource, PdfName resType, PdfName resName) async {
    if (_readOnly) {
      // TODO: Implement cloning for read-only resources
    }

    final category = await getPdfObject().getAsDictionary(resType);
    if (category != null && category.containsKey(resName)) {
      return resName;
    }

    _resourceToName[resource] = resName;
    var resourceCategory = await getPdfObject().getAsDictionary(resType);
    if (resourceCategory == null) {
      resourceCategory = PdfDictionary();
      getPdfObject().put(resType, resourceCategory);
    } else {
      resourceCategory.setModified();
    }
    resourceCategory.put(resName, resource);
    setModified();
    return resName;
  }

  PdfName getResourceName(PdfObject resource) {
    var resName = _resourceToName[resource];
    return resName ?? PdfName('');
  }

  Future<void> _buildResources(PdfDictionary dictionary) async {
    for (final resourceType in dictionary.keySet()) {
      final resources = await dictionary.getAsDictionary(resourceType);
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
  final PdfName resourceType;
  final String prefix;
  int _counter;

  ResourceNameGenerator(this.resourceType, this.prefix, [this._counter = 1]);

  Future<PdfName> generate(PdfResources resources) async {
    var newName = PdfName('$prefix$_counter');
    _counter++;
    final r = resources.getPdfObject();
    if (r.containsKey(resourceType)) {
      final category = await r.getAsDictionary(resourceType);
      if (category != null) {
        while (category.containsKey(newName)) {
          newName = PdfName('$prefix$_counter');
          _counter++;
        }
      }
    }
    return newName;
  }
}
