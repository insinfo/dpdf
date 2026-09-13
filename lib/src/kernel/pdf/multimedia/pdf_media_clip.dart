import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';
import '../filespec/pdf_file_spec.dart';
import 'pdf_software_identifier.dart';
import 'pdf_timespan.dart';

/// Media permissions dictionary.
///
/// See ISO 32000-1:2008, 13.2.4.2 "Media Clip Data", Table 275.
class PdfMediaPermissions extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MediaPermissions`.
  static final PdfName typeValue = PdfName.intern('MediaPermissions');

  /// `/TF (TEMPNEVER)`: writing a temporary file is never allowed.
  static const String temporaryNever = 'TEMPNEVER';

  /// `/TF (TEMPEXTRACT)`: allowed only when content extraction is permitted.
  static const String temporaryExtract = 'TEMPEXTRACT';

  /// `/TF (TEMPACCESS)`: allowed when extraction, including for
  /// accessibility, is permitted.
  static const String temporaryAccess = 'TEMPACCESS';

  /// `/TF (TEMPALWAYS)`: always allowed.
  static const String temporaryAlways = 'TEMPALWAYS';

  static const Set<String> _values = {
    temporaryNever,
    temporaryExtract,
    temporaryAccess,
    temporaryAlways,
  };

  PdfMediaPermissions(super.pdfObject);

  /// Creates a media permissions dictionary with the given `/TF` value.
  PdfMediaPermissions.create(String temporaryFilePolicy)
      : super(PdfDictionary()) {
    if (!_values.contains(temporaryFilePolicy)) {
      throw ArgumentError.value(
          temporaryFilePolicy,
          'temporaryFilePolicy',
          'Media permissions /TF shall be one of (TEMPNEVER), (TEMPEXTRACT), '
              '(TEMPACCESS) or (TEMPALWAYS) (Table 275)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.intern('TF'), PdfString(temporaryFilePolicy));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/TF`; the default is `(TEMPNEVER)` per Table 275, and an
  /// unrecognised value is likewise treated as `(TEMPNEVER)`.
  Future<String> getTemporaryFilePolicy() async {
    final value = (await pdfRepresentation().stringEntry(PdfName.intern('TF')))
        ?.getValue();
    if (value == null || !_values.contains(value)) return temporaryNever;
    return value;
  }
}

/// Base class of the media clip objects of ISO 32000-1:2008, 13.2.4.
///
/// Table 273 lists the entries common to all media clip dictionaries.
abstract class PdfMediaClip extends PdfObjectWrapper<PdfDictionary>
    with PdfViabilityAware {
  /// `/Type /MediaClip`.
  static final PdfName typeValue = PdfName.intern('MediaClip');

  /// `/S /MCD`: a media clip data dictionary (13.2.4.2).
  static final PdfName subtypeData = PdfName.intern('MCD');

  /// `/S /MCS`: a media clip section dictionary (13.2.4.3).
  static final PdfName subtypeSection = PdfName.intern('MCS');

  PdfMediaClip(super.pdfObject);

  /// A media clip object should be an indirect object: it is shared between
  /// renditions and referenced from the rendition `/C` entry.
  @override
  bool requiresIndirectStorage() => true;

  @override
  PdfDictionary viabilityOwner() => pdfRepresentation();

  /// Gets `/S`, the media clip subtype.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Sets `/N`, the clip name shown in the user interface.
  PdfMediaClip setName(String name) {
    pdfRepresentation().put(PdfName.n, PdfString(name));
    return this;
  }

  /// Gets `/N`.
  Future<String?> getName() async =>
      (await pdfRepresentation().stringEntry(PdfName.n))?.decodeMappingText();

  /// Sets `/Alt`, the multi-language text array of alternate descriptions
  /// (14.9.2.4). The array pairs language identifiers with text strings, and
  /// an empty language identifier introduces the default text.
  PdfMediaClip setAlternateDescriptions(List<String> languageTextPairs) {
    if (languageTextPairs.length.isOdd) {
      throw ArgumentError.value(
          languageTextPairs,
          'languageTextPairs',
          'A multi-language text array shall hold language/text pairs '
              '(14.9.2.4)');
    }
    pdfRepresentation()
        .put(PdfName.intern('Alt'), PdfArray.fromStrings(languageTextPairs));
    return this;
  }

  /// Gets `/Alt` as a flat list of language/text pairs.
  Future<List<String>> getAlternateDescriptions() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.intern('Alt'));
    if (array == null) return const <String>[];
    final result = <String>[];
    for (var i = 0; i < array.size(); i++) {
      final value = await array.stringEntry(i);
      if (value != null) result.add(value.decodeMappingText());
    }
    return result;
  }

  /// Reads the media clip stored in [dictionary], returning the concrete
  /// subclass identified by `/S`, or null when `/S` is unrecognised (which
  /// Table 273 makes non-viable).
  static Future<PdfMediaClip?> read(PdfDictionary dictionary) async {
    final subtype = (await dictionary.nameEntry(PdfName.s))?.getValue();
    if (subtype == 'MCD') return PdfMediaClipData(dictionary);
    if (subtype == 'MCS') return PdfMediaClipSection(dictionary);
    return null;
  }
}

/// Media clip data dictionary.
///
/// See ISO 32000-1:2008, 13.2.4.2 "Media Clip Data", Table 274.
class PdfMediaClipData extends PdfMediaClip {
  PdfMediaClipData(super.pdfObject);

  /// Creates a media clip data dictionary for the file specification [data].
  ///
  /// Table 274 makes `/D` required; the text after the table says the object
  /// referenced by `/D` shall be a dictionary or stream carrying a `/Type`
  /// entry, which excludes plain file specification strings. A file
  /// specification therefore gets `/Type /Filespec` forced here.
  PdfMediaClipData.forFileSpec(PdfFileSpec data, {String? contentType})
      : super(PdfDictionary()) {
    data.pdfRepresentation().put(PdfName.type, PdfName.intern('Filespec'));
    _initialise(data.pdfRepresentation(), contentType);
  }

  /// Creates a media clip data dictionary for a form XObject.
  ///
  /// Table 274 forbids `/CT` for form XObjects; the associated player is
  /// implicitly the conforming reader.
  PdfMediaClipData.forFormXObject(PdfStream form) : super(PdfDictionary()) {
    form.put(PdfName.type, PdfName.xObject);
    form.put(PdfName.subtype, PdfName.form);
    _initialise(form, null);
  }

  void _initialise(PdfObject data, String? contentType) {
    pdfRepresentation()
      ..put(PdfName.type, PdfMediaClip.typeValue)
      ..put(PdfName.s, PdfMediaClip.subtypeData)
      ..put(PdfName.d, data);
    if (contentType != null) setContentType(contentType);
  }

  /// Gets `/D`, the media data, as written.
  Future<PdfObject?> getData() async =>
      await pdfRepresentation().get(PdfName.d, true);

  /// Gets `/D` as a file specification, or null when `/D` is a form XObject.
  Future<PdfFileSpec?> getFileSpec() async {
    final data = await getData();
    if (data is PdfStream) return null;
    if (data is PdfDictionary) return PdfFileSpec(data);
    return null;
  }

  /// Sets `/CT`, the RFC 2045 content type of the data in `/D`.
  PdfMediaClipData setContentType(String contentType) {
    if (pdfRepresentation().getMap()?[PdfName.d] is PdfStream) {
      throw StateError(
          'Media clip data /CT is not allowed for form XObjects (Table 274)');
    }
    pdfRepresentation().put(PdfName.intern('CT'), PdfString(contentType));
    return this;
  }

  /// Gets `/CT`.
  Future<String?> getContentType() async =>
      (await pdfRepresentation().stringEntry(PdfName.intern('CT')))?.getValue();

  /// Sets `/P`, the media permissions dictionary.
  PdfMediaClipData setPermissions(PdfMediaPermissions permissions) {
    pdfRepresentation().put(PdfName.p, permissions.pdfRepresentation());
    return this;
  }

  /// Gets `/P`; the default of Table 274 is a permissions dictionary holding
  /// default values, so a missing entry yields `(TEMPNEVER)`.
  Future<PdfMediaPermissions?> getPermissions() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.p);
    return dictionary == null ? null : PdfMediaPermissions(dictionary);
  }

  /// Sets `/PL`, the media players dictionary.
  PdfMediaClipData setPlayers(PdfMediaPlayers players) {
    pdfRepresentation().put(PdfName.intern('PL'), players.pdfRepresentation());
    return this;
  }

  /// Gets `/PL`.
  Future<PdfMediaPlayers?> getPlayers() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('PL'));
    return dictionary == null ? null : PdfMediaPlayers(dictionary);
  }

  /// Sets `/BU` in the `/MH` dictionary, the base URL that shall be honoured
  /// for the clip to be viable (Table 276).
  PdfMediaClipData setMustHonourBaseUrl(String url) {
    mustHonour().put(PdfName.intern('BU'), PdfString(url));
    return this;
  }

  /// Sets `/BU` in the `/BE` dictionary, the best-effort base URL.
  PdfMediaClipData setBestEffortBaseUrl(String url) {
    bestEffort().put(PdfName.intern('BU'), PdfString(url));
    return this;
  }

  /// Gets the effective `/BU`, preferring the `/MH` value over `/BE` as
  /// 13.2.2 requires.
  Future<String?> getBaseUrl() async {
    final bu = PdfName.intern('BU');
    final mustHonour = await readMustHonour();
    final value = await mustHonour?.stringEntry(bu);
    if (value != null) return value.getValue();
    final bestEffort = await readBestEffort();
    return (await bestEffort?.stringEntry(bu))?.getValue();
  }

  /// Reports whether the object referenced by `/D` satisfies the viability
  /// rule stated after Table 274: it shall be a dictionary or stream and it
  /// shall carry a recognised `/Type` entry.
  Future<bool> isDataViable() async {
    final data = await getData();
    if (data is! PdfDictionary) return false;
    final type = (await data.nameEntry(PdfName.type))?.getValue();
    return type == 'Filespec' || type == 'XObject';
  }
}

/// Media clip section dictionary.
///
/// See ISO 32000-1:2008, 13.2.4.3 "Media Clip Section", Tables 277 and 278.
class PdfMediaClipSection extends PdfMediaClip {
  static final PdfName _e = PdfName.intern('E');

  PdfMediaClipSection(super.pdfObject);

  /// Creates a media clip section over the next-level media clip [next].
  /// `/D` is required by Table 277.
  PdfMediaClipSection.of(PdfMediaClip next) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, PdfMediaClip.typeValue)
      ..put(PdfName.s, PdfMediaClip.subtypeSection)
      ..put(PdfName.d, next.pdfRepresentation());
  }

  /// Gets `/D`, the next-level media clip object.
  Future<PdfMediaClip?> getNext() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.d);
    return dictionary == null ? null : await PdfMediaClip.read(dictionary);
  }

  /// Sets `/B` in `/MH`, the offset at which the section begins and which
  /// shall be honoured for the section to be viable (Table 278).
  PdfMediaClipSection setMustHonourBegin(PdfMediaOffset offset) {
    mustHonour().put(PdfName.b, offset.pdfRepresentation());
    return this;
  }

  /// Sets `/E` in `/MH`, the offset at which the section ends.
  PdfMediaClipSection setMustHonourEnd(PdfMediaOffset offset) {
    mustHonour().put(_e, offset.pdfRepresentation());
    return this;
  }

  /// Sets `/B` in `/BE`, the best-effort beginning offset.
  PdfMediaClipSection setBestEffortBegin(PdfMediaOffset offset) {
    bestEffort().put(PdfName.b, offset.pdfRepresentation());
    return this;
  }

  /// Sets `/E` in `/BE`, the best-effort ending offset.
  PdfMediaClipSection setBestEffortEnd(PdfMediaOffset offset) {
    bestEffort().put(_e, offset.pdfRepresentation());
    return this;
  }

  /// Gets the effective `/B`, preferring `/MH` over `/BE`.
  Future<PdfMediaOffset?> getBegin() => _offset(PdfName.b);

  /// Gets the effective `/E`, preferring `/MH` over `/BE`.
  Future<PdfMediaOffset?> getEnd() => _offset(_e);

  /// Walks the `/D` chain, which 13.2.4.3 requires to terminate in a media
  /// clip data object, and returns that object. Returns null when the chain
  /// is broken or cyclic.
  Future<PdfMediaClipData?> resolveClipData() async {
    PdfMediaClip? current = this;
    final seen = <PdfDictionary>{};
    while (current != null) {
      if (current is PdfMediaClipData) return current;
      if (!seen.add(current.pdfRepresentation())) return null;
      current = await (current as PdfMediaClipSection).getNext();
    }
    return null;
  }

  Future<PdfMediaOffset?> _offset(PdfName key) async {
    final mustHonour = await readMustHonour();
    final value = await mustHonour?.dictionaryEntry(key);
    if (value != null) return PdfMediaOffset(value);
    final bestEffort = await readBestEffort();
    final fallback = await bestEffort?.dictionaryEntry(key);
    return fallback == null ? null : PdfMediaOffset(fallback);
  }
}
