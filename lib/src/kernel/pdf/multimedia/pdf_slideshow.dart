import '../pdf_array.dart';
import '../pdf_catalog.dart';
import '../pdf_dictionary.dart';
import '../pdf_document.dart';
import '../pdf_name.dart';
import '../pdf_name_tree.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// Slideshow dictionary, the only kind of alternate presentation PDF 1.5
/// defines.
///
/// See ISO 32000-1:2008, 13.5 "Alternate Presentations", Table 297. The
/// `/Resources` name tree is a flat virtual file system: it maps "file names"
/// to the objects the slideshow loads, and `/StartResource` names the root
/// object among them.
class PdfSlideShow extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /SlideShow`, required by Table 297.
  static final PdfName typeValue = PdfName.intern('SlideShow');

  /// `/Subtype /Embedded`, required by Table 297.
  static final PdfName subtypeEmbedded = PdfName.intern('Embedded');

  /// The `/AlternatePresentations` name tree of the document name dictionary
  /// (Table 31).
  static final PdfName alternatePresentationsTree =
      PdfName.intern('AlternatePresentations');

  static final PdfName _resources = PdfName.intern('Resources');
  static final PdfName _startResource = PdfName.intern('StartResource');

  PdfSlideShow(super.pdfObject);

  /// Creates a slideshow whose root object is the resource named
  /// [startResource]. Table 297 makes `/Type`, `/Subtype`, `/Resources` and
  /// `/StartResource` all required, and requires `/StartResource` to match
  /// one of the names in `/Resources`.
  PdfSlideShow.create(String startResource, Map<String, PdfObject> resources)
      : super(PdfDictionary()) {
    if (!resources.containsKey(startResource)) {
      throw ArgumentError.value(
          startResource,
          'startResource',
          'Slideshow /StartResource shall match one of the strings in '
              '/Resources (Table 297)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, subtypeEmbedded)
      ..put(_resources, _buildResources(resources))
      ..put(_startResource, PdfString(startResource));
  }

  /// A slideshow is referenced from the `/AlternatePresentations` name tree,
  /// whose values shall be indirect objects.
  @override
  bool requiresIndirectStorage() => true;

  /// Gets `/StartResource`, the name of the root object.
  Future<String?> getStartResource() async =>
      (await pdfRepresentation().stringEntry(_startResource))?.getValue();

  /// Gets `/Resources`, the name tree holding the slideshow's virtual file
  /// system.
  Future<PdfDictionary?> getResourcesTree() async =>
      await pdfRepresentation().dictionaryEntry(_resources);

  /// Gets the names present in `/Resources`. NOTE 1 of Table 297 says the
  /// slideshow interprets them as UTF-8 encoded Unicode.
  Future<List<String>> getResourceNames() async =>
      (await _readResources()).keys.toList();

  /// Gets the resource registered under [name], or null when absent.
  Future<PdfObject?> getResource(String name) async =>
      (await _readResources())[name];

  /// Gets the object named by `/StartResource`.
  Future<PdfObject?> getStartObject() async {
    final name = await getStartResource();
    return name == null ? null : await getResource(name);
  }

  /// Reports whether the structural requirement of Table 297 still holds
  /// after the dictionary has been read back: `/StartResource` names an entry
  /// that is actually present in `/Resources`.
  Future<bool> isStructurallyValid() async {
    final name = await getStartResource();
    if (name == null) return false;
    return (await _readResources()).containsKey(name);
  }

  /// Registers this slideshow in the document's `/AlternatePresentations`
  /// name tree (Table 31) under [name], the mapping 13.5 describes.
  Future<PdfSlideShow> registerIn(PdfDocument document, String name) async {
    attachToDocument(document);
    final PdfCatalog catalog = document.rootCatalog();
    await catalog.addNameToNameTree(
        PdfString(name), pdfRepresentation(), alternatePresentationsTree);
    return this;
  }

  /// Reads the slideshow registered in [document] under [name], or null when
  /// the document holds no such alternate presentation.
  static Future<PdfSlideShow?> read(PdfDocument document, String name) async {
    final catalog = document.rootCatalog();
    final tree = await PdfNameTree.create(catalog, alternatePresentationsTree);
    final entry = await tree.getEntry(PdfString(name));
    final resolved =
        entry is PdfIndirectReference ? await entry.targetObject(true) : entry;
    if (resolved is! PdfDictionary) return null;
    return PdfSlideShow(resolved);
  }

  Future<Map<String, PdfObject>> _readResources() async {
    final tree = await getResourcesTree();
    if (tree == null) return const <String, PdfObject>{};
    final result = <String, PdfObject>{};
    await _collect(tree, result);
    return result;
  }

  static Future<void> _collect(
      PdfDictionary node, Map<String, PdfObject> into) async {
    final names = await node.arrayEntry(PdfName.names);
    if (names != null) {
      for (var i = 0; i + 1 < names.size(); i += 2) {
        final key = await names.stringEntry(i);
        final value = await names.get(i + 1, true);
        if (key != null && value != null) into[key.getValue()] = value;
      }
    }
    final kids = await node.arrayEntry(PdfName.kids);
    if (kids == null) return;
    for (var i = 0; i < kids.size(); i++) {
      final kid = await kids.dictionaryEntry(i);
      if (kid != null) await _collect(kid, into);
    }
  }

  static PdfDictionary _buildResources(Map<String, PdfObject> resources) {
    final names = PdfArray();
    final ordered = resources.keys.toList()..sort();
    for (final name in ordered) {
      names.add(PdfString(name));
      names.add(resources[name]!);
    }
    return PdfDictionary()..put(PdfName.names, names);
  }
}
