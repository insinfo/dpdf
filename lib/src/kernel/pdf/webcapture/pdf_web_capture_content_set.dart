import 'dart:typed_data';

import '../pdf_array.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';
import 'pdf_web_capture_source.dart';

/// A Web Capture content set.
///
/// ISO 32000-1:2008, 14.10.4.1, Table 352: a dictionary describing a set of
/// PDF objects generated from the same source data. The `/S` entry says which
/// of the two kinds it is - `/SPS` for a page set (14.10.4.2, Table 353) or
/// `/SIS` for an image set (14.10.4.3, Table 354).
class PdfWebCaptureContentSet extends PdfObjectWrapper<PdfDictionary> {
  /// `/SpiderContentSet`, the optional `/Type` of Table 352.
  static final PdfName spiderContentSet = PdfName.intern('SpiderContentSet');

  /// `/S`, the content set subtype.
  static final PdfName subtype = PdfName.intern('S');

  /// `/SPS`, the "Spider page set" subtype.
  static final PdfName pageSetSubtype = PdfName.intern('SPS');

  /// `/SIS`, the "Spider image set" subtype.
  static final PdfName imageSetSubtype = PdfName.intern('SIS');

  /// `/ID`, the digital identifier of the content set.
  static final PdfName identifier = PdfName.intern('ID');

  /// `/O`, the objects belonging to the content set.
  static final PdfName objects = PdfName.intern('O');

  /// `/SI`, the source information.
  static final PdfName sourceInformation = PdfName.intern('SI');

  /// `/CT`, the content type of the source.
  static final PdfName contentType = PdfName.intern('CT');

  /// `/TS`, the creation time stamp of the content set.
  static final PdfName timeStamp = PdfName.intern('TS');

  PdfWebCaptureContentSet(super.pdfObject);

  /// Wraps [dictionary] as the kind of content set its `/S` entry declares, or
  /// returns `null` when `/S` is missing or unknown.
  static Future<PdfWebCaptureContentSet?> wrap(PdfDictionary dictionary) async {
    final declared = await dictionary.nameEntry(subtype);
    switch (declared?.getValue()) {
      case 'SPS':
        return PdfWebCapturePageSet(dictionary);
      case 'SIS':
        return PdfWebCaptureImageSet(dictionary);
      default:
        return null;
    }
  }

  /// The `/O` array holds indirect references, and the `/IDS` and `/URLS` name
  /// trees point at content sets, so a content set is an indirect object.
  @override
  bool requiresIndirectStorage() => true;

  /// Sets `/ID`, the digital identifier of 14.10.3.3.
  PdfWebCaptureContentSet setIdentifier(Uint8List digest) {
    if (digest.isEmpty) {
      throw ArgumentError.value(digest, 'digest',
          'A content set /ID is required and shall not be empty (Table 352)');
    }
    pdfRepresentation().put(identifier, PdfString.fromBytes(digest, true));
    markChanged();
    return this;
  }

  /// Gets `/ID`.
  Future<Uint8List?> getIdentifier() async =>
      (await pdfRepresentation().stringEntry(identifier))?.getValueBytes();

  /// Sets `/O` to the objects generated from the source data.
  ///
  /// Table 352 requires indirect references, so every object has to belong to
  /// a document already.
  PdfWebCaptureContentSet setObjects(List<PdfObject> members) {
    final array = PdfArray();
    for (final member in members) {
      final reference = member.indirectHandle();
      if (reference == null) {
        throw ArgumentError.value(members, 'members',
            'A content set /O shall hold indirect references (Table 352)');
      }
      array.add(reference);
    }
    pdfRepresentation().put(objects, array);
    markChanged();
    return this;
  }

  /// Appends one object to `/O`, keeping the order in which objects were added
  /// to the file, as 14.10.4.2 requires of a page set.
  PdfWebCaptureContentSet addObject(PdfObject member) {
    final reference = member.indirectHandle();
    if (reference == null) {
      throw ArgumentError.value(member, 'member',
          'A content set /O shall hold indirect references (Table 352)');
    }
    var array = _objectArray();
    if (array == null) {
      array = PdfArray();
      pdfRepresentation().put(objects, array);
    }
    array.add(reference);
    markChanged();
    return this;
  }

  /// Gets `/O` as written.
  Future<PdfArray?> getObjectArray() async =>
      await pdfRepresentation().arrayEntry(objects);

  /// Gets the objects of `/O`, resolved.
  Future<List<PdfObject>> getObjects() async {
    final array = await getObjectArray();
    if (array == null) return const [];
    final result = <PdfObject>[];
    for (var i = 0; i < array.size(); i++) {
      final member = await array.get(i, true);
      if (member != null) result.add(member);
    }
    return result;
  }

  /// Sets `/SI` to a single source information dictionary.
  PdfWebCaptureContentSet setSource(PdfWebCaptureSourceInformation source) {
    pdfRepresentation().put(sourceInformation, source.pdfRepresentation());
    markChanged();
    return this;
  }

  /// Sets `/SI` to an array of source information dictionaries, the form used
  /// "when the same source data has been located via two or more distinct
  /// URLs".
  PdfWebCaptureContentSet setSources(
      List<PdfWebCaptureSourceInformation> sources) {
    if (sources.isEmpty) {
      throw ArgumentError.value(
          sources, 'sources', 'A content set /SI is required (Table 352)');
    }
    pdfRepresentation().put(sourceInformation,
        PdfArray.fromList([for (final s in sources) s.pdfRepresentation()]));
    markChanged();
    return this;
  }

  /// Gets `/SI` as a list, whichever of the two forms was used.
  Future<List<PdfWebCaptureSourceInformation>> getSources() async {
    final value = await pdfRepresentation().get(sourceInformation, true);
    if (value is PdfArray) {
      final result = <PdfWebCaptureSourceInformation>[];
      for (var i = 0; i < value.size(); i++) {
        final entry = await value.dictionaryEntry(i);
        if (entry != null) {
          result.add(PdfWebCaptureSourceInformation(entry));
        }
      }
      return result;
    }
    if (value is PdfDictionary) {
      return [PdfWebCaptureSourceInformation(value)];
    }
    return const [];
  }

  /// Sets `/CT`, a MIME content type such as `text/html`.
  PdfWebCaptureContentSet setContentType(String type) {
    pdfRepresentation().put(contentType, PdfString(type));
    markChanged();
    return this;
  }

  /// Gets `/CT`.
  Future<String?> getContentType() async =>
      (await pdfRepresentation().stringEntry(contentType))?.getValue();

  /// Sets `/TS`, the moment the content set was created.
  PdfWebCaptureContentSet setTimeStamp(DateTime moment) {
    pdfRepresentation().put(timeStamp, PdfString(PdfDate(moment).getValue()));
    markChanged();
    return this;
  }

  /// Gets `/TS`.
  Future<DateTime?> getTimeStamp() async {
    final value = await pdfRepresentation().stringEntry(timeStamp);
    if (value == null) return null;
    try {
      return PdfDate.decode(value.getValue());
    } catch (_) {
      return null;
    }
  }

  /// Reports every way in which this dictionary departs from Table 352.
  Future<List<String>> validate() async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    final type = await dictionary.nameEntry(PdfName.type);
    if (dictionary.containsKey(PdfName.type) &&
        (type == null || type.getValue() != 'SpiderContentSet')) {
      problems.add('/Type shall be /SpiderContentSet when present (Table 352)');
    }

    final declared = await dictionary.nameEntry(subtype);
    if (declared == null) {
      problems.add('/S is required in a content set (Table 352)');
    } else if (declared.getValue() != 'SPS' && declared.getValue() != 'SIS') {
      problems.add('/S shall be /SPS or /SIS (Table 352)');
    }

    if (await getIdentifier() == null) {
      problems.add('/ID is required in a content set (Table 352)');
    }

    final array = await getObjectArray();
    if (array == null) {
      problems.add('/O is required in a content set (Table 352)');
    } else {
      for (var i = 0; i < array.size(); i++) {
        if (await array.get(i, false) is! PdfIndirectReference) {
          problems.add('/O entry $i shall be an indirect reference '
              '(Table 352)');
        }
      }
    }

    final isPageSet = declared?.getValue() == 'SPS';
    final sources = await getSources();
    if (sources.isEmpty) {
      problems.add('/SI is required in a content set (Table 352)');
    } else {
      for (final source in sources) {
        problems.addAll(await source.validate(forPageSet: isPageSet));
      }
    }

    if (dictionary.containsKey(contentType) &&
        await dictionary.stringEntry(contentType) == null) {
      problems.add('/CT shall be an ASCII string (Table 352)');
    }
    if (dictionary.containsKey(timeStamp) &&
        await dictionary.stringEntry(timeStamp) == null) {
      problems.add('/TS shall be a date (Table 352)');
    }

    return problems;
  }

  PdfArray? _objectArray() {
    final value = pdfRepresentation().getMap()?[objects];
    return value is PdfArray ? value : null;
  }
}

/// A Web Capture page set.
///
/// ISO 32000-1:2008, 14.10.4.2, Table 353. "The pages shall be listed in the O
/// array of the page set dictionary in the same order in which they were
/// initially added to the file. A single page object shall not belong to more
/// than one page set."
class PdfWebCapturePageSet extends PdfWebCaptureContentSet {
  /// `/T`, the human-readable title of the page set.
  static final PdfName title = PdfName.intern('T');

  /// `/TID`, the text identifier of 14.10.3.3.
  static final PdfName textIdentifier = PdfName.intern('TID');

  PdfWebCapturePageSet(super.pdfObject);

  /// Creates a page set with `/Type /SpiderContentSet` and `/S /SPS`.
  PdfWebCapturePageSet.create(Uint8List digest) : super(PdfDictionary()) {
    pdfRepresentation()
        .put(PdfName.type, PdfWebCaptureContentSet.spiderContentSet);
    pdfRepresentation().put(PdfWebCaptureContentSet.subtype,
        PdfWebCaptureContentSet.pageSetSubtype);
    setIdentifier(digest);
  }

  /// Sets `/T`.
  PdfWebCapturePageSet setTitle(String value) {
    pdfRepresentation().put(title, PdfString(value));
    markChanged();
    return this;
  }

  /// Gets `/T`.
  Future<String?> getTitle() async =>
      (await pdfRepresentation().stringEntry(title))?.decodeMappingText();

  /// Sets `/TID`, "a text identifier generated from the text of the page set".
  PdfWebCapturePageSet setTextIdentifier(Uint8List digest) {
    pdfRepresentation().put(textIdentifier, PdfString.fromBytes(digest, true));
    markChanged();
    return this;
  }

  /// Gets `/TID`.
  Future<Uint8List?> getTextIdentifier() async =>
      (await pdfRepresentation().stringEntry(textIdentifier))?.getValueBytes();

  @override
  Future<List<String>> validate() async {
    final problems = await super.validate();
    final declared =
        await pdfRepresentation().nameEntry(PdfWebCaptureContentSet.subtype);
    if (declared != null && declared.getValue() != 'SPS') {
      problems.add('/S shall be /SPS in a page set (Table 353)');
    }
    if (pdfRepresentation().containsKey(title) &&
        await pdfRepresentation().stringEntry(title) == null) {
      problems.add('/T shall be a text string (Table 353)');
    }
    if (pdfRepresentation().containsKey(textIdentifier) &&
        await pdfRepresentation().stringEntry(textIdentifier) == null) {
      problems.add('/TID shall be a byte string (Table 353)');
    }
    return problems;
  }
}

/// A Web Capture image set.
///
/// ISO 32000-1:2008, 14.10.4.3, Table 354. `/R` holds the reference count of
/// each image XObject of `/O`: a single integer when the set holds one
/// XObject, and otherwise an array parallel to `/O`.
class PdfWebCaptureImageSet extends PdfWebCaptureContentSet {
  /// `/R`, the reference counts.
  static final PdfName referenceCounts = PdfName.intern('R');

  PdfWebCaptureImageSet(super.pdfObject);

  /// Creates an image set with `/Type /SpiderContentSet` and `/S /SIS`.
  PdfWebCaptureImageSet.create(Uint8List digest) : super(PdfDictionary()) {
    pdfRepresentation()
        .put(PdfName.type, PdfWebCaptureContentSet.spiderContentSet);
    pdfRepresentation().put(PdfWebCaptureContentSet.subtype,
        PdfWebCaptureContentSet.imageSetSubtype);
    setIdentifier(digest);
  }

  /// Sets `/R` from one count per object of `/O`.
  ///
  /// A single count is written as an integer, as Table 354 prescribes for an
  /// image set holding one XObject.
  PdfWebCaptureImageSet setReferenceCounts(List<int> counts) {
    if (counts.isEmpty) {
      throw ArgumentError.value(
          counts, 'counts', 'An image set /R is required (Table 354)');
    }
    for (final count in counts) {
      if (count < 0) {
        throw ArgumentError.value(
            counts, 'counts', 'A reference count shall not be negative');
      }
    }
    pdfRepresentation().put(
        referenceCounts,
        counts.length == 1
            ? PdfNumber.fromInt(counts.single)
            : PdfArray.fromInts(counts));
    markChanged();
    return this;
  }

  /// Gets `/R` as one count per object of `/O`.
  Future<List<int>> getReferenceCounts() async {
    final value = await pdfRepresentation().get(referenceCounts, true);
    if (value is PdfNumber) return [value.intValue()];
    if (value is PdfArray) {
      final counts = <int>[];
      for (var i = 0; i < value.size(); i++) {
        final count = await value.numberEntry(i);
        if (count == null) return const [];
        counts.add(count.intValue());
      }
      return counts;
    }
    return const [];
  }

  /// Raises the reference count of the XObject at [index] by one, as happens
  /// "whenever Web Capture creates a new page referring to the XObject".
  Future<PdfWebCaptureImageSet> retainAt(int index) async {
    final counts = await getReferenceCounts();
    _checkIndex(counts, index);
    counts[index]++;
    return setReferenceCounts(counts);
  }

  /// Lowers the reference count of the XObject at [index] by one.
  ///
  /// "If the reference count reaches 0, it shall be assumed that there are no
  /// remaining pages referring to the XObject and that the XObject can be
  /// removed from the image set's O array. When removing an XObject from the O
  /// array of an image set, the corresponding entry in the R array shall be
  /// removed also." That removal is what [releaseAt] performs, and it returns
  /// the resulting count.
  Future<int> releaseAt(int index) async {
    final counts = await getReferenceCounts();
    _checkIndex(counts, index);
    final remaining = counts[index] - 1;
    if (remaining > 0) {
      counts[index] = remaining;
      setReferenceCounts(counts);
      return remaining;
    }
    counts.removeAt(index);
    final array = await getObjectArray();
    array?.removeAt(index);
    if (counts.isEmpty) {
      pdfRepresentation().remove(referenceCounts);
      markChanged();
    } else {
      setReferenceCounts(counts);
    }
    return 0;
  }

  @override
  Future<List<String>> validate() async {
    final problems = await super.validate();
    final declared =
        await pdfRepresentation().nameEntry(PdfWebCaptureContentSet.subtype);
    if (declared != null && declared.getValue() != 'SIS') {
      problems.add('/S shall be /SIS in an image set (Table 354)');
    }

    if (!pdfRepresentation().containsKey(referenceCounts)) {
      problems.add('/R is required in an image set (Table 354)');
      return problems;
    }
    final counts = await getReferenceCounts();
    if (counts.isEmpty) {
      problems.add('/R shall be an integer or an array of integers '
          '(Table 354)');
      return problems;
    }
    final array = await getObjectArray();
    final members = array?.size() ?? 0;
    if (counts.length != members) {
      problems.add('/R shall hold one reference count per entry of /O '
          '(Table 354), expected $members and found ${counts.length}');
    }
    if (members > 1 &&
        await pdfRepresentation().arrayEntry(referenceCounts) == null) {
      problems.add('/R shall be an array when the image set holds more than '
          'one XObject (Table 354)');
    }
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] < 0) {
        problems.add('/R entry $i shall not be negative (Table 354)');
      }
    }
    return problems;
  }

  static void _checkIndex(List<int> counts, int index) {
    if (index < 0 || index >= counts.length) {
      throw RangeError.index(index, counts, 'index', null, counts.length);
    }
  }
}
