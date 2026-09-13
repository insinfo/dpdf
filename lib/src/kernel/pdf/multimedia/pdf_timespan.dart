import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// Timespan dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.3 "Timespan Dictionary", Table 289.
class PdfTimespan extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /Timespan`.
  static final PdfName typeValue = PdfName.intern('Timespan');

  /// The only `/S` subtype defined by Table 289: a simple timespan.
  static final PdfName subtypeSimple = PdfName.intern('S');

  PdfTimespan(super.pdfObject);

  /// Creates a simple timespan of [seconds].
  ///
  /// Table 289 makes both `/S` and `/V` required. PDF 1.5 forbids negative
  /// values, which is enforced here.
  PdfTimespan.ofSeconds(double seconds) : super(PdfDictionary()) {
    if (seconds.isNaN || seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds',
          'Timespan /V shall not be negative (PDF 1.5, Table 289)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.s, subtypeSimple)
      ..put(PdfName.v, PdfNumber(seconds));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/S`, the timespan subtype.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Gets `/V`, the number of seconds.
  Future<double?> getSeconds() async =>
      (await pdfRepresentation().numberEntry(PdfName.v))?.getValue();

  /// Whether the timespan is viable: Table 289 says a conforming reader that
  /// does not recognise `/S` shall treat the rendition as non-viable, and the
  /// only recognised subtype is `/S`.
  Future<bool> isViable() async {
    final subtype = await getSubtype();
    if (subtype == null || subtype.getValue() != subtypeSimple.getValue()) {
      return false;
    }
    final seconds = await getSeconds();
    return seconds != null && seconds >= 0;
  }
}

/// Media offset dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.2 "Media Offset Dictionary", Tables 285 to 288.
class PdfMediaOffset extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MediaOffset`.
  static final PdfName typeValue = PdfName.intern('MediaOffset');

  /// `/S /T`: a media offset time dictionary (Table 286).
  static final PdfName subtypeTime = PdfName.t;

  /// `/S /F`: a media offset frame dictionary (Table 287).
  static final PdfName subtypeFrame = PdfName.f;

  /// `/S /M`: a media offset marker dictionary (Table 288).
  static final PdfName subtypeMarker = PdfName.m;

  PdfMediaOffset(super.pdfObject);

  /// Creates a media offset time dictionary. Table 286 requires `/T`, a
  /// timespan dictionary; negative timespans are not allowed here.
  PdfMediaOffset.time(PdfTimespan timespan) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.s, subtypeTime)
      ..put(PdfName.t, timespan.pdfRepresentation());
  }

  /// Creates a media offset time dictionary from a number of seconds.
  factory PdfMediaOffset.seconds(double seconds) =>
      PdfMediaOffset.time(PdfTimespan.ofSeconds(seconds));

  /// Creates a media offset frame dictionary. Table 287 numbers frames from
  /// zero and forbids negative frame numbers.
  PdfMediaOffset.frame(int frame) : super(PdfDictionary()) {
    if (frame < 0) {
      throw ArgumentError.value(
          frame, 'frame', 'Media offset /F shall not be negative (Table 287)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.s, subtypeFrame)
      ..put(PdfName.f, PdfNumber.fromInt(frame));
  }

  /// Creates a media offset marker dictionary. Table 288 requires `/M`, the
  /// text string naming the offset.
  PdfMediaOffset.marker(String marker) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.s, subtypeMarker)
      ..put(PdfName.m, PdfString(marker));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/S`, the offset subtype.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Gets `/T`, the timespan of a `/S /T` offset.
  Future<PdfTimespan?> getTimespan() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.t);
    return dictionary == null ? null : PdfTimespan(dictionary);
  }

  /// Gets `/F`, the frame number of a `/S /F` offset.
  Future<int?> getFrame() async =>
      await pdfRepresentation().integerEntry(PdfName.f);

  /// Gets `/M`, the marker name of a `/S /M` offset.
  Future<String?> getMarker() async =>
      (await pdfRepresentation().stringEntry(PdfName.m))?.decodeMappingText();
}

/// Media duration dictionary.
///
/// See ISO 32000-1:2008, 13.2.5 "Media Play Parameters", Table 281.
class PdfMediaDuration extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MediaDuration`.
  static final PdfName typeValue = PdfName.intern('MediaDuration');

  /// `/S /I`: the intrinsic duration of the associated media.
  static final PdfName subtypeIntrinsic = PdfName.intern('I');

  /// `/S /F`: the duration is infinity.
  static final PdfName subtypeInfinity = PdfName.f;

  /// `/S /T`: the duration is given by the `/T` timespan.
  static final PdfName subtypeExplicit = PdfName.t;

  PdfMediaDuration(super.pdfObject);

  PdfMediaDuration._ofSubtype(PdfName subtype) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.s, subtype);
  }

  /// Creates a `/S /I` duration: the media's intrinsic duration.
  factory PdfMediaDuration.intrinsic() =>
      PdfMediaDuration._ofSubtype(subtypeIntrinsic);

  /// Creates a `/S /F` duration: infinity.
  factory PdfMediaDuration.infinity() =>
      PdfMediaDuration._ofSubtype(subtypeInfinity);

  /// Creates a `/S /T` duration. Table 281 makes `/T` required in this case
  /// and forbids a negative duration.
  factory PdfMediaDuration.explicit(PdfTimespan timespan) {
    final duration = PdfMediaDuration._ofSubtype(subtypeExplicit);
    duration.pdfRepresentation().put(PdfName.t, timespan.pdfRepresentation());
    return duration;
  }

  /// Creates a `/S /T` duration of [seconds].
  factory PdfMediaDuration.ofSeconds(double seconds) =>
      PdfMediaDuration.explicit(PdfTimespan.ofSeconds(seconds));

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/S`, the duration subtype.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Gets `/T`, the explicit duration; meaningful only when `/S` is `/T`.
  Future<PdfTimespan?> getTimespan() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.t);
    return dictionary == null ? null : PdfTimespan(dictionary);
  }

  /// Resolves the duration in seconds, returning `double.infinity` for
  /// `/S /F` and null for `/S /I` (the intrinsic duration, which is known
  /// only to the player).
  Future<double?> getSeconds() async {
    final subtype = (await getSubtype())?.getValue();
    if (subtype == subtypeInfinity.getValue()) return double.infinity;
    if (subtype == subtypeExplicit.getValue()) {
      return await (await getTimespan())?.getSeconds();
    }
    return null;
  }
}

/// Reads a nested dictionary, creating it when absent. Shared by the MH/BE
/// "viability" dictionaries of 13.2.2 that many multimedia objects carry.
PdfDictionary ensureSubDictionary(PdfDictionary owner, PdfName key) {
  final existing = owner.getMap()?[key];
  if (existing is PdfDictionary) return existing;
  if (existing is PdfIndirectReference) {
    final target = existing.targetObjectSync();
    if (target is PdfDictionary) return target;
  }
  final created = PdfDictionary();
  owner.put(key, created);
  return created;
}
