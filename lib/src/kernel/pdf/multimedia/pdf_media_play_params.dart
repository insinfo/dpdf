import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import 'pdf_software_identifier.dart';
import 'pdf_timespan.dart';

/// `/F` fit modes of a media play parameters MH/BE dictionary.
///
/// See ISO 32000-1:2008, 13.2.5, Table 280.
abstract final class PdfMediaFitMode {
  /// Scale preserving the aspect ratio so that all media content shows
  /// ("meet" in SMIL).
  static const int meet = 0;

  /// Scale preserving the aspect ratio so that the play rectangle is filled
  /// ("slice" in SMIL).
  static const int slice = 1;

  /// Scale width and height independently ("fill" in SMIL).
  static const int fill = 2;

  /// Do not scale; provide a scrolling interface ("scroll" in SMIL).
  static const int scroll = 3;

  /// Do not scale; clip to the play rectangle ("hidden" in SMIL).
  static const int hidden = 4;

  /// Use the player's default setting. This is the default of Table 280.
  static const int playerDefault = 5;

  /// Whether [value] is one of the fit modes of Table 280.
  static bool isValid(int value) => value >= 0 && value <= 5;
}

/// Media play parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.5 "Media Play Parameters", Tables 279 to 281.
class PdfMediaPlayParams extends PdfObjectWrapper<PdfDictionary>
    with PdfViabilityAware {
  /// `/Type /MediaPlayParams`.
  static final PdfName typeValue = PdfName.intern('MediaPlayParams');

  static final PdfName _pl = PdfName.intern('PL');
  static final PdfName _rc = PdfName.intern('RC');

  PdfMediaPlayParams(super.pdfObject);

  /// Creates a media play parameters dictionary.
  PdfMediaPlayParams.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, typeValue);
  }

  @override
  bool requiresIndirectStorage() => false;

  @override
  PdfDictionary viabilityOwner() => pdfRepresentation();

  /// Sets `/PL`, the media players dictionary (Table 279).
  PdfMediaPlayParams setPlayers(PdfMediaPlayers players) {
    pdfRepresentation().put(_pl, players.pdfRepresentation());
    return this;
  }

  /// Gets `/PL`.
  Future<PdfMediaPlayers?> getPlayers() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_pl);
    return dictionary == null ? null : PdfMediaPlayers(dictionary);
  }

  /// Sets `/V`, the volume as a percentage of the recorded level. Table 280
  /// forbids negative values; zero means mute.
  PdfMediaPlayParams setVolume(int percent, {bool bestEffortOnly = true}) {
    if (percent < 0) {
      throw ArgumentError.value(percent, 'percent',
          'Media play parameters /V shall not be negative (Table 280)');
    }
    _target(bestEffortOnly).put(PdfName.v, PdfNumber.fromInt(percent));
    return this;
  }

  /// Gets the effective `/V`; the default is 100 per Table 280.
  Future<int> getVolume() async => await _integer(PdfName.v) ?? 100;

  /// Sets `/C`, whether a player controller user interface is shown.
  PdfMediaPlayParams setShowController(bool show,
      {bool bestEffortOnly = true}) {
    _target(bestEffortOnly).put(PdfName.c, PdfBoolean(show));
    return this;
  }

  /// Gets the effective `/C`; the default is false per Table 280.
  Future<bool> isShowController() async => await _boolean(PdfName.c) ?? false;

  /// Sets `/F`, the fit mode of [PdfMediaFitMode].
  PdfMediaPlayParams setFitMode(int mode, {bool bestEffortOnly = true}) {
    if (!PdfMediaFitMode.isValid(mode)) {
      throw ArgumentError.value(mode, 'mode',
          'Media play parameters /F shall lie in [0, 5] (Table 280)');
    }
    _target(bestEffortOnly).put(PdfName.f, PdfNumber.fromInt(mode));
    return this;
  }

  /// Gets the effective `/F`; the default is [PdfMediaFitMode.playerDefault].
  ///
  /// Table 280 says an unrecognised value in `/BE` is treated as the default,
  /// while in `/MH` it makes the object non-viable; [isFitModeViable] reports
  /// the latter case.
  Future<int> getFitMode() async {
    final mustHonour = await _integerIn(await readMustHonour(), PdfName.f);
    if (mustHonour != null) {
      return PdfMediaFitMode.isValid(mustHonour)
          ? mustHonour
          : PdfMediaFitMode.playerDefault;
    }
    final bestEffort = await _integerIn(await readBestEffort(), PdfName.f);
    if (bestEffort != null && PdfMediaFitMode.isValid(bestEffort)) {
      return bestEffort;
    }
    return PdfMediaFitMode.playerDefault;
  }

  /// Whether the `/F` entry keeps the object viable: an unrecognised value in
  /// the `/MH` dictionary does not (Table 280).
  Future<bool> isFitModeViable() async {
    final mustHonour = await _integerIn(await readMustHonour(), PdfName.f);
    return mustHonour == null || PdfMediaFitMode.isValid(mustHonour);
  }

  /// Sets `/D`, the media duration dictionary (Table 281).
  PdfMediaPlayParams setDuration(PdfMediaDuration duration,
      {bool bestEffortOnly = true}) {
    _target(bestEffortOnly).put(PdfName.d, duration.pdfRepresentation());
    return this;
  }

  /// Gets the effective `/D`; the default of Table 280 is the intrinsic
  /// duration.
  Future<PdfMediaDuration?> getDuration() async {
    final mustHonour =
        await (await readMustHonour())?.dictionaryEntry(PdfName.d);
    if (mustHonour != null) return PdfMediaDuration(mustHonour);
    final bestEffort =
        await (await readBestEffort())?.dictionaryEntry(PdfName.d);
    return bestEffort == null ? null : PdfMediaDuration(bestEffort);
  }

  /// Sets `/A`, whether the media plays automatically when activated.
  PdfMediaPlayParams setAutoPlay(bool autoPlay, {bool bestEffortOnly = true}) {
    _target(bestEffortOnly).put(PdfName.a, PdfBoolean(autoPlay));
    return this;
  }

  /// Gets the effective `/A`; the default is true per Table 280.
  Future<bool> isAutoPlay() async => await _boolean(PdfName.a) ?? true;

  /// Sets `/RC`, the repeat count. Table 280 forbids negative values, allows
  /// non-integral ones, and treats zero as "repeat forever".
  PdfMediaPlayParams setRepeatCount(double count,
      {bool bestEffortOnly = true}) {
    if (count.isNaN || count < 0) {
      throw ArgumentError.value(count, 'count',
          'Media play parameters /RC shall not be negative (Table 280)');
    }
    _target(bestEffortOnly).put(_rc, PdfNumber(count));
    return this;
  }

  /// Gets the effective `/RC`; the default is 1.0 per Table 280.
  Future<double> getRepeatCount() async {
    final mustHonour = await (await readMustHonour())?.numberEntry(_rc);
    if (mustHonour != null) return mustHonour.getValue();
    final bestEffort = await (await readBestEffort())?.numberEntry(_rc);
    return bestEffort?.getValue() ?? 1.0;
  }

  /// Whether `/RC` asks for endless repetition (a value of zero).
  Future<bool> isRepeatForever() async => await getRepeatCount() == 0;

  PdfDictionary _target(bool bestEffortOnly) =>
      bestEffortOnly ? bestEffort() : mustHonour();

  Future<int?> _integer(PdfName key) async =>
      await _integerIn(await readMustHonour(), key) ??
      await _integerIn(await readBestEffort(), key);

  static Future<int?> _integerIn(
          PdfDictionary? dictionary, PdfName key) async =>
      dictionary == null ? null : await dictionary.integerEntry(key);

  Future<bool?> _boolean(PdfName key) async {
    final mustHonour = await (await readMustHonour())?.booleanEntry(key);
    if (mustHonour != null) return mustHonour.getValue();
    final bestEffort = await (await readBestEffort())?.booleanEntry(key);
    return bestEffort?.getValue();
  }
}
