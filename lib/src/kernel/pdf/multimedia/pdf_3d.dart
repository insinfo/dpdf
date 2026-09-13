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

/// 3D activation dictionary.
///
/// See ISO 32000-1:2008, 13.6.2 "3D Annotations", Table 299.
class Pdf3DActivation extends PdfObjectWrapper<PdfDictionary> {
  /// `/A /PO`: activate as soon as the page is opened.
  static final PdfName activationPageOpen = PdfName.intern('PO');

  /// `/A /PV`: activate as soon as any part of the page becomes visible.
  static final PdfName activationPageVisible = PdfName.intern('PV');

  /// `/A /XA`: stay inactive until explicitly activated. The default.
  static final PdfName activationExplicit = PdfName.intern('XA');

  /// `/D /PC`: deactivate as soon as the page is closed.
  static final PdfName deactivationPageClose = PdfName.intern('PC');

  /// `/D /PI`: deactivate as soon as the page becomes invisible. The default.
  static final PdfName deactivationPageInvisible = PdfName.intern('PI');

  /// `/D /XD`: stay active until explicitly deactivated.
  static final PdfName deactivationExplicit = PdfName.intern('XD');

  /// Artwork state `/U`: uninstantiated.
  static final PdfName stateUninstantiated = PdfName.u;

  /// Artwork state `/I`: instantiated, script-driven animations disabled.
  static final PdfName stateInstantiated = PdfName.intern('I');

  /// Artwork state `/L`: live, real-time animations enabled.
  static final PdfName stateLive = PdfName.intern('L');

  static final Set<String> _activations = {
    activationPageOpen.getValue(),
    activationPageVisible.getValue(),
    activationExplicit.getValue(),
  };

  static final Set<String> _deactivations = {
    deactivationPageClose.getValue(),
    deactivationPageInvisible.getValue(),
    deactivationExplicit.getValue(),
  };

  static final PdfName _ais = PdfName.intern('AIS');
  static final PdfName _dis = PdfName.intern('DIS');
  static final PdfName _tb = PdfName.intern('TB');
  static final PdfName _np = PdfName.intern('NP');

  Pdf3DActivation(super.pdfObject);

  /// Creates a 3D activation dictionary; every entry of Table 299 is
  /// optional, and the defaults are `/A /XA`, `/AIS /L`, `/D /PI`, `/DIS /U`,
  /// `/TB true` and `/NP false`.
  Pdf3DActivation.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/A`, when the annotation shall be activated.
  Pdf3DActivation setActivation(PdfName when) {
    if (!_activations.contains(when.getValue())) {
      throw ArgumentError.value(when, 'when',
          '3D activation /A shall be /PO, /PV or /XA (Table 299)');
    }
    pdfRepresentation().put(PdfName.a, when);
    return this;
  }

  /// Gets `/A`; the default is `/XA` per Table 299.
  Future<PdfName> getActivation() async =>
      await pdfRepresentation().nameEntry(PdfName.a) ?? activationExplicit;

  /// Sets `/D`, when the annotation shall be deactivated.
  Pdf3DActivation setDeactivation(PdfName when) {
    if (!_deactivations.contains(when.getValue())) {
      throw ArgumentError.value(when, 'when',
          '3D activation /D shall be /PC, /PI or /XD (Table 299)');
    }
    pdfRepresentation().put(PdfName.d, when);
    return this;
  }

  /// Gets `/D`; the default is `/PI` per Table 299.
  Future<PdfName> getDeactivation() async =>
      await pdfRepresentation().nameEntry(PdfName.d) ??
      deactivationPageInvisible;

  /// Sets `/AIS`, the artwork state on activation. Table 299 allows `/I` and
  /// `/L` only.
  Pdf3DActivation setActivationState(PdfName state) {
    final value = state.getValue();
    if (value != stateInstantiated.getValue() &&
        value != stateLive.getValue()) {
      throw ArgumentError.value(
          state, 'state', '3D activation /AIS shall be /I or /L (Table 299)');
    }
    pdfRepresentation().put(_ais, state);
    return this;
  }

  /// Gets `/AIS`; the default is `/L` per Table 299.
  Future<PdfName> getActivationState() async =>
      await pdfRepresentation().nameEntry(_ais) ?? stateLive;

  /// Sets `/DIS`, the artwork state on deactivation. Table 299 allows `/U`,
  /// `/I` and `/L`.
  Pdf3DActivation setDeactivationState(PdfName state) {
    final value = state.getValue();
    if (value != stateUninstantiated.getValue() &&
        value != stateInstantiated.getValue() &&
        value != stateLive.getValue()) {
      throw ArgumentError.value(state, 'state',
          '3D activation /DIS shall be /U, /I or /L (Table 299)');
    }
    pdfRepresentation().put(_dis, state);
    return this;
  }

  /// Gets `/DIS`; the default is `/U` per Table 299.
  Future<PdfName> getDeactivationState() async =>
      await pdfRepresentation().nameEntry(_dis) ?? stateUninstantiated;

  /// Sets `/TB`, whether a toolbar is displayed by default (PDF 1.7).
  Pdf3DActivation setShowToolbar(bool show) {
    pdfRepresentation().put(_tb, PdfBoolean(show));
    return this;
  }

  /// Gets `/TB`; the default is true per Table 299.
  Future<bool> isShowToolbar() async =>
      (await pdfRepresentation().booleanEntry(_tb))?.getValue() ?? true;

  /// Sets `/NP`, whether the model tree user interface is shown by default
  /// (PDF 1.7).
  Pdf3DActivation setShowModelTree(bool show) {
    pdfRepresentation().put(_np, PdfBoolean(show));
    return this;
  }

  /// Gets `/NP`; the default is false per Table 299.
  Future<bool> isShowModelTree() async =>
      (await pdfRepresentation().booleanEntry(_np))?.getValue() ?? false;
}

/// 3D animation style dictionary.
///
/// See ISO 32000-1:2008, 13.6.3.2 "3D Animation Style Dictionaries",
/// Tables 301 and 302 (PDF 1.7).
class Pdf3DAnimationStyle extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /3DAnimationStyle`.
  static final PdfName typeValue = PdfName.intern('3DAnimationStyle');

  /// `/Subtype /None`: the reader does not drive keyframe animations. The
  /// default of Table 301.
  static final PdfName styleNone = PdfName.intern('None');

  /// `/Subtype /Linear`: animations run linearly from beginning to end.
  static final PdfName styleLinear = PdfName.intern('Linear');

  /// `/Subtype /Oscillating`: animations run forward then backward.
  static final PdfName styleOscillating = PdfName.intern('Oscillating');

  static final Set<String> _styles = {
    styleNone.getValue(),
    styleLinear.getValue(),
    styleOscillating.getValue(),
  };

  static final PdfName _pc = PdfName.intern('PC');
  static final PdfName _tm = PdfName.intern('TM');

  Pdf3DAnimationStyle(super.pdfObject);

  /// Creates a 3D animation style dictionary of the given `/Subtype`.
  Pdf3DAnimationStyle.ofStyle(PdfName style) : super(PdfDictionary()) {
    if (!_styles.contains(style.getValue())) {
      throw ArgumentError.value(
          style,
          'style',
          '3D animation /Subtype shall be /None, /Linear or /Oscillating '
              '(Table 302)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, style);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/Subtype`; the default is `/None` per Table 301, and Table 302
  /// says an unrecognised style is treated as `/None`.
  Future<PdfName> getStyle() async {
    final style = await pdfRepresentation().nameEntry(PdfName.subtype);
    if (style == null || !_styles.contains(style.getValue())) return styleNone;
    return style;
  }

  /// Sets `/PC`, the play count. Table 301 lets a negative value mean
  /// "repeat forever" and ignores the entry for the `/None` style.
  Pdf3DAnimationStyle setPlayCount(int count) {
    pdfRepresentation().put(_pc, PdfNumber.fromInt(count));
    return this;
  }

  /// Gets `/PC`; the default is 0 per Table 301.
  Future<int> getPlayCount() async =>
      await pdfRepresentation().integerEntry(_pc) ?? 0;

  /// Whether `/PC` asks for endless repetition, that is a negative value.
  Future<bool> isRepeatForever() async => (await getPlayCount()) < 0;

  /// Sets `/TM`, the positive time multiplier of Table 301.
  Pdf3DAnimationStyle setTimeMultiplier(double multiplier) {
    if (multiplier.isNaN || multiplier <= 0) {
      throw ArgumentError.value(multiplier, 'multiplier',
          '3D animation /TM shall be a positive number (Table 301)');
    }
    pdfRepresentation().put(_tm, PdfNumber(multiplier));
    return this;
  }

  /// Gets `/TM`; the default is 1 per Table 301.
  Future<double> getTimeMultiplier() async =>
      (await pdfRepresentation().numberEntry(_tm))?.getValue() ?? 1.0;
}

/// 3D projection dictionary.
///
/// See ISO 32000-1:2008, 13.6.4.2 "Projection Dictionaries", Table 305.
class Pdf3DProjection extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /Projection`.
  static final PdfName typeValue = PdfName.intern('Projection');

  /// `/Subtype /O`: an orthographic projection.
  static final PdfName subtypeOrthographic = PdfName.o;

  /// `/Subtype /P`: a perspective projection. The default of Table 304.
  static final PdfName subtypePerspective = PdfName.p;

  /// `/CS /XNF`: the `/N` and `/F` entries clip explicitly.
  static final PdfName clippingExplicit = PdfName.intern('XNF');

  /// `/CS /ANF`: near and far planes are found automatically. The default.
  static final PdfName clippingAutomatic = PdfName.intern('ANF');

  /// The `/PS` and `/OB` names of Table 305, which scale the projection to
  /// the width, height, lesser or greater dimension of the 3D view box.
  static const List<String> scaleNames = ['W', 'H', 'Min', 'Max'];

  /// The extra `/OB` value of Table 305: no scaling from binding.
  static const String bindAbsolute = 'Absolute';

  static final PdfName _cs = PdfName.intern('CS');
  static final PdfName _fov = PdfName.intern('FOV');
  static final PdfName _ps = PdfName.intern('PS');
  static final PdfName _os = PdfName.intern('OS');
  static final PdfName _ob = PdfName.intern('OB');

  Pdf3DProjection(super.pdfObject);

  /// Creates a perspective projection with the given field of view, in
  /// degrees. Table 305 requires `/FOV` when `/Subtype` is `/P` and
  /// constrains it to [0, 180]; Table 304 defaults a view's projection to a
  /// perspective one with `/FOV` 90.
  Pdf3DProjection.perspective({double fieldOfView = 90})
      : super(PdfDictionary()) {
    if (fieldOfView.isNaN || fieldOfView < 0 || fieldOfView > 180) {
      throw ArgumentError.value(fieldOfView, 'fieldOfView',
          'A perspective /FOV shall lie in [0, 180] degrees (Table 305)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, subtypePerspective)
      ..put(_fov, PdfNumber(fieldOfView));
  }

  /// Creates an orthographic projection. Table 305 defaults `/OS`, the scale
  /// factor applied to x and y, to 1.
  Pdf3DProjection.orthographic({double? scale}) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, subtypeOrthographic);
    if (scale != null) setOrthographicScale(scale);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/Subtype`.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.subtype);

  /// Gets `/FOV`, the field of view of a perspective projection.
  Future<double?> getFieldOfView() async =>
      (await pdfRepresentation().numberEntry(_fov))?.getValue();

  /// Sets `/CS /XNF` together with the near and far clipping distances of
  /// Table 305. `/N` shall be positive for a perspective projection and
  /// non-negative for an orthographic one; `/F` may be omitted, in which case
  /// no far clipping occurs.
  Future<Pdf3DProjection> setExplicitClipping(double near,
      {double? far}) async {
    final perspective =
        (await getSubtype())?.getValue() == subtypePerspective.getValue();
    if (near.isNaN || (perspective ? near <= 0 : near < 0)) {
      throw ArgumentError.value(
          near,
          'near',
          perspective
              ? 'A perspective projection /N shall be positive (Table 305)'
              : 'An orthographic projection /N shall be non-negative '
                  '(Table 305)');
    }
    if (far != null && (far.isNaN || far < near)) {
      throw ArgumentError.value(far, 'far',
          'The far clipping distance /F shall not precede /N (Table 305)');
    }
    pdfRepresentation()
      ..put(_cs, clippingExplicit)
      ..put(PdfName.n, PdfNumber(near));
    if (far != null) pdfRepresentation().put(PdfName.f, PdfNumber(far));
    return this;
  }

  /// Gets `/CS`; the default is `/ANF` per Table 305.
  Future<PdfName> getClippingStyle() async =>
      await pdfRepresentation().nameEntry(_cs) ?? clippingAutomatic;

  /// Gets `/N`, the near clipping distance.
  Future<double?> getNearClipping() async =>
      (await pdfRepresentation().numberEntry(PdfName.n))?.getValue();

  /// Gets `/F`, the far clipping distance.
  Future<double?> getFarClipping() async =>
      (await pdfRepresentation().numberEntry(PdfName.f))?.getValue();

  /// Sets `/PS` to an explicit positive diameter in the annotation's target
  /// coordinate system (Table 305; meaningful only for `/Subtype /P`).
  Pdf3DProjection setProjectionScaleDiameter(double diameter) {
    if (diameter.isNaN || diameter <= 0) {
      throw ArgumentError.value(diameter, 'diameter',
          'Projection /PS as a number shall be positive (Table 305)');
    }
    pdfRepresentation().put(_ps, PdfNumber(diameter));
    return this;
  }

  /// Sets `/PS` to one of the names of [scaleNames].
  Pdf3DProjection setProjectionScaleName(String name) {
    if (!scaleNames.contains(name)) {
      throw ArgumentError.value(name, 'name',
          'Projection /PS as a name shall be W, H, Min or Max (Table 305)');
    }
    pdfRepresentation().put(_ps, PdfName.intern(name));
    return this;
  }

  /// Gets `/PS` as written; the default is the name `/W` per Table 305.
  Future<PdfObject?> getProjectionScale() async =>
      await pdfRepresentation().get(_ps, true);

  /// Sets `/OS`, the positive scale factor of an orthographic projection.
  Pdf3DProjection setOrthographicScale(double scale) {
    if (scale.isNaN || scale <= 0) {
      throw ArgumentError.value(scale, 'scale',
          'Projection /OS shall be a positive number (Table 305)');
    }
    pdfRepresentation().put(_os, PdfNumber(scale));
    return this;
  }

  /// Gets `/OS`; the default is 1 per Table 305.
  Future<double> getOrthographicScale() async =>
      (await pdfRepresentation().numberEntry(_os))?.getValue() ?? 1.0;

  /// Sets `/OB`, the binding strategy of an orthographic projection
  /// (PDF 1.7): one of [scaleNames] or [bindAbsolute].
  Pdf3DProjection setOrthographicBinding(String binding) {
    if (!scaleNames.contains(binding) && binding != bindAbsolute) {
      throw ArgumentError.value(binding, 'binding',
          'Projection /OB shall be W, H, Min, Max or Absolute (Table 305)');
    }
    pdfRepresentation().put(_ob, PdfName.intern(binding));
    return this;
  }

  /// Gets `/OB`; the default is `/Absolute` per Table 305.
  Future<PdfName> getOrthographicBinding() async =>
      await pdfRepresentation().nameEntry(_ob) ?? PdfName.intern(bindAbsolute);
}

/// 3D background dictionary.
///
/// See ISO 32000-1:2008, 13.6.4.3 "3D Background Dictionaries", Table 306.
class Pdf3DBackground extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /3DBG`.
  static final PdfName typeValue = PdfName.intern('3DBG');

  /// `/Subtype /SC`: the background is a single colour.
  static final PdfName subtypeSolidColour = PdfName.intern('SC');

  static final PdfName _cs = PdfName.intern('CS');
  static final PdfName _ea = PdfName.intern('EA');

  Pdf3DBackground(super.pdfObject);

  /// Creates a solid background of the given colour in the named colour
  /// space. `/CS` and `/C` give the colour; Table 306 defaults them to
  /// `/DeviceRGB` white.
  Pdf3DBackground.solid(List<double> colour,
      {PdfName? colourSpace, bool? applyToEntireAnnotation})
      : super(PdfDictionary()) {
    if (colour.isEmpty) {
      throw ArgumentError.value(
          colour, 'colour', '3D background /C shall hold colour components');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, subtypeSolidColour)
      ..put(_cs, colourSpace ?? PdfName.deviceRgb)
      ..put(PdfName.c, PdfArray.fromDoubles(colour));
    if (applyToEntireAnnotation != null) {
      pdfRepresentation().put(_ea, PdfBoolean(applyToEntireAnnotation));
    }
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/CS`; the default is `/DeviceRGB` per Table 306.
  Future<PdfName> getColourSpace() async =>
      await pdfRepresentation().nameEntry(_cs) ?? PdfName.deviceRgb;

  /// Gets `/C`; the default of Table 306 is white.
  Future<List<double>?> getColour() async =>
      await (await pdfRepresentation().arrayEntry(PdfName.c))?.toDoubleArray();

  /// Gets `/EA`, whether the background fills the whole annotation rather
  /// than only the 3D view box; the default is false per Table 306.
  Future<bool> isEntireAnnotation() async =>
      (await pdfRepresentation().booleanEntry(_ea))?.getValue() ?? false;
}

/// 3D render mode dictionary.
///
/// See ISO 32000-1:2008, 13.6.4.4 "3D Render Mode Dictionaries", Table 307
/// (PDF 1.7).
class Pdf3DRenderMode extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /3DRenderMode`.
  static final PdfName typeValue = PdfName.intern('3DRenderMode');

  /// The `/Subtype` values of Table 307.
  static const List<String> styles = [
    'Solid',
    'SolidWireframe',
    'Transparent',
    'TransparentWireframe',
    'BoundingBox',
    'TransparentBoundingBox',
    'TransparentBoundingBoxOutline',
    'Wireframe',
    'ShadedWireframe',
    'HiddenWireframe',
    'Vertices',
    'ShadedVertices',
    'Illustration',
    'SolidOutline',
    'ShadedIllustration',
  ];

  Pdf3DRenderMode(super.pdfObject);

  /// Creates a render mode dictionary of the given `/Subtype`.
  Pdf3DRenderMode.ofStyle(String style) : super(PdfDictionary()) {
    if (!styles.contains(style)) {
      throw ArgumentError.value(
          style, 'style', '3D render mode /Subtype shall be one of Table 307');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, PdfName.intern(style));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/Subtype`.
  Future<PdfName?> getStyle() async =>
      await pdfRepresentation().nameEntry(PdfName.subtype);
}

/// 3D lighting scheme dictionary.
///
/// See ISO 32000-1:2008, 13.6.4.5 "3D Lighting Scheme Dictionaries",
/// Tables 309 and 310 (PDF 1.7).
class Pdf3DLightingScheme extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /3DLightingScheme`.
  static final PdfName typeValue = PdfName.intern('3DLightingScheme');

  /// The `/Subtype` values of Table 310.
  static const List<String> schemes = [
    'Artwork',
    'None',
    'White',
    'Day',
    'Night',
    'Hard',
    'Primary',
    'Blue',
    'Red',
    'Cube',
    'CAD',
    'Headlamp',
  ];

  Pdf3DLightingScheme(super.pdfObject);

  /// Creates a lighting scheme dictionary of the given `/Subtype`.
  Pdf3DLightingScheme.ofScheme(String scheme) : super(PdfDictionary()) {
    if (!schemes.contains(scheme)) {
      throw ArgumentError.value(scheme, 'scheme',
          '3D lighting scheme /Subtype shall be one of Table 310');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, PdfName.intern(scheme));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/Subtype`; a missing entry behaves like `/Artwork`, which
  /// Table 310 says has the same effect as omitting the dictionary.
  Future<PdfName> getScheme() async =>
      await pdfRepresentation().nameEntry(PdfName.subtype) ??
      PdfName.intern('Artwork');
}

/// 3D view dictionary.
///
/// See ISO 32000-1:2008, 13.6.4 "3D Views", Table 304.
class Pdf3DView extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /3DView`.
  static final PdfName typeValue = PdfName.intern('3DView');

  /// `/MS /M`: the camera-to-world matrix is given by `/C2W`.
  static final PdfName matrixSourceMatrix = PdfName.m;

  /// `/MS /U3D`: the matrix comes from the view node named by `/U3DPath`.
  static final PdfName matrixSourceU3D = PdfName.intern('U3D');

  static final PdfName _xn = PdfName.intern('XN');
  static final PdfName _in = PdfName.intern('IN');
  static final PdfName _ms = PdfName.intern('MS');
  static final PdfName _c2w = PdfName.intern('C2W');
  static final PdfName _u3dPath = PdfName.intern('U3DPath');
  static final PdfName _co = PdfName.intern('CO');
  static final PdfName _bg = PdfName.intern('BG');
  static final PdfName _rm = PdfName.intern('RM');
  static final PdfName _ls = PdfName.intern('LS');
  static final PdfName _sa = PdfName.intern('SA');
  static final PdfName _na = PdfName.intern('NA');
  static final PdfName _nr = PdfName.intern('NR');

  Pdf3DView(super.pdfObject);

  /// Creates a 3D view named [externalName]. `/XN` is the only required entry
  /// of Table 304.
  Pdf3DView.named(String externalName, {String? internalName})
      : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(_xn, PdfString(externalName));
    if (internalName != null) {
      pdfRepresentation().put(_in, PdfString(internalName));
    }
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/XN`, the external name presented in a user interface.
  Future<String?> getExternalName() async =>
      (await pdfRepresentation().stringEntry(_xn))?.decodeMappingText();

  /// Gets `/IN`, the internal name used by go-to-3D-view actions (12.6.4.15).
  Future<String?> getInternalName() async =>
      (await pdfRepresentation().stringEntry(_in))?.decodeMappingText();

  /// Sets `/MS /M` and `/C2W`, the explicit twelve-element camera-to-world
  /// matrix Table 304 requires when `/MS` is `/M`.
  Pdf3DView setCameraToWorldMatrix(List<double> matrix) {
    if (matrix.length != 12) {
      throw ArgumentError.value(matrix, 'matrix',
          '3D view /C2W shall hold twelve numbers (Table 304)');
    }
    pdfRepresentation()
      ..put(_ms, matrixSourceMatrix)
      ..put(_c2w, PdfArray.fromDoubles(matrix));
    return this;
  }

  /// Gets `/C2W`.
  Future<List<double>?> getCameraToWorldMatrix() async =>
      await (await pdfRepresentation().arrayEntry(_c2w))?.toDoubleArray();

  /// Sets `/MS /U3D` and `/U3DPath`, the view node path Table 304 requires
  /// when `/MS` is `/U3D`. Conforming writers should specify a single text
  /// string rather than an array.
  Pdf3DView setU3DPath(List<String> nodeIds) {
    if (nodeIds.isEmpty) {
      throw ArgumentError.value(nodeIds, 'nodeIds',
          '3D view /U3DPath shall name at least one view node (Table 304)');
    }
    pdfRepresentation().put(_ms, matrixSourceU3D);
    pdfRepresentation().put(
        _u3dPath,
        nodeIds.length == 1
            ? PdfString(nodeIds.single)
            : PdfArray.fromStrings(nodeIds));
    return this;
  }

  /// Gets `/U3DPath`, accepting both the text string and the array form.
  Future<List<String>> getU3DPath() async {
    final value = await pdfRepresentation().get(_u3dPath, true);
    if (value is PdfString) return [value.decodeMappingText()];
    if (value is PdfArray) {
      final result = <String>[];
      for (var i = 0; i < value.size(); i++) {
        final item = await value.stringEntry(i);
        if (item != null) result.add(item.decodeMappingText());
      }
      return result;
    }
    return const <String>[];
  }

  /// Gets `/MS`, which says how the camera-to-world matrix is determined.
  /// A missing entry means the view stored in the 3D artwork is used.
  Future<PdfName?> getMatrixSource() async =>
      await pdfRepresentation().nameEntry(_ms);

  /// Sets `/CO`, the non-negative distance along the camera z axis to the
  /// centre of orbit. Table 304 uses it only when `/MS` is present.
  Pdf3DView setCentreOfOrbit(double distance) {
    if (distance.isNaN || distance < 0) {
      throw ArgumentError.value(distance, 'distance',
          '3D view /CO shall be a non-negative number (Table 304)');
    }
    pdfRepresentation().put(_co, PdfNumber(distance));
    return this;
  }

  /// Gets `/CO`; when absent, the reader determines the centre of orbit.
  Future<double?> getCentreOfOrbit() async =>
      (await pdfRepresentation().numberEntry(_co))?.getValue();

  /// Sets `/P`, the projection dictionary.
  Pdf3DView setProjection(Pdf3DProjection projection) {
    pdfRepresentation().put(PdfName.p, projection.pdfRepresentation());
    return this;
  }

  /// Gets `/P`; Table 304 defaults it to a perspective projection with a
  /// field of view of 90 degrees.
  Future<Pdf3DProjection?> getProjection() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.p);
    return dictionary == null ? null : Pdf3DProjection(dictionary);
  }

  /// Sets `/O`, the form XObject overlaying 2D graphics on the artwork
  /// (13.6.6 "3D Markup"). Table 304 makes it meaningful only when `/MS` and
  /// `/P` are present.
  Pdf3DView setOverlay(PdfStream form) {
    pdfRepresentation().put(PdfName.o, form);
    return this;
  }

  /// Gets `/O`.
  Future<PdfStream?> getOverlay() async =>
      await pdfRepresentation().streamEntry(PdfName.o);

  /// Sets `/BG`, the background dictionary.
  Pdf3DView setBackground(Pdf3DBackground background) {
    pdfRepresentation().put(_bg, background.pdfRepresentation());
    return this;
  }

  /// Gets `/BG`.
  Future<Pdf3DBackground?> getBackground() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_bg);
    return dictionary == null ? null : Pdf3DBackground(dictionary);
  }

  /// Sets `/RM`, the render mode dictionary (PDF 1.7).
  Pdf3DView setRenderMode(Pdf3DRenderMode renderMode) {
    pdfRepresentation().put(_rm, renderMode.pdfRepresentation());
    return this;
  }

  /// Gets `/RM`; when absent, the render mode of the artwork is used.
  Future<Pdf3DRenderMode?> getRenderMode() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_rm);
    return dictionary == null ? null : Pdf3DRenderMode(dictionary);
  }

  /// Sets `/LS`, the lighting scheme dictionary (PDF 1.7).
  Pdf3DView setLightingScheme(Pdf3DLightingScheme scheme) {
    pdfRepresentation().put(_ls, scheme.pdfRepresentation());
    return this;
  }

  /// Gets `/LS`; when absent, the lighting of the artwork is used.
  Future<Pdf3DLightingScheme?> getLightingScheme() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_ls);
    return dictionary == null ? null : Pdf3DLightingScheme(dictionary);
  }

  /// Sets `/SA`, the cross section dictionaries (PDF 1.7). An empty array
  /// means no cross sections are displayed.
  Pdf3DView setCrossSections(List<PdfDictionary> crossSections) {
    pdfRepresentation().put(_sa, PdfArray.fromList(crossSections));
    return this;
  }

  /// Gets `/SA`.
  Future<PdfArray?> getCrossSections() async =>
      await pdfRepresentation().arrayEntry(_sa);

  /// Sets `/NA`, the 3D node dictionaries (PDF 1.7), and `/NR`, whether the
  /// nodes are first restored to their original states. Table 304 makes `/NA`
  /// meaningful only when `/NR` is present.
  Pdf3DView setNodes(List<PdfDictionary> nodes, {required bool restoreFirst}) {
    pdfRepresentation()
      ..put(_na, PdfArray.fromList(nodes))
      ..put(_nr, PdfBoolean(restoreFirst));
    return this;
  }

  /// Gets `/NA`.
  Future<PdfArray?> getNodes() async =>
      await pdfRepresentation().arrayEntry(_na);

  /// Gets `/NR`; the default is false.
  Future<bool> isRestoreNodes() async =>
      (await pdfRepresentation().booleanEntry(_nr))?.getValue() ?? false;

  /// Whether the `/MS` requirements of Table 304 hold: `/M` demands `/C2W`
  /// and `/U3D` demands `/U3DPath`.
  Future<bool> isMatrixSourceSatisfied() async {
    final source = (await getMatrixSource())?.getValue();
    if (source == null) return true;
    if (source == matrixSourceMatrix.getValue()) {
      return (await getCameraToWorldMatrix())?.length == 12;
    }
    if (source == matrixSourceU3D.getValue()) {
      return (await getU3DPath()).isNotEmpty;
    }
    return false;
  }
}

/// 3D stream.
///
/// See ISO 32000-1:2008, 13.6.3 "3D Streams", Table 300. The artwork data
/// itself is opaque to PDF; only its `/Subtype` identifies the format.
class Pdf3DStream extends PdfObjectWrapper<PdfStream> {
  /// `/Type /3D`.
  static final PdfName typeValue = PdfName.threeD;

  /// `/Subtype /U3D`, the Universal 3D format; the only value Table 300
  /// defines for ISO 32000-1.
  static final PdfName subtypeU3D = PdfName.intern('U3D');

  /// `/Subtype /PRC`, the format added by ISO 32000-2 and used by PDF/E.
  static final PdfName subtypePRC = PdfName.intern('PRC');

  /// `/DV /F`: the first entry of `/VA` is the default view.
  static final PdfName defaultViewFirst = PdfName.f;

  /// `/DV /L`: the last entry of `/VA` is the default view.
  static final PdfName defaultViewLast = PdfName.intern('L');

  static final PdfName _va = PdfName.intern('VA');
  static final PdfName _dv = PdfName.intern('DV');
  static final PdfName _resources = PdfName.intern('Resources');
  static final PdfName _onInstantiate = PdfName.intern('OnInstantiate');
  static final PdfName _an = PdfName.intern('AN');

  Pdf3DStream(super.pdfObject);

  /// Creates a 3D stream carrying [artwork] bytes in the given `/Subtype`.
  /// `/Subtype` is required by Table 300.
  Pdf3DStream.fromArtwork(Uint8List artwork, PdfName subtype,
      {int compressionLevel = 0})
      : super(PdfStream.withBytes(artwork, compressionLevel)) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.subtype, subtype);
  }

  /// A 3D stream is referenced from annotations and reference dictionaries,
  /// so it is stored indirectly.
  @override
  bool requiresIndirectStorage() => true;

  /// Gets `/Subtype`, the format of the artwork data.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.subtype);

  /// Gets the decoded artwork bytes. The content is opaque to PDF.
  Future<Uint8List?> getArtwork() async => await pdfRepresentation().getBytes();

  /// Sets `/VA`, the named preset views, in the order a user interface shall
  /// present them.
  Pdf3DStream setViews(List<Pdf3DView> views) {
    pdfRepresentation().put(
        _va,
        PdfArray.fromList(
            views.map((view) => view.pdfRepresentation()).toList()));
    return this;
  }

  /// Gets `/VA`.
  Future<List<Pdf3DView>> getViews() async {
    final array = await pdfRepresentation().arrayEntry(_va);
    if (array == null) return const <Pdf3DView>[];
    final result = <Pdf3DView>[];
    for (var i = 0; i < array.size(); i++) {
      final dictionary = await array.dictionaryEntry(i);
      if (dictionary != null) result.add(Pdf3DView(dictionary));
    }
    return result;
  }

  /// Sets `/DV` to an index into `/VA`.
  Pdf3DStream setDefaultViewIndex(int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index',
          '3D stream /DV shall index /VA from zero (Table 300)');
    }
    pdfRepresentation().put(_dv, PdfNumber.fromInt(index));
    return this;
  }

  /// Sets `/DV` to a text string matching the `/IN` entry of a view in `/VA`.
  Pdf3DStream setDefaultViewName(String internalName) {
    pdfRepresentation().put(_dv, PdfString(internalName));
    return this;
  }

  /// Sets `/DV` to `/F` or `/L`, the first or last entry of `/VA`.
  Pdf3DStream setDefaultViewPosition(PdfName position) {
    final value = position.getValue();
    if (value != defaultViewFirst.getValue() &&
        value != defaultViewLast.getValue()) {
      throw ArgumentError.value(position, 'position',
          '3D stream /DV as a name shall be /F or /L (Table 300)');
    }
    pdfRepresentation().put(_dv, position);
    return this;
  }

  /// Gets `/DV` as written.
  Future<PdfObject?> getDefaultView() async =>
      await pdfRepresentation().get(_dv, true);

  /// Resolves `/DV` against `/VA`, applying the default of Table 300: index 0
  /// when `/VA` is present and `/DV` is absent.
  Future<Pdf3DView?> resolveDefaultView() async {
    final views = await getViews();
    if (views.isEmpty) return null;
    final dv = await getDefaultView();
    if (dv == null) return views.first;
    if (dv is PdfNumber) {
      final index = dv.getValue().toInt();
      return index >= 0 && index < views.length ? views[index] : null;
    }
    if (dv is PdfName) {
      if (dv.getValue() == defaultViewFirst.getValue()) return views.first;
      if (dv.getValue() == defaultViewLast.getValue()) return views.last;
      return null;
    }
    if (dv is PdfString) {
      final wanted = dv.decodeMappingText();
      for (final view in views) {
        if (await view.getInternalName() == wanted) return view;
      }
    }
    return null;
  }

  /// Sets `/Resources`, the name tree of objects scripts may use to modify
  /// the default view.
  Pdf3DStream setResources(PdfDictionary nameTree) {
    pdfRepresentation().put(_resources, nameTree);
    return this;
  }

  /// Gets `/Resources`.
  Future<PdfDictionary?> getResources() async =>
      await pdfRepresentation().dictionaryEntry(_resources);

  /// Sets `/OnInstantiate`, the JavaScript stream run when the 3D stream is
  /// instantiated.
  Pdf3DStream setOnInstantiate(PdfStream script) {
    pdfRepresentation().put(_onInstantiate, script);
    return this;
  }

  /// Gets `/OnInstantiate`.
  Future<PdfStream?> getOnInstantiate() async =>
      await pdfRepresentation().streamEntry(_onInstantiate);

  /// Sets `/AN`, the animation style dictionary (PDF 1.7).
  Pdf3DStream setAnimationStyle(Pdf3DAnimationStyle style) {
    pdfRepresentation().put(_an, style.pdfRepresentation());
    return this;
  }

  /// Gets `/AN`; Table 300 defaults it to an animation style whose
  /// `/Subtype` is `/None`.
  Future<Pdf3DAnimationStyle?> getAnimationStyle() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_an);
    return dictionary == null ? null : Pdf3DAnimationStyle(dictionary);
  }
}

/// 3D reference dictionary.
///
/// See ISO 32000-1:2008, 13.6.3.3 "3D Reference Dictionaries", Table 303.
/// Annotations that share a reference dictionary share one run-time instance
/// of the artwork.
class Pdf3DReference extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /3DRef`.
  static final PdfName typeValue = PdfName.intern('3DRef');

  static final PdfName _artwork = PdfName.intern('3DD');

  Pdf3DReference(super.pdfObject);

  /// Creates a 3D reference dictionary for [stream]. `/3DD` is required by
  /// Table 303 and shall be a 3D stream, not another reference dictionary.
  Pdf3DReference.to(Pdf3DStream stream) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(_artwork, stream.pdfRepresentation());
  }

  /// A reference dictionary is shared between annotations, so it is stored
  /// indirectly; sharing it is what makes them share an artwork instance.
  @override
  bool requiresIndirectStorage() => true;

  /// Gets `/3DD`, the 3D stream holding the artwork.
  Future<Pdf3DStream?> getArtworkStream() async {
    final stream = await pdfRepresentation().streamEntry(_artwork);
    return stream == null ? null : Pdf3DStream(stream);
  }
}
