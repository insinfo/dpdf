import 'dart:typed_data';

import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';
import '../filespec/pdf_file_spec.dart';

/// Movie dictionary.
///
/// See ISO 32000-1:2008, 13.4 "Movies", Table 295. 13.4 marks the movie
/// feature obsolescent; it is superseded by the multimedia framework of 13.2.
class PdfMovie extends PdfObjectWrapper<PdfDictionary> {
  static final PdfName _aspect = PdfName.intern('Aspect');
  static final PdfName _rotate = PdfName.intern('Rotate');
  static final PdfName _poster = PdfName.intern('Poster');

  PdfMovie(super.pdfObject);

  /// Creates a movie dictionary for the self-describing movie file [file].
  /// `/F` is the only required entry of Table 295.
  PdfMovie.forFile(PdfFileSpec file) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
  }

  /// Movie dictionaries are referenced from movie annotations, so they are
  /// stored indirectly.
  @override
  bool requiresIndirectStorage() => true;

  /// Gets `/F`, the movie file.
  Future<PdfFileSpec?> getFile() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.f);
    return dictionary == null ? null : PdfFileSpec(dictionary);
  }

  /// Sets `/Aspect`, the `[width height]` bounding box of the movie in
  /// pixels. Table 295 asks that this entry be omitted for a movie made
  /// entirely of sound.
  PdfMovie setAspect(int width, int height) {
    if (width < 0 || height < 0) {
      throw ArgumentError(
          'Movie /Aspect shall contain non-negative pixel counts (Table 295)');
    }
    pdfRepresentation().put(_aspect, PdfArray.fromInts([width, height]));
    return this;
  }

  /// Gets `/Aspect`.
  Future<List<int>?> getAspect() async =>
      await (await pdfRepresentation().arrayEntry(_aspect))?.toIntArray();

  /// Sets `/Rotate`, the clockwise rotation in degrees relative to the page.
  /// Table 295 requires a multiple of 90.
  PdfMovie setRotation(int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(degrees, 'degrees',
          'Movie /Rotate shall be a multiple of 90 (Table 295)');
    }
    pdfRepresentation().put(_rotate, PdfNumber.fromInt(degrees));
    return this;
  }

  /// Gets `/Rotate`; the default is 0 per Table 295.
  Future<int> getRotation() async =>
      await pdfRepresentation().integerEntry(_rotate) ?? 0;

  /// Sets `/Poster` to the boolean form of Table 295: true retrieves the
  /// poster image from the movie file, false displays no poster.
  PdfMovie setPosterFromMovie(bool fromMovie) {
    pdfRepresentation().put(_poster, PdfBoolean(fromMovie));
    return this;
  }

  /// Sets `/Poster` to an image XObject displayed as the poster.
  PdfMovie setPosterImage(PdfStream image) {
    pdfRepresentation().put(_poster, image);
    return this;
  }

  /// Gets `/Poster` as written; the value is a boolean or an image XObject
  /// stream, and its default is false per Table 295.
  Future<PdfObject?> getPoster() async =>
      await pdfRepresentation().get(_poster, true);

  /// Whether a poster shall be displayed, resolving both forms of `/Poster`.
  Future<bool> hasPoster() async {
    final poster = await getPoster();
    if (poster is PdfBoolean) return poster.getValue();
    return poster is PdfStream;
  }
}

/// Movie activation dictionary.
///
/// See ISO 32000-1:2008, 13.4 "Movies", Table 296.
class PdfMovieActivation extends PdfObjectWrapper<PdfDictionary> {
  /// `/Mode /Once`: play once and stop. This is the default of Table 296.
  static final PdfName modeOnce = PdfName.intern('Once');

  /// `/Mode /Open`: play and leave the movie controller bar open.
  static final PdfName modeOpen = PdfName.intern('Open');

  /// `/Mode /Repeat`: play repeatedly from beginning to end until stopped.
  static final PdfName modeRepeat = PdfName.intern('Repeat');

  /// `/Mode /Palindrome`: play forward and backward until stopped.
  static final PdfName modePalindrome = PdfName.intern('Palindrome');

  static final Set<String> _modes = {
    modeOnce.getValue(),
    modeOpen.getValue(),
    modeRepeat.getValue(),
    modePalindrome.getValue(),
  };

  static final PdfName _start = PdfName.intern('Start');
  static final PdfName _duration = PdfName.intern('Duration');
  static final PdfName _rate = PdfName.intern('Rate');
  static final PdfName _volume = PdfName.intern('Volume');
  static final PdfName _showControls = PdfName.intern('ShowControls');
  static final PdfName _mode = PdfName.intern('Mode');
  static final PdfName _synchronous = PdfName.intern('Synchronous');
  static final PdfName _fwScale = PdfName.intern('FWScale');
  static final PdfName _fwPosition = PdfName.intern('FWPosition');

  PdfMovieActivation(super.pdfObject);

  /// Creates an empty movie activation dictionary; every entry of Table 296
  /// is optional.
  PdfMovieActivation.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/Start` to a movie time value in the movie's own time scale.
  /// Table 296 says the value shall be a non-negative 64-bit integer, written
  /// as an integer when it fits the implementation limit for integers.
  PdfMovieActivation setStart(int time) {
    pdfRepresentation().put(_start, _movieTime(time, 'time'));
    return this;
  }

  /// Sets `/Start` to a movie time expressed in a time scale that differs
  /// from the movie's own, the two-element array form of Table 296.
  PdfMovieActivation setStartInTimeScale(int time, int unitsPerSecond) {
    pdfRepresentation()
        .put(_start, _movieTimeInScale(time, unitsPerSecond, 'time'));
    return this;
  }

  /// Sets `/Start` to the eight-byte string form of Table 296, used when the
  /// value is not representable as an integer. The bytes are a 64-bit
  /// twos-complement integer, most significant byte first.
  PdfMovieActivation setStartBytes(Uint8List time) {
    pdfRepresentation().put(_start, _movieTimeBytes(time, 'time'));
    return this;
  }

  /// Gets `/Start` as written; it is an integer, an 8-byte string or an
  /// array. A missing entry means the movie plays from the beginning.
  Future<PdfObject?> getStart() async =>
      await pdfRepresentation().get(_start, true);

  /// Resolves `/Start` to a number of movie time units, or null when the
  /// entry is absent. For the array form, only the time value is returned;
  /// [getStartTimeScale] reports the accompanying scale.
  Future<int?> getStartTime() => _movieTimeValue(_start);

  /// Gets the time scale, in units per second, attached to the array form of
  /// `/Start`; null means the movie's own default time scale.
  Future<int?> getStartTimeScale() => _movieTimeScale(_start);

  /// Sets `/Duration`, in the same form as `/Start`.
  PdfMovieActivation setDuration(int time) {
    pdfRepresentation().put(_duration, _movieTime(time, 'time'));
    return this;
  }

  /// Sets `/Duration` in a time scale other than the movie's own.
  PdfMovieActivation setDurationInTimeScale(int time, int unitsPerSecond) {
    pdfRepresentation()
        .put(_duration, _movieTimeInScale(time, unitsPerSecond, 'time'));
    return this;
  }

  /// Sets `/Duration` to the eight-byte string form of Table 296.
  PdfMovieActivation setDurationBytes(Uint8List time) {
    pdfRepresentation().put(_duration, _movieTimeBytes(time, 'time'));
    return this;
  }

  /// Gets `/Duration` as written. A missing entry means the movie plays to
  /// the end.
  Future<PdfObject?> getDuration() async =>
      await pdfRepresentation().get(_duration, true);

  /// Resolves `/Duration` to a number of movie time units.
  Future<int?> getDurationTime() => _movieTimeValue(_duration);

  /// Gets the time scale attached to the array form of `/Duration`.
  Future<int?> getDurationTimeScale() => _movieTimeScale(_duration);

  /// Sets `/Rate`, the initial play speed. Table 296 allows negative values,
  /// which play the movie backwards.
  PdfMovieActivation setRate(double rate) {
    pdfRepresentation().put(_rate, PdfNumber(rate));
    return this;
  }

  /// Gets `/Rate`; the default is 1.0 per Table 296.
  Future<double> getRate() async =>
      (await pdfRepresentation().numberEntry(_rate))?.getValue() ?? 1.0;

  /// Sets `/Volume`, in the range -1.0 to 1.0; negative values mute the
  /// sound (Table 296).
  PdfMovieActivation setVolume(double volume) {
    if (volume.isNaN || volume < -1 || volume > 1) {
      throw ArgumentError.value(volume, 'volume',
          'Movie activation /Volume shall lie in [-1, 1] (Table 296)');
    }
    pdfRepresentation().put(_volume, PdfNumber(volume));
    return this;
  }

  /// Gets `/Volume`; the default is 1.0 per Table 296.
  Future<double> getVolume() async =>
      (await pdfRepresentation().numberEntry(_volume))?.getValue() ?? 1.0;

  /// Sets `/ShowControls`, whether a movie controller bar is displayed.
  PdfMovieActivation setShowControls(bool showControls) {
    pdfRepresentation().put(_showControls, PdfBoolean(showControls));
    return this;
  }

  /// Gets `/ShowControls`; the default is false per Table 296.
  Future<bool> isShowControls() async =>
      (await pdfRepresentation().booleanEntry(_showControls))?.getValue() ??
      false;

  /// Sets `/Mode`, the play mode.
  PdfMovieActivation setMode(PdfName mode) {
    if (!_modes.contains(mode.getValue())) {
      throw ArgumentError.value(
          mode,
          'mode',
          'Movie activation /Mode shall be /Once, /Open, /Repeat or '
              '/Palindrome (Table 296)');
    }
    pdfRepresentation().put(_mode, mode);
    return this;
  }

  /// Gets `/Mode`; the default is `/Once` per Table 296.
  Future<PdfName> getMode() async =>
      await pdfRepresentation().nameEntry(_mode) ?? modeOnce;

  /// Sets `/Synchronous`, whether the player retains control until the movie
  /// completes.
  PdfMovieActivation setSynchronous(bool synchronous) {
    pdfRepresentation().put(_synchronous, PdfBoolean(synchronous));
    return this;
  }

  /// Gets `/Synchronous`; the default is false per Table 296.
  Future<bool> isSynchronous() async =>
      (await pdfRepresentation().booleanEntry(_synchronous))?.getValue() ??
      false;

  /// Sets `/FWScale`, the rational magnification factor
  /// `[numerator denominator]`. Table 296 requires two positive integers, and
  /// the presence of the entry means the movie plays in a floating window.
  PdfMovieActivation setFloatingWindowScale(int numerator, int denominator) {
    if (numerator <= 0 || denominator <= 0) {
      throw ArgumentError(
          'Movie activation /FWScale shall hold two positive integers '
          '(Table 296)');
    }
    pdfRepresentation()
        .put(_fwScale, PdfArray.fromInts([numerator, denominator]));
    return this;
  }

  /// Gets `/FWScale`.
  Future<List<int>?> getFloatingWindowScale() async =>
      await (await pdfRepresentation().arrayEntry(_fwScale))?.toIntArray();

  /// Whether the movie plays in a floating window, which Table 296 ties to
  /// the presence of `/FWScale`.
  bool isFloatingWindow() => pdfRepresentation().containsKey(_fwScale);

  /// Sets `/FWPosition`, the relative `[horiz vert]` position of a floating
  /// window; Table 296 constrains each number to `[0.0, 1.0]`.
  PdfMovieActivation setFloatingWindowPosition(
      double horizontal, double vertical) {
    for (final value in [horizontal, vertical]) {
      if (value.isNaN || value < 0 || value > 1) {
        throw ArgumentError(
            'Movie activation /FWPosition components shall lie in [0, 1] '
            '(Table 296)');
      }
    }
    pdfRepresentation()
        .put(_fwPosition, PdfArray.fromDoubles([horizontal, vertical]));
    return this;
  }

  /// Gets `/FWPosition`; the default is `[0.5 0.5]` per Table 296.
  Future<List<double>> getFloatingWindowPosition() async =>
      await (await pdfRepresentation().arrayEntry(_fwPosition))
          ?.toDoubleArray() ??
      const <double>[0.5, 0.5];

  /// The final floating window size in pixels, which Table 296 defines as
  /// `(numerator / denominator) * Aspect`. Returns null when `/FWScale` is
  /// absent or [movie] has no `/Aspect`.
  Future<List<double>?> floatingWindowSize(PdfMovie movie) async {
    final scale = await getFloatingWindowScale();
    if (scale == null || scale.length != 2 || scale[1] == 0) return null;
    final aspect = await movie.getAspect();
    if (aspect == null || aspect.length != 2) return null;
    final factor = scale[0] / scale[1];
    return [aspect[0] * factor, aspect[1] * factor];
  }

  static PdfObject _movieTime(int time, String name) {
    if (time < 0) {
      throw ArgumentError.value(
          time, name, 'Movie time values shall be non-negative (Table 296)');
    }
    return PdfNumber.fromInt(time);
  }

  static PdfObject _movieTimeBytes(Uint8List time, String name) {
    if (time.length != 8) {
      throw ArgumentError.value(time, name,
          'A movie time byte string shall hold exactly 8 bytes (Table 296)');
    }
    return PdfString.fromBytes(time, true);
  }

  static PdfObject _movieTimeInScale(
      int time, int unitsPerSecond, String name) {
    if (unitsPerSecond <= 0) {
      throw ArgumentError.value(unitsPerSecond, 'unitsPerSecond',
          'A movie time scale shall be positive (Table 296)');
    }
    return PdfArray.fromList(
        [_movieTime(time, name), PdfNumber.fromInt(unitsPerSecond)]);
  }

  Future<int?> _movieTimeValue(PdfName key) async {
    final value = await pdfRepresentation().get(key, true);
    if (value is PdfNumber) return value.getValue().toInt();
    if (value is PdfString) return _decodeMovieTimeBytes(value);
    if (value is PdfArray) {
      final first = await value.get(0);
      if (first is PdfNumber) return first.getValue().toInt();
      if (first is PdfString) return _decodeMovieTimeBytes(first);
    }
    return null;
  }

  Future<int?> _movieTimeScale(PdfName key) async {
    final value = await pdfRepresentation().get(key, true);
    if (value is! PdfArray) return null;
    return (await value.numberEntry(1))?.getValue().toInt();
  }

  static int? _decodeMovieTimeBytes(PdfString value) {
    final bytes = value.getValueBytes();
    if (bytes == null || bytes.length != 8) return null;
    var result = 0;
    for (final byte in bytes) {
      result = (result << 8) | byte;
    }
    return result;
  }
}
