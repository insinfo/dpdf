import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import 'pdf_software_identifier.dart';

/// Minimum bit depth dictionary.
///
/// See ISO 32000-1:2008, 13.2.3.1, Table 269.
class PdfMinimumBitDepth extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MinBitDepth`.
  static final PdfName typeValue = PdfName.intern('MinBitDepth');

  PdfMinimumBitDepth(super.pdfObject);

  /// Creates a minimum bit depth dictionary. `/V` is required by Table 269
  /// and shall be a non-negative integer; `/M` is a monitor specifier whose
  /// default is 0.
  PdfMinimumBitDepth.create(int depth, {int? monitor})
      : super(PdfDictionary()) {
    if (depth < 0) {
      throw ArgumentError.value(depth, 'depth',
          'Minimum bit depth /V shall be 0 or greater (Table 269)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.v, PdfNumber.fromInt(depth));
    if (monitor != null) {
      pdfRepresentation().put(PdfName.m,
          PdfNumber.fromInt(PdfMonitorSpecifier.check(monitor, 'monitor')));
    }
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/V`, the minimum screen depth in bits.
  Future<int?> getDepth() async =>
      await pdfRepresentation().integerEntry(PdfName.v);

  /// Gets `/M`; the default is 0 per Table 269.
  Future<int> getMonitor() async =>
      await pdfRepresentation().integerEntry(PdfName.m) ??
      PdfMonitorSpecifier.documentMonitor;
}

/// Minimum screen size dictionary.
///
/// See ISO 32000-1:2008, 13.2.3.1, Table 270.
class PdfMinimumScreenSize extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MinScreenSize`.
  static final PdfName typeValue = PdfName.intern('MinScreenSize');

  PdfMinimumScreenSize(super.pdfObject);

  /// Creates a minimum screen size dictionary. `/V` is required by Table 270
  /// and shall hold two non-negative integers.
  PdfMinimumScreenSize.create(int width, int height, {int? monitor})
      : super(PdfDictionary()) {
    if (width < 0 || height < 0) {
      throw ArgumentError(
          'Minimum screen size /V shall contain non-negative integers '
          '(Table 270)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.v, PdfArray.fromInts([width, height]));
    if (monitor != null) {
      pdfRepresentation().put(PdfName.m,
          PdfNumber.fromInt(PdfMonitorSpecifier.check(monitor, 'monitor')));
    }
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/V`, the minimum `[width height]` in pixels.
  Future<List<int>?> getSize() async =>
      await (await pdfRepresentation().arrayEntry(PdfName.v))?.toIntArray();

  /// Gets `/M`; the default is 0 per Table 270.
  Future<int> getMonitor() async =>
      await pdfRepresentation().integerEntry(PdfName.m) ??
      PdfMonitorSpecifier.documentMonitor;
}

/// Media criteria dictionary.
///
/// See ISO 32000-1:2008, 13.2.3.1 "General", Table 268. All the criteria it
/// carries shall be met for the enclosing rendition to be viable.
class PdfMediaCriteria extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MediaCriteria`.
  static final PdfName typeValue = PdfName.intern('MediaCriteria');

  PdfMediaCriteria(super.pdfObject);

  /// Creates an empty media criteria dictionary.
  PdfMediaCriteria.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, typeValue);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/A`, the user's audio-description preference (SMIL
  /// `systemAudioDesc`).
  PdfMediaCriteria setAudioDescriptions(bool value) =>
      _putFlag(PdfName.a, value);

  /// Gets `/A`.
  Future<bool?> getAudioDescriptions() => _flag(PdfName.a);

  /// Sets `/C`, the user's text-caption preference (SMIL `systemCaptions`).
  PdfMediaCriteria setTextCaptions(bool value) => _putFlag(PdfName.c, value);

  /// Gets `/C`.
  Future<bool?> getTextCaptions() => _flag(PdfName.c);

  /// Sets `/O`, the user's audio-overdub preference.
  PdfMediaCriteria setAudioOverdubs(bool value) => _putFlag(PdfName.o, value);

  /// Gets `/O`.
  Future<bool?> getAudioOverdubs() => _flag(PdfName.o);

  /// Sets `/S`, the user's subtitle preference.
  PdfMediaCriteria setSubtitles(bool value) => _putFlag(PdfName.s, value);

  /// Gets `/S`.
  Future<bool?> getSubtitles() => _flag(PdfName.s);

  /// Sets `/R`, the minimum system bandwidth in bits per second (SMIL
  /// `systemBitrate`).
  PdfMediaCriteria setMinimumBandwidth(int bitsPerSecond) {
    if (bitsPerSecond < 0) {
      throw ArgumentError.value(bitsPerSecond, 'bitsPerSecond',
          'Media criteria /R shall not be negative');
    }
    pdfRepresentation().put(PdfName.r, PdfNumber.fromInt(bitsPerSecond));
    return this;
  }

  /// Gets `/R`.
  Future<int?> getMinimumBandwidth() async =>
      await pdfRepresentation().integerEntry(PdfName.r);

  /// Sets `/D`, the minimum bit depth dictionary.
  PdfMediaCriteria setMinimumBitDepth(PdfMinimumBitDepth depth) {
    pdfRepresentation().put(PdfName.d, depth.pdfRepresentation());
    return this;
  }

  /// Gets `/D`.
  Future<PdfMinimumBitDepth?> getMinimumBitDepth() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.d);
    return dictionary == null ? null : PdfMinimumBitDepth(dictionary);
  }

  /// Sets `/Z`, the minimum screen size dictionary.
  PdfMediaCriteria setMinimumScreenSize(PdfMinimumScreenSize size) {
    pdfRepresentation().put(PdfName.intern('Z'), size.pdfRepresentation());
    return this;
  }

  /// Gets `/Z`.
  Future<PdfMinimumScreenSize?> getMinimumScreenSize() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('Z'));
    return dictionary == null ? null : PdfMinimumScreenSize(dictionary);
  }

  /// Sets `/V`, the software identifiers the conforming reader shall match.
  PdfMediaCriteria setSoftware(List<PdfSoftwareIdentifier> software) {
    pdfRepresentation().put(
        PdfName.v,
        PdfArray.fromList(
            software.map((item) => item.pdfRepresentation()).toList()));
    return this;
  }

  /// Gets `/V`.
  Future<List<PdfSoftwareIdentifier>> getSoftware() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.v);
    if (array == null) return const <PdfSoftwareIdentifier>[];
    final result = <PdfSoftwareIdentifier>[];
    for (var i = 0; i < array.size(); i++) {
      final dictionary = await array.dictionaryEntry(i);
      if (dictionary != null) result.add(PdfSoftwareIdentifier(dictionary));
    }
    return result;
  }

  /// Sets `/P`, the minimum and optional maximum PDF language version.
  /// Table 268 allows one or two names.
  PdfMediaCriteria setPdfVersionRange(String minimum, [String? maximum]) {
    final versions = <String>[minimum, if (maximum != null) maximum];
    pdfRepresentation()
        .put(PdfName.p, PdfArray.fromStrings(versions, asNames: true));
    return this;
  }

  /// Gets `/P`.
  Future<List<String>> getPdfVersionRange() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.p);
    if (array == null) return const <String>[];
    final result = <String>[];
    for (var i = 0; i < array.size(); i++) {
      final name = await array.nameEntry(i);
      if (name != null) result.add(name.getValue());
    }
    return result;
  }

  /// Sets `/L`, the language identifiers of 14.9.2.2 (SMIL `systemLanguage`).
  PdfMediaCriteria setLanguages(List<String> languages) {
    pdfRepresentation()
        .put(PdfName.intern('L'), PdfArray.fromStrings(languages));
    return this;
  }

  /// Gets `/L`.
  Future<List<String>> getLanguages() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.intern('L'));
    if (array == null) return const <String>[];
    final result = <String>[];
    for (var i = 0; i < array.size(); i++) {
      final value = await array.stringEntry(i);
      if (value != null) result.add(value.getValue());
    }
    return result;
  }

  PdfMediaCriteria _putFlag(PdfName key, bool value) {
    pdfRepresentation().put(key, PdfBoolean(value));
    return this;
  }

  Future<bool?> _flag(PdfName key) async =>
      (await pdfRepresentation().booleanEntry(key))?.getValue();
}
