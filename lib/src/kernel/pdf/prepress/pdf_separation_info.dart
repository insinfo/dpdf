import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_page.dart';
import '../pdf_string.dart';

/// A separation dictionary.
///
/// ISO 32000-1:2008, 14.11.4 "Separation Dictionaries", Table 364. It is the
/// `/SeparationInfo` entry of a page object (Table 30) in a preseparated PDF
/// file, where every separation of a document page is a page object of its own
/// painting a single colorant.
///
/// The three entries are:
///
/// * `/Pages` (required) - the page objects of all the separations of the same
///   document page, including the one this dictionary belongs to. Every one of
///   them shall carry a `/SeparationInfo` whose `/Pages` array is identical.
/// * `/DeviceColorant` (required) - a name or a string naming the colorant.
/// * `/ColorSpace` (optional) - a Separation or DeviceN colour space array,
///   whose colorant name shall agree with `/DeviceColorant`.
class PdfSeparationInfo extends PdfObjectWrapper<PdfDictionary> {
  /// `/SeparationInfo`, the page object entry of Table 30.
  static final PdfName separationInfo = PdfName.intern('SeparationInfo');

  /// `/Pages`.
  static final PdfName pages = PdfName.intern('Pages');

  /// `/DeviceColorant`.
  static final PdfName deviceColorant = PdfName.intern('DeviceColorant');

  /// `/ColorSpace`.
  static final PdfName colorSpace = PdfName.intern('ColorSpace');

  PdfSeparationInfo(super.pdfObject);

  /// Creates an empty separation dictionary. Both required entries still have
  /// to be supplied before the document is written.
  PdfSeparationInfo.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Reads `/SeparationInfo` from [page], or `null` when the page has none.
  static Future<PdfSeparationInfo?> ofPage(PdfDictionary page) async {
    final dictionary = await page.dictionaryEntry(separationInfo);
    return dictionary == null ? null : PdfSeparationInfo(dictionary);
  }

  /// Writes this dictionary into the `/SeparationInfo` entry of [page].
  void attachToPage(PdfDictionary page) {
    page.put(separationInfo, pdfRepresentation());
    page.markChanged();
  }

  /// Sets `/Pages` to [pageObjects].
  ///
  /// Table 364 requires indirect references to page objects, so every entry
  /// must already belong to a document; a page that has no indirect reference
  /// yet is rejected rather than silently written as a direct dictionary.
  PdfSeparationInfo setPages(List<PdfDictionary> pageObjects) {
    if (pageObjects.isEmpty) {
      throw ArgumentError.value(pageObjects, 'pageObjects',
          'A separation dictionary /Pages array shall not be empty');
    }
    final array = PdfArray();
    for (final page in pageObjects) {
      final reference = page.indirectHandle();
      if (reference == null) {
        throw ArgumentError.value(
            pageObjects,
            'pageObjects',
            'A separation dictionary /Pages array shall hold indirect '
                'references to page objects (Table 364)');
      }
      array.add(reference);
    }
    pdfRepresentation().put(pages, array);
    markChanged();
    return this;
  }

  /// Gets `/Pages` as written, including unresolved references.
  Future<PdfArray?> getPagesArray() async =>
      await pdfRepresentation().arrayEntry(pages);

  /// Gets the page dictionaries named by `/Pages`.
  Future<List<PdfDictionary>> getPages() async {
    final array = await getPagesArray();
    final result = <PdfDictionary>[];
    if (array == null) return result;
    for (var i = 0; i < array.size(); i++) {
      final entry = await array.get(i, true);
      if (entry is PdfDictionary) result.add(entry);
    }
    return result;
  }

  /// Sets `/DeviceColorant` as a name, the form used for the standard process
  /// colorants such as `/Cyan`.
  PdfSeparationInfo setDeviceColorantName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name',
          'A separation dictionary /DeviceColorant shall name a colorant');
    }
    pdfRepresentation().put(deviceColorant, PdfName(name));
    markChanged();
    return this;
  }

  /// Sets `/DeviceColorant` as a string, the form that suits spot colorants
  /// whose names contain spaces, such as `PANTONE 35 CV`.
  PdfSeparationInfo setDeviceColorantString(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name',
          'A separation dictionary /DeviceColorant shall name a colorant');
    }
    pdfRepresentation().put(deviceColorant, PdfString(name));
    markChanged();
    return this;
  }

  /// Gets `/DeviceColorant`, accepting either of the two permitted types.
  Future<String?> getDeviceColorant() async {
    final value = await pdfRepresentation().get(deviceColorant, true);
    if (value is PdfName) return value.getValue();
    if (value is PdfString) return value.getValue();
    return null;
  }

  /// Sets `/ColorSpace`, a Separation or DeviceN colour space array.
  PdfSeparationInfo setColorSpace(PdfArray space) {
    pdfRepresentation().put(colorSpace, space);
    markChanged();
    return this;
  }

  /// Gets `/ColorSpace`.
  Future<PdfArray?> getColorSpace() async =>
      await pdfRepresentation().arrayEntry(colorSpace);

  /// The colorant names declared by the `/ColorSpace` array.
  ///
  /// A Separation space (8.6.6.4) has one name at index 1; a DeviceN space
  /// (8.6.6.5) has an array of names there. Any other family yields an empty
  /// list.
  Future<List<String>> colorSpaceColorants() async {
    final space = await getColorSpace();
    if (space == null || space.size() < 2) return const [];
    final family = await space.get(0, true);
    if (family is! PdfName) return const [];
    final names = await space.get(1, true);
    if (family.getValue() == 'Separation') {
      return names is PdfName ? [names.getValue()] : const [];
    }
    if (family.getValue() == 'DeviceN' && names is PdfArray) {
      final result = <String>[];
      for (var i = 0; i < names.size(); i++) {
        final entry = await names.get(i, true);
        if (entry is PdfName) result.add(entry.getValue());
      }
      return result;
    }
    return const [];
  }

  /// Reports every way in which this dictionary departs from Table 364 when it
  /// is read as the separation dictionary of [owner].
  ///
  /// An empty list means the dictionary conforms. Pass [owner] as the page
  /// dictionary that carries this `/SeparationInfo` so that the rule "one of
  /// the page objects in the array shall be the one with which this separation
  /// dictionary is associated" can be checked; pass `null` to skip it.
  Future<List<String>> validate({PdfDictionary? owner}) async {
    final problems = <String>[];

    final array = await getPagesArray();
    if (array == null) {
      problems.add('/Pages is required in a separation dictionary (Table 364)');
    } else if (array.size() == 0) {
      problems.add('/Pages shall list the page objects of the separations');
    } else {
      for (var i = 0; i < array.size(); i++) {
        final raw = await array.get(i, false);
        if (raw is! PdfIndirectReference) {
          problems.add('/Pages entry $i shall be an indirect reference to a '
              'page object (Table 364)');
        }
      }
    }

    final colorant = await getDeviceColorant();
    if (colorant == null) {
      final raw = await pdfRepresentation().get(deviceColorant, true);
      problems.add(raw == null
          ? '/DeviceColorant is required in a separation dictionary '
              '(Table 364)'
          : '/DeviceColorant shall be a name or a string (Table 364)');
    }

    if (owner != null && array != null) {
      var found = false;
      for (final page in await getPages()) {
        if (identical(page, owner)) {
          found = true;
          break;
        }
      }
      if (!found) {
        problems.add('/Pages shall include the page object this separation '
            'dictionary is associated with (Table 364)');
      }
    }

    if (colorant != null) {
      final colorants = await colorSpaceColorants();
      if (colorants.isNotEmpty && !colorants.contains(colorant)) {
        problems.add('/DeviceColorant "$colorant" shall match a colorant name '
            'of /ColorSpace (Table 364)');
      }
    }

    return problems;
  }

  /// Cross-checks a whole set of separations of one document page.
  ///
  /// Table 364: "all of them shall have separation dictionaries
  /// (SeparationInfo entries) containing Pages arrays identical to this one."
  /// Returns the list of departures; an empty list means the group conforms.
  static Future<List<String>> validateGroup(
      List<PdfDictionary> pageObjects) async {
    final problems = <String>[];
    if (pageObjects.isEmpty) return problems;

    List<PdfObject>? reference;
    final colorants = <String>{};

    for (var i = 0; i < pageObjects.length; i++) {
      final page = pageObjects[i];
      final info = await ofPage(page);
      if (info == null) {
        problems.add('Page $i of the separation group has no /SeparationInfo '
            '(Table 364)');
        continue;
      }
      problems.addAll(await info.validate(owner: page));

      final array = await info.getPagesArray();
      final entries = <PdfObject>[];
      if (array != null) {
        for (var j = 0; j < array.size(); j++) {
          final entry = await array.get(j, false);
          if (entry != null) entries.add(entry);
        }
      }
      if (reference == null) {
        reference = entries;
      } else if (!_sameReferences(reference, entries)) {
        problems.add('Page $i of the separation group has a /Pages array that '
            'differs from the first one (Table 364)');
      }

      final colorant = await info.getDeviceColorant();
      if (colorant != null && !colorants.add(colorant)) {
        problems.add('Colorant "$colorant" is used by more than one separation '
            'of the same document page (14.11.4)');
      }
    }

    return problems;
  }

  /// Builds the separation group of a document page.
  ///
  /// Each entry of [colorantsByPage] pairs one separation page with the device
  /// colorant it paints. Every page receives a `/SeparationInfo` whose `/Pages`
  /// array lists all of them in the given order, as Table 364 requires.
  static List<PdfSeparationInfo> buildGroup(
      List<MapEntry<PdfPage, String>> colorantsByPage,
      {bool colorantsAsNames = true}) {
    if (colorantsByPage.isEmpty) {
      throw ArgumentError.value(colorantsByPage, 'colorantsByPage',
          'A separation group shall contain at least one page');
    }
    final dictionaries =
        colorantsByPage.map((e) => e.key.pdfRepresentation()).toList();
    final result = <PdfSeparationInfo>[];
    for (final entry in colorantsByPage) {
      final info = PdfSeparationInfo.create()..setPages(dictionaries);
      if (colorantsAsNames) {
        info.setDeviceColorantName(entry.value);
      } else {
        info.setDeviceColorantString(entry.value);
      }
      info.attachToPage(entry.key.pdfRepresentation());
      result.add(info);
    }
    return result;
  }

  static bool _sameReferences(List<PdfObject> a, List<PdfObject> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left is PdfIndirectReference && right is PdfIndirectReference) {
        if (left.objectNumber() != right.objectNumber() ||
            left.generationNumber() != right.generationNumber()) {
          return false;
        }
      } else if (!identical(left, right)) {
        return false;
      }
    }
    return true;
  }
}
