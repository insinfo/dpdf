import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import 'pdf_software_identifier.dart';

/// `/W` window types of a media screen parameters MH/BE dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.1, Table 283.
abstract final class PdfMediaWindowType {
  /// A floating window; `/F` is then required.
  static const int floating = 0;

  /// A full-screen window obscuring all other windows.
  static const int fullScreen = 1;

  /// A hidden window.
  static const int hidden = 2;

  /// The rectangle occupied by the associated screen annotation. This is the
  /// default of Table 283.
  static const int annotation = 3;

  /// Whether [value] is one of the window types of Table 283.
  static bool isValid(int value) => value >= 0 && value <= 3;
}

/// `/RT` relative-window values of a floating window parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.1, Table 284.
abstract final class PdfFloatingWindowRelativeTo {
  /// The document window; the default of Table 284.
  static const int documentWindow = 0;

  /// The application window.
  static const int applicationWindow = 1;

  /// The full virtual desktop.
  static const int virtualDesktop = 2;

  /// The monitor named by `/M` in the media screen parameters dictionary.
  static const int monitor = 3;

  /// Whether [value] is one of the values of Table 284.
  static bool isValid(int value) => value >= 0 && value <= 3;
}

/// `/P` positions of a floating window parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.1, Table 284.
abstract final class PdfFloatingWindowPosition {
  static const int upperLeft = 0;
  static const int upperCenter = 1;
  static const int upperRight = 2;
  static const int centerLeft = 3;

  /// The default of Table 284.
  static const int center = 4;
  static const int centerRight = 5;
  static const int lowerLeft = 6;
  static const int lowerCenter = 7;
  static const int lowerRight = 8;

  /// Whether [value] is one of the positions of Table 284.
  static bool isValid(int value) => value >= 0 && value <= 8;
}

/// `/O` offscreen behaviours of a floating window parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.1, Table 284.
abstract final class PdfFloatingWindowOffscreen {
  /// Take no special action.
  static const int none = 0;

  /// Move or resize the window so that it is on-screen; the default.
  static const int moveOnScreen = 1;

  /// Consider the object non-viable.
  static const int nonViable = 2;

  /// Whether [value] is one of the values of Table 284.
  static bool isValid(int value) => value >= 0 && value <= 2;
}

/// `/R` resize behaviours of a floating window parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.1, Table 284.
abstract final class PdfFloatingWindowResize {
  /// The window may not be resized; the default of Table 284.
  static const int none = 0;

  /// The window may be resized only if the aspect ratio is preserved.
  static const int keepAspectRatio = 1;

  /// The window may be resized freely.
  static const int free = 2;

  /// Whether [value] is one of the values of Table 284.
  static bool isValid(int value) => value >= 0 && value <= 2;
}

/// Floating window parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.6.1, Table 284.
class PdfFloatingWindowParams extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /FWParams`.
  static final PdfName typeValue = PdfName.intern('FWParams');

  static final PdfName _rt = PdfName.intern('RT');
  static final PdfName _uc = PdfName.intern('UC');
  static final PdfName _tt = PdfName.intern('TT');

  PdfFloatingWindowParams(super.pdfObject);

  /// Creates a floating window parameters dictionary of the given size in
  /// pixels. `/D` is required by Table 284 and shall hold two non-negative
  /// integers.
  PdfFloatingWindowParams.ofSize(int width, int height)
      : super(PdfDictionary()) {
    if (width < 0 || height < 0) {
      throw ArgumentError(
          'Floating window /D shall contain non-negative integers (Table 284)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.d, PdfArray.fromInts([width, height]));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/D`, the `[width height]` of the window in pixels.
  Future<List<int>?> getSize() async =>
      await (await pdfRepresentation().arrayEntry(PdfName.d))?.toIntArray();

  /// Sets `/RT`, the window the floating window is positioned relative to.
  PdfFloatingWindowParams setRelativeTo(int relativeTo) {
    if (!PdfFloatingWindowRelativeTo.isValid(relativeTo)) {
      throw ArgumentError.value(relativeTo, 'relativeTo',
          'Floating window /RT shall lie in [0, 3] (Table 284)');
    }
    pdfRepresentation().put(_rt, PdfNumber.fromInt(relativeTo));
    return this;
  }

  /// Gets `/RT`; the default is 0 per Table 284.
  Future<int> getRelativeTo() async =>
      await pdfRepresentation().integerEntry(_rt) ??
      PdfFloatingWindowRelativeTo.documentWindow;

  /// Sets `/P`, the position of the window.
  PdfFloatingWindowParams setPosition(int position) {
    if (!PdfFloatingWindowPosition.isValid(position)) {
      throw ArgumentError.value(position, 'position',
          'Floating window /P shall lie in [0, 8] (Table 284)');
    }
    pdfRepresentation().put(PdfName.p, PdfNumber.fromInt(position));
    return this;
  }

  /// Gets `/P`; the default is 4 (center) per Table 284.
  Future<int> getPosition() async =>
      await pdfRepresentation().integerEntry(PdfName.p) ??
      PdfFloatingWindowPosition.center;

  /// Sets `/O`, what happens when the window falls offscreen.
  PdfFloatingWindowParams setOffscreenBehaviour(int behaviour) {
    if (!PdfFloatingWindowOffscreen.isValid(behaviour)) {
      throw ArgumentError.value(behaviour, 'behaviour',
          'Floating window /O shall lie in [0, 2] (Table 284)');
    }
    pdfRepresentation().put(PdfName.o, PdfNumber.fromInt(behaviour));
    return this;
  }

  /// Gets `/O`; the default is 1 per Table 284.
  Future<int> getOffscreenBehaviour() async =>
      await pdfRepresentation().integerEntry(PdfName.o) ??
      PdfFloatingWindowOffscreen.moveOnScreen;

  /// Sets `/T`, whether the window has a title bar.
  PdfFloatingWindowParams setHasTitleBar(bool hasTitleBar) {
    pdfRepresentation().put(PdfName.t, PdfBoolean(hasTitleBar));
    return this;
  }

  /// Gets `/T`; the default is true per Table 284.
  Future<bool> hasTitleBar() async =>
      (await pdfRepresentation().booleanEntry(PdfName.t))?.getValue() ?? true;

  /// Sets `/UC`, whether the window offers a close control. Table 284 makes
  /// this meaningful only when `/T` is true.
  PdfFloatingWindowParams setHasCloseControl(bool hasCloseControl) {
    pdfRepresentation().put(_uc, PdfBoolean(hasCloseControl));
    return this;
  }

  /// Gets `/UC`; the default is true per Table 284.
  Future<bool> hasCloseControl() async =>
      (await pdfRepresentation().booleanEntry(_uc))?.getValue() ?? true;

  /// Sets `/R`, whether and how the window may be resized.
  PdfFloatingWindowParams setResizeBehaviour(int behaviour) {
    if (!PdfFloatingWindowResize.isValid(behaviour)) {
      throw ArgumentError.value(behaviour, 'behaviour',
          'Floating window /R shall lie in [0, 2] (Table 284)');
    }
    pdfRepresentation().put(PdfName.r, PdfNumber.fromInt(behaviour));
    return this;
  }

  /// Gets `/R`; the default is 0 per Table 284.
  Future<int> getResizeBehaviour() async =>
      await pdfRepresentation().integerEntry(PdfName.r) ??
      PdfFloatingWindowResize.none;

  /// Sets `/TT`, the multi-language text array shown in the title bar
  /// (14.9.2.4). Meaningful only when `/T` is true.
  PdfFloatingWindowParams setTitle(List<String> languageTextPairs) {
    if (languageTextPairs.length.isOdd) {
      throw ArgumentError.value(languageTextPairs, 'languageTextPairs',
          'Floating window /TT shall hold language/text pairs (14.9.2.4)');
    }
    pdfRepresentation().put(_tt, PdfArray.fromStrings(languageTextPairs));
    return this;
  }

  /// Gets `/TT` as a flat list of language/text pairs.
  Future<List<String>> getTitle() async {
    final array = await pdfRepresentation().arrayEntry(_tt);
    if (array == null) return const <String>[];
    final result = <String>[];
    for (var i = 0; i < array.size(); i++) {
      final value = await array.stringEntry(i);
      if (value != null) result.add(value.decodeMappingText());
    }
    return result;
  }
}

/// Media screen parameters dictionary.
///
/// See ISO 32000-1:2008, 13.2.6 "Media Screen Parameters", Tables 282 to 284.
class PdfMediaScreenParams extends PdfObjectWrapper<PdfDictionary>
    with PdfViabilityAware {
  /// `/Type /MediaScreenParams`.
  static final PdfName typeValue = PdfName.intern('MediaScreenParams');

  PdfMediaScreenParams(super.pdfObject);

  /// Creates a media screen parameters dictionary.
  PdfMediaScreenParams.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, typeValue);
  }

  @override
  bool requiresIndirectStorage() => false;

  @override
  PdfDictionary viabilityOwner() => pdfRepresentation();

  /// Sets `/W`, the window type of [PdfMediaWindowType]. Table 283 requires
  /// `/F` when `/W` is 0, which [setFloatingWindow] supplies.
  PdfMediaScreenParams setWindowType(int type, {bool bestEffortOnly = true}) {
    if (!PdfMediaWindowType.isValid(type)) {
      throw ArgumentError.value(type, 'type',
          'Media screen parameters /W shall lie in [0, 3] (Table 283)');
    }
    _target(bestEffortOnly).put(PdfName.w, PdfNumber.fromInt(type));
    return this;
  }

  /// Gets the effective `/W`; the default is 3 per Table 283. An unrecognised
  /// value in `/BE` is treated as the default.
  Future<int> getWindowType() async {
    final mustHonour = await _integerIn(await readMustHonour(), PdfName.w);
    if (mustHonour != null) {
      return PdfMediaWindowType.isValid(mustHonour)
          ? mustHonour
          : PdfMediaWindowType.annotation;
    }
    final bestEffort = await _integerIn(await readBestEffort(), PdfName.w);
    if (bestEffort != null && PdfMediaWindowType.isValid(bestEffort)) {
      return bestEffort;
    }
    return PdfMediaWindowType.annotation;
  }

  /// Sets `/B`, the DeviceRGB background colour of the play rectangle.
  /// Table 283 constrains each component to `[0.0, 1.0]`.
  PdfMediaScreenParams setBackgroundColour(List<double> rgb,
      {bool bestEffortOnly = true}) {
    if (rgb.length != 3) {
      throw ArgumentError.value(rgb, 'rgb',
          'Media screen parameters /B shall hold three numbers (Table 283)');
    }
    for (final component in rgb) {
      if (component.isNaN || component < 0 || component > 1) {
        throw ArgumentError.value(rgb, 'rgb',
            'Media screen parameters /B components shall lie in [0, 1]');
      }
    }
    _target(bestEffortOnly).put(PdfName.b, PdfArray.fromDoubles(rgb));
    return this;
  }

  /// Gets the effective `/B`, preferring `/MH` over `/BE`.
  Future<List<double>?> getBackgroundColour() async {
    final mustHonour = await (await readMustHonour())?.arrayEntry(PdfName.b);
    if (mustHonour != null) return await mustHonour.toDoubleArray();
    final bestEffort = await (await readBestEffort())?.arrayEntry(PdfName.b);
    return await bestEffort?.toDoubleArray();
  }

  /// Sets `/O`, the constant opacity used to paint `/B`. Table 283 constrains
  /// it to `[0.0, 1.0]`.
  PdfMediaScreenParams setOpacity(double opacity,
      {bool bestEffortOnly = true}) {
    if (opacity.isNaN || opacity < 0 || opacity > 1) {
      throw ArgumentError.value(opacity, 'opacity',
          'Media screen parameters /O shall lie in [0, 1] (Table 283)');
    }
    _target(bestEffortOnly).put(PdfName.o, PdfNumber(opacity));
    return this;
  }

  /// Gets the effective `/O`; the default is 1.0 per Table 283.
  Future<double> getOpacity() async {
    final mustHonour = await (await readMustHonour())?.numberEntry(PdfName.o);
    if (mustHonour != null) return mustHonour.getValue();
    final bestEffort = await (await readBestEffort())?.numberEntry(PdfName.o);
    return bestEffort?.getValue() ?? 1.0;
  }

  /// Sets `/M`, the monitor specifier of Table 293.
  PdfMediaScreenParams setMonitor(int monitor, {bool bestEffortOnly = true}) {
    _target(bestEffortOnly).put(PdfName.m,
        PdfNumber.fromInt(PdfMonitorSpecifier.check(monitor, 'monitor')));
    return this;
  }

  /// Gets the effective `/M`; the default is 0 per Table 283.
  Future<int> getMonitor() async =>
      await _integerIn(await readMustHonour(), PdfName.m) ??
      await _integerIn(await readBestEffort(), PdfName.m) ??
      PdfMonitorSpecifier.documentMonitor;

  /// Sets `/W` to 0 and `/F` to [params], the pairing Table 283 requires for
  /// a floating window.
  PdfMediaScreenParams setFloatingWindow(PdfFloatingWindowParams params,
      {bool bestEffortOnly = true}) {
    final target = _target(bestEffortOnly);
    target.put(PdfName.w, PdfNumber.fromInt(PdfMediaWindowType.floating));
    target.put(PdfName.f, params.pdfRepresentation());
    return this;
  }

  /// Gets the effective `/F`, preferring `/MH` over `/BE`.
  Future<PdfFloatingWindowParams?> getFloatingWindow() async {
    final mustHonour =
        await (await readMustHonour())?.dictionaryEntry(PdfName.f);
    if (mustHonour != null) return PdfFloatingWindowParams(mustHonour);
    final bestEffort =
        await (await readBestEffort())?.dictionaryEntry(PdfName.f);
    return bestEffort == null ? null : PdfFloatingWindowParams(bestEffort);
  }

  /// Whether the object satisfies the `/W` / `/F` pairing of Table 283: a
  /// floating window requires a floating window parameters dictionary.
  Future<bool> isViable() async {
    final mustHonour = await _integerIn(await readMustHonour(), PdfName.w);
    if (mustHonour != null && !PdfMediaWindowType.isValid(mustHonour)) {
      return false;
    }
    if (await getWindowType() != PdfMediaWindowType.floating) return true;
    return await getFloatingWindow() != null;
  }

  PdfDictionary _target(bool bestEffortOnly) =>
      bestEffortOnly ? bestEffort() : mustHonour();

  static Future<int?> _integerIn(
          PdfDictionary? dictionary, PdfName key) async =>
      dictionary == null ? null : await dictionary.integerEntry(key);
}
