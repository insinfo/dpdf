import '../../exceptions/pdf_exception.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';

/// The `/S` transition styles of ISO 32000-1:2008, 12.4.4.1, Table 162.
enum PdfPageTransitionStyle {
  /// Two lines sweep across the screen, revealing the new page.
  split('Split'),

  /// Multiple evenly spaced lines sweep in the same direction.
  blinds('Blinds'),

  /// A rectangular box sweeps inward or outward.
  box('Box'),

  /// A single line sweeps across the screen from one edge to the other.
  wipe('Wipe'),

  /// The old page dissolves gradually to reveal the new one.
  dissolve('Dissolve'),

  /// Like [dissolve], but sweeping across the page in a wide band.
  glitter('Glitter'),

  /// `/R`: the new page replaces the old one with no special effect. The
  /// Table 162 default; `/D` is ignored for it.
  replace('R'),

  /// (PDF 1.5) Changes are flown out or in.
  fly('Fly'),

  /// (PDF 1.5) The old page slides off while the new page pushes it out.
  push('Push'),

  /// (PDF 1.5) The new page slides on, covering the old page.
  cover('Cover'),

  /// (PDF 1.5) The old page slides off, uncovering the new page.
  uncover('Uncover'),

  /// (PDF 1.5) The new page gradually becomes visible through the old one.
  fade('Fade');

  const PdfPageTransitionStyle(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The style as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves an `/S` value, or `null` when unrecognized.
  static PdfPageTransitionStyle? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// Values of `/Dm`, the dimension in which the transition occurs (Table 162).
enum PdfTransitionDimension {
  /// Horizontal. The Table 162 default.
  horizontal('H'),

  /// Vertical.
  vertical('V');

  const PdfTransitionDimension(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The dimension as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves a `/Dm` value, or `null` when unrecognized.
  static PdfTransitionDimension? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// Values of `/M`, the direction of motion of the transition (Table 162).
enum PdfTransitionMotion {
  /// Inward from the edges of the page. The Table 162 default.
  inward('I'),

  /// Outward from the centre of the page.
  outward('O');

  const PdfTransitionMotion(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The motion as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves an `/M` value, or `null` when unrecognized.
  static PdfTransitionMotion? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// The transition dictionary of ISO 32000-1:2008, 12.4.4.1, Table 162.
///
/// It is the value of `/Trans` in a page object (Table 30) and describes the
/// visual transition used when moving to that page during a presentation.
/// Table 162 restricts most entries to particular styles, and this class
/// enforces those restrictions instead of writing a dictionary a conforming
/// reader would have to guess at.
class PdfTransition extends PdfObjectWrapper<PdfDictionary> {
  /// `/Trans`, both the entry name in a page object and the `/Type` value.
  static final PdfName trans = PdfName.intern('Trans');

  /// `/S`, the transition style.
  static final PdfName style = PdfName.intern('S');

  /// `/D`, the duration of the transition effect in seconds.
  static final PdfName duration = PdfName.intern('D');

  /// `/Dm`, the dimension in which the effect occurs.
  static final PdfName dimension = PdfName.intern('Dm');

  /// `/M`, the direction of motion.
  static final PdfName motion = PdfName.intern('M');

  /// `/Di`, the direction in which the effect moves.
  static final PdfName direction = PdfName.intern('Di');

  /// `/SS`, the starting or ending scale of a `/Fly` transition.
  static final PdfName scale = PdfName.intern('SS');

  /// `/B`, whether the area flown in is rectangular and opaque.
  static final PdfName opaque = PdfName.intern('B');

  /// The `/Di` name value `/None`, relevant only to `/Fly`.
  static final PdfName noneDirection = PdfName.intern('None');

  /// Styles for which Table 162 allows `/Dm`.
  static const Set<PdfPageTransitionStyle> dimensionStyles = {
    PdfPageTransitionStyle.split,
    PdfPageTransitionStyle.blinds,
  };

  /// Styles for which Table 162 allows `/M`.
  static const Set<PdfPageTransitionStyle> motionStyles = {
    PdfPageTransitionStyle.split,
    PdfPageTransitionStyle.box,
    PdfPageTransitionStyle.fly,
  };

  /// Styles for which Table 162 allows `/Di`.
  static const Set<PdfPageTransitionStyle> directionStyles = {
    PdfPageTransitionStyle.wipe,
    PdfPageTransitionStyle.glitter,
    PdfPageTransitionStyle.fly,
    PdfPageTransitionStyle.cover,
    PdfPageTransitionStyle.uncover,
    PdfPageTransitionStyle.push,
  };

  PdfPageTransitionStyle _style;

  /// Builds a transition dictionary with `/Type /Trans` and the given `/S`.
  PdfTransition([PdfPageTransitionStyle style = PdfPageTransitionStyle.replace])
      : _style = style,
        super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, trans);
    pdfRepresentation().put(PdfTransition.style, style.toPdfName());
  }

  /// Wraps an existing transition dictionary. An absent or unrecognized `/S`
  /// is read as [PdfPageTransitionStyle.replace], the Table 162 default.
  PdfTransition.wrap(PdfDictionary dictionary)
      : _style = PdfPageTransitionStyle.replace,
        super(dictionary) {
    final name = dictionary.getMap()?[PdfTransition.style];
    if (name is PdfName) {
      _style = PdfPageTransitionStyle.fromPdfName(name) ??
          PdfPageTransitionStyle.replace;
    }
  }

  /// Table 162 describes a plain dictionary, so it may stay a direct object.
  @override
  bool requiresIndirectStorage() => false;

  /// The `/S` style of this transition.
  PdfPageTransitionStyle getStyle() => _style;

  /// Sets `/S`. Entries that the new style does not allow are dropped, so the
  /// dictionary stays consistent with Table 162.
  PdfTransition setStyle(PdfPageTransitionStyle value) {
    _style = value;
    pdfRepresentation().put(style, value.toPdfName());
    if (!dimensionStyles.contains(value)) pdfRepresentation().remove(dimension);
    if (!motionStyles.contains(value)) pdfRepresentation().remove(motion);
    if (!directionStyles.contains(value)) pdfRepresentation().remove(direction);
    if (value != PdfPageTransitionStyle.fly) {
      pdfRepresentation().remove(scale);
      pdfRepresentation().remove(opaque);
    }
    markChanged();
    return this;
  }

  /// Sets `/D`, the duration of the transition in seconds. Default 1.
  /// A negative duration is not a duration and is rejected.
  PdfTransition setDuration(double seconds) {
    if (seconds < 0 || seconds.isNaN) {
      throw PdfException('/D is a duration in seconds and cannot be $seconds.');
    }
    pdfRepresentation().put(duration, PdfNumber(seconds));
    markChanged();
    return this;
  }

  /// Gets `/D`, defaulting to the Table 162 value of 1 second.
  Future<double> getDuration() async {
    return (await pdfRepresentation().numberEntry(duration))?.doubleValue() ??
        1.0;
  }

  /// Sets `/Dm`. Table 162 allows it only for `/Split` and `/Blinds`.
  PdfTransition setDimension(PdfTransitionDimension value) {
    _requireStyle(dimensionStyles, '/Dm');
    pdfRepresentation().put(dimension, value.toPdfName());
    markChanged();
    return this;
  }

  /// Gets `/Dm`, defaulting to [PdfTransitionDimension.horizontal].
  Future<PdfTransitionDimension> getDimension() async {
    return PdfTransitionDimension.fromPdfName(
            await pdfRepresentation().nameEntry(dimension)) ??
        PdfTransitionDimension.horizontal;
  }

  /// Sets `/M`. Table 162 allows it only for `/Split`, `/Box` and `/Fly`.
  PdfTransition setMotion(PdfTransitionMotion value) {
    _requireStyle(motionStyles, '/M');
    pdfRepresentation().put(motion, value.toPdfName());
    markChanged();
    return this;
  }

  /// Gets `/M`, defaulting to [PdfTransitionMotion.inward].
  Future<PdfTransitionMotion> getMotion() async {
    return PdfTransitionMotion.fromPdfName(
            await pdfRepresentation().nameEntry(motion)) ??
        PdfTransitionMotion.inward;
  }

  /// Sets the numeric form of `/Di`, in degrees counterclockwise from a
  /// left-to-right direction. Table 162 allows the entry only for `/Wipe`,
  /// `/Glitter`, `/Fly`, `/Cover`, `/Uncover` and `/Push`, and restricts the
  /// value to 0 and 270, plus 90 and 180 for `/Wipe` and 315 for `/Glitter`.
  PdfTransition setDirection(int degrees) {
    _requireStyle(directionStyles, '/Di');
    if (!_allowedDegrees().contains(degrees)) {
      throw PdfException(
          '/Di $degrees is not allowed for the /${_style.pdfName} style; '
          'Table 162 allows ${_allowedDegrees().toList()..sort()}.');
    }
    pdfRepresentation().put(direction, PdfNumber.fromInt(degrees));
    markChanged();
    return this;
  }

  /// Sets `/Di` to the name `/None`. Table 162 allows that only for `/Fly`,
  /// and only matters when `/SS` differs from 1.0.
  PdfTransition setDirectionNone() {
    if (_style != PdfPageTransitionStyle.fly) {
      throw PdfException('/Di /None is only relevant to the /Fly style, not '
          '/${_style.pdfName}.');
    }
    pdfRepresentation().put(direction, noneDirection);
    markChanged();
    return this;
  }

  /// Gets the numeric `/Di`, defaulting to 0. Returns `null` when `/Di` is the
  /// name `/None`, which [isDirectionNone] reports.
  Future<int?> getDirection() async {
    final value = await pdfRepresentation().get(direction, true);
    if (value is PdfName) return null;
    if (value is PdfNumber) return value.intValue();
    return 0;
  }

  /// Whether `/Di` is the name `/None`.
  Future<bool> isDirectionNone() async {
    final value = await pdfRepresentation().get(direction, true);
    return value is PdfName && value == noneDirection;
  }

  /// Sets `/SS` (PDF 1.5), the starting or ending scale of a `/Fly`
  /// transition. Default 1.0. Allowed only for `/Fly`, and a scale cannot be
  /// negative.
  PdfTransition setScale(double value) {
    if (_style != PdfPageTransitionStyle.fly) {
      throw PdfException(
          '/SS is only defined for the /Fly style, not /${_style.pdfName}.');
    }
    if (value < 0 || value.isNaN) {
      throw PdfException('/SS is a scale and cannot be $value.');
    }
    pdfRepresentation().put(scale, PdfNumber(value));
    markChanged();
    return this;
  }

  /// Gets `/SS`, defaulting to the Table 162 value of 1.0.
  Future<double> getScale() async {
    return (await pdfRepresentation().numberEntry(scale))?.doubleValue() ?? 1.0;
  }

  /// Sets `/B` (PDF 1.5): the area flown in is rectangular and opaque.
  /// Default `false`, allowed only for `/Fly`.
  PdfTransition setOpaque(bool value) {
    if (_style != PdfPageTransitionStyle.fly) {
      throw PdfException(
          '/B is only defined for the /Fly style, not /${_style.pdfName}.');
    }
    pdfRepresentation().put(opaque, PdfBoolean(value));
    markChanged();
    return this;
  }

  /// Gets `/B`, defaulting to `false`.
  Future<bool> getOpaque() async {
    return (await pdfRepresentation().booleanEntry(opaque))?.getValue() ??
        false;
  }

  /// Puts an arbitrary entry, for transition entries outside Table 162.
  PdfTransition put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  Set<int> _allowedDegrees() {
    switch (_style) {
      case PdfPageTransitionStyle.wipe:
        return const {0, 90, 180, 270};
      case PdfPageTransitionStyle.glitter:
        return const {0, 270, 315};
      default:
        return const {0, 270};
    }
  }

  void _requireStyle(Set<PdfPageTransitionStyle> allowed, String entry) {
    if (!allowed.contains(_style)) {
      throw PdfException(
          '$entry is not allowed for the /${_style.pdfName} style; Table 162 '
          'allows it only for '
          '${allowed.map((s) => '/${s.pdfName}').join(', ')}.');
    }
  }
}
