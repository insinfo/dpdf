import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_special_cs.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';

class PdfShading extends PdfObjectWrapper<PdfDictionary> {
  /// Shading types of ISO 32000-1, table 78.
  static const int typeFunctionBased = 1;
  static const int typeAxial = 2;
  static const int typeRadial = 3;
  static const int typeFreeFormGouraud = 4;
  static const int typeLatticeFormGouraud = 5;
  static const int typeCoonsPatch = 6;
  static const int typeTensorPatch = 7;

  /// The shading types defined by clause 8.7.4.3.
  static const Set<int> knownTypes = <int>{1, 2, 3, 4, 5, 6, 7};

  /// The types whose shading dictionary is also a stream (clause 8.7.4.3).
  static const Set<int> meshTypes = <int>{4, 5, 6, 7};

  static final PdfName backgroundKey = PdfName.intern('Background');
  static final PdfName antiAliasKey = PdfName.intern('AntiAlias');
  static final PdfName domainKey = PdfName.intern('Domain');
  static final PdfName extendKey = PdfName.intern('Extend');
  static final PdfName bitsPerCoordinateKey =
      PdfName.intern('BitsPerCoordinate');
  static final PdfName bitsPerComponentKey = PdfName.intern('BitsPerComponent');
  static final PdfName bitsPerFlagKey = PdfName.intern('BitsPerFlag');
  static final PdfName decodeKey = PdfName.intern('Decode');
  static final PdfName verticesPerRowKey = PdfName.intern('VerticesPerRow');

  PdfShading(PdfDictionary pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  /// Reads a shading dictionary or stream, ISO 32000-1, clause 8.7.4.3.
  ///
  /// Returns null when [object] is not a dictionary with a known
  /// `/ShadingType`, or when a mesh type (4 to 7) is not carried by a stream
  /// as table 78 requires.
  static Future<PdfShading?> parse(PdfObject? object) async {
    var resolved = object;
    if (resolved is PdfIndirectReference) {
      resolved = await resolved.targetObject(true);
    }
    if (resolved is! PdfDictionary) return null;

    final type = await resolved.integerEntry(PdfName.shadingType);
    if (type == null || !knownTypes.contains(type)) return null;
    if (meshTypes.contains(type) && resolved is! PdfStream) return null;
    return PdfShading(resolved);
  }

  /// The `/ShadingType` entry (table 78).
  Future<int?> getShadingType() =>
      pdfRepresentation().integerEntry(PdfName.shadingType);

  /// The `/ColorSpace` entry, resolved into a colour space.
  ///
  /// Clause 8.7.4.4 forbids `/Pattern` here, so a Pattern space is rejected.
  Future<PdfColorSpace?> getColorSpace() async {
    final space = await PdfColorSpace.makeColorSpace(
        await pdfRepresentation().get(PdfName.colorSpace, false));
    if (space is PdfSpecialCsPattern) return null;
    return space;
  }

  /// The `/Background` colour, in the components of [getColorSpace].
  ///
  /// It fills the parts of the painted area that fall outside the shading, and
  /// only when the shading is used through a shading pattern, never under the
  /// `sh` operator (table 78).
  Future<List<double>?> getBackground() async {
    final array = await pdfRepresentation().arrayEntry(backgroundKey);
    if (array == null || array.isEmpty()) return null;
    return array.toDoubleArray();
  }

  /// The `/BBox` entry: an extra clip in the target coordinate space.
  Future<Rectangle?> getBBox() async {
    return Rectangle.fromPdfArray(
        await pdfRepresentation().arrayEntry(PdfName.bBox));
  }

  /// The `/AntiAlias` flag; defaults to false (table 78).
  Future<bool> getAntiAlias() async =>
      await pdfRepresentation().flagEntry(antiAliasKey) ?? false;

  /// The `/Function` entry, which may be one function or an array of
  /// 1-in-1-out functions, one per colour component.
  ///
  /// It is required for types 1, 2 and 3 and optional for 4 to 7.
  Future<PdfFunction?> getFunction() async {
    return PdfFunction.parse(
        await pdfRepresentation().get(PdfName.function, false));
  }

  /// The `/Coords` entry: four numbers for an axial shading, six for a radial.
  Future<List<double>> getCoords() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.coords);
    if (array == null) return const <double>[];
    return array.toDoubleArray();
  }

  /// The `/Domain` entry.
  ///
  /// A function-based shading spans two inputs and defaults to `[0 1 0 1]`;
  /// the axial and radial shadings span one and default to `[0 1]`.
  Future<List<double>> getDomain() async {
    final array = await pdfRepresentation().arrayEntry(domainKey);
    if (array != null && array.size() >= 2) return array.toDoubleArray();
    final type = await getShadingType();
    if (type == typeFunctionBased) {
      return const <double>[0.0, 1.0, 0.0, 1.0];
    }
    return const <double>[0.0, 1.0];
  }

  /// The `/Matrix` of a function-based shading; defaults to the identity.
  Future<List<double>> getMatrix() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.matrix);
    if (array == null || array.size() < 6) {
      return const <double>[1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
    }
    return array.toDoubleArray();
  }

  /// The `/Extend` entry of an axial or radial shading; defaults to
  /// `[false false]`.
  Future<List<bool>> getExtend() async {
    final array = await pdfRepresentation().arrayEntry(extendKey);
    if (array == null || array.size() < 2) return const <bool>[false, false];
    final start = await array.booleanEntry(0);
    final end = await array.booleanEntry(1);
    return <bool>[start?.getValue() ?? false, end?.getValue() ?? false];
  }

  /// The `/BitsPerCoordinate` entry of a mesh shading (types 4 to 7).
  Future<int?> getBitsPerCoordinate() =>
      pdfRepresentation().integerEntry(bitsPerCoordinateKey);

  /// The `/BitsPerComponent` entry of a mesh shading (types 4 to 7).
  Future<int?> getBitsPerComponent() =>
      pdfRepresentation().integerEntry(bitsPerComponentKey);

  /// The `/BitsPerFlag` entry of a mesh shading (types 4, 6 and 7).
  Future<int?> getBitsPerFlag() =>
      pdfRepresentation().integerEntry(bitsPerFlagKey);

  /// The `/VerticesPerRow` entry of a lattice-form mesh (type 5).
  Future<int?> getVerticesPerRow() =>
      pdfRepresentation().integerEntry(verticesPerRowKey);

  /// The `/Decode` entry of a mesh shading: the ranges the packed coordinates
  /// and colour components are spread over.
  Future<List<double>> getDecode() async {
    final array = await pdfRepresentation().arrayEntry(decodeKey);
    if (array == null) return const <double>[];
    return array.toDoubleArray();
  }

  /// The colour a shading paints at parametric position [t], in sRGB.
  ///
  /// This is the colour pipeline of clause 8.7.4.5: the value is clipped into
  /// `/Domain`, handed to `/Function`, and the result read in the shading
  /// colour space. Returns null when the shading has no function or no usable
  /// colour space, which is the case for the mesh types.
  Future<List<double>?> colorAt(double t) async {
    final function = await getFunction();
    final space = await getColorSpace();
    if (function == null || space == null) return null;
    final domain = await getDomain();
    final clipped = PdfFunction.clip(t, domain[0], domain[1]);
    return space.toRgb(function.evaluate(<double>[clipped]));
  }

  static PdfShading createAxial(PdfName colorSpace, double x0, double y0,
      double x1, double y1, List<double> coords, PdfObject function) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.shadingType, PdfNumber(2)); // Axial
    dict.put(PdfName.colorSpace, colorSpace);
    dict.put(PdfName.coords, PdfArray.fromDoubles([x0, y0, x1, y1]));
    dict.put(PdfName.function, function);
    dict.put(PdfName.intern('Extend'), PdfArray.fromBooleans([true, true]));
    return PdfShading(dict);
  }

  static PdfShading createRadial(PdfName colorSpace, double x0, double y0,
      double r0, double x1, double y1, double r1, PdfObject function) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.shadingType, PdfNumber(3)); // Radial
    dict.put(PdfName.colorSpace, colorSpace);
    dict.put(PdfName.coords, PdfArray.fromDoubles([x0, y0, r0, x1, y1, r1]));
    dict.put(PdfName.function, function);
    dict.put(PdfName.intern('Extend'), PdfArray.fromBooleans([true, true]));
    return PdfShading(dict);
  }

  /// Cria um shading axial DeviceRGB entre duas cores normalizadas.
  static PdfShading axialRgb(double x0, double y0, double x1, double y1,
      List<double> start, List<double> end,
      {bool extendStart = true, bool extendEnd = true}) {
    _checkRgb(start);
    _checkRgb(end);
    return _gradient(
      type: 2,
      coords: [x0, y0, x1, y1],
      start: start,
      end: end,
      extendStart: extendStart,
      extendEnd: extendEnd,
    );
  }

  /// Shading axial com qualquer quantidade de paradas de cor.
  static PdfShading axialRgbStops(double x0, double y0, double x1, double y1,
      List<double> offsets, List<List<double>> colors,
      {bool extendStart = true, bool extendEnd = true}) {
    return _gradientStops(
      type: 2,
      coords: [x0, y0, x1, y1],
      offsets: offsets,
      colors: colors,
      extendStart: extendStart,
      extendEnd: extendEnd,
    );
  }

  /// Cria um shading radial DeviceRGB entre dois círculos.
  static PdfShading radialRgb(double x0, double y0, double r0, double x1,
      double y1, double r1, List<double> start, List<double> end,
      {bool extendStart = true, bool extendEnd = true}) {
    if (r0 < 0 || r1 < 0) throw ArgumentError('Radii cannot be negative.');
    _checkRgb(start);
    _checkRgb(end);
    return _gradient(
      type: 3,
      coords: [x0, y0, r0, x1, y1, r1],
      start: start,
      end: end,
      extendStart: extendStart,
      extendEnd: extendEnd,
    );
  }

  static PdfShading radialRgbStops(double x0, double y0, double r0, double x1,
      double y1, double r1, List<double> offsets, List<List<double>> colors,
      {bool extendStart = true, bool extendEnd = true}) {
    if (r0 < 0 || r1 < 0) throw ArgumentError('Radii cannot be negative.');
    return _gradientStops(
      type: 3,
      coords: [x0, y0, r0, x1, y1, r1],
      offsets: offsets,
      colors: colors,
      extendStart: extendStart,
      extendEnd: extendEnd,
    );
  }

  static PdfShading _gradientStops({
    required int type,
    required List<double> coords,
    required List<double> offsets,
    required List<List<double>> colors,
    required bool extendStart,
    required bool extendEnd,
  }) {
    if (colors.length < 2 || offsets.length != colors.length) {
      throw ArgumentError('A gradient needs matching offsets and 2+ colors.');
    }
    for (final color in colors) {
      _checkRgb(color);
    }
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] < 0 ||
          offsets[i] > 1 ||
          (i > 0 && offsets[i] < offsets[i - 1])) {
        throw ArgumentError('Offsets must be ordered values in 0..1.');
      }
    }
    if (colors.length == 2 && offsets.first == 0 && offsets.last == 1) {
      return _gradient(
          type: type,
          coords: coords,
          start: colors.first,
          end: colors.last,
          extendStart: extendStart,
          extendEnd: extendEnd);
    }
    final functions = <PdfObject>[];
    for (var i = 0; i + 1 < colors.length; i++) {
      functions.add(PdfDictionary()
        ..put(PdfName.intern('FunctionType'), PdfNumber(2))
        ..put(PdfName.intern('Domain'), PdfArray.fromDoubles([0, 1]))
        ..put(PdfName.intern('C0'), PdfArray.fromDoubles(colors[i]))
        ..put(PdfName.intern('C1'), PdfArray.fromDoubles(colors[i + 1]))
        ..put(PdfName.intern('N'), PdfNumber(1)));
    }
    final function = PdfDictionary()
      ..put(PdfName.intern('FunctionType'), PdfNumber(3))
      ..put(PdfName.intern('Domain'), PdfArray.fromDoubles([0, 1]))
      ..put(PdfName.intern('Functions'), PdfArray.fromList(functions))
      ..put(PdfName.intern('Bounds'),
          PdfArray.fromDoubles(offsets.sublist(1, offsets.length - 1)))
      ..put(
          PdfName.intern('Encode'),
          PdfArray.fromDoubles(List<double>.generate(
              functions.length * 2, (index) => index.isEven ? 0 : 1)));
    final dictionary = PdfDictionary()
      ..put(PdfName.shadingType, PdfNumber.fromInt(type))
      ..put(PdfName.colorSpace, PdfName.intern('DeviceRGB'))
      ..put(PdfName.coords, PdfArray.fromDoubles(coords))
      ..put(PdfName.function, function)
      ..put(PdfName.intern('Extend'),
          PdfArray.fromBooleans([extendStart, extendEnd]));
    return PdfShading(dictionary);
  }

  static PdfShading _gradient({
    required int type,
    required List<double> coords,
    required List<double> start,
    required List<double> end,
    required bool extendStart,
    required bool extendEnd,
  }) {
    final function = PdfDictionary()
      ..put(PdfName.intern('FunctionType'), PdfNumber(2))
      ..put(PdfName.intern('Domain'), PdfArray.fromDoubles([0, 1]))
      ..put(PdfName.intern('C0'), PdfArray.fromDoubles(start))
      ..put(PdfName.intern('C1'), PdfArray.fromDoubles(end))
      ..put(PdfName.intern('N'), PdfNumber(1));
    final dictionary = PdfDictionary()
      ..put(PdfName.shadingType, PdfNumber.fromInt(type))
      ..put(PdfName.colorSpace, PdfName.intern('DeviceRGB'))
      ..put(PdfName.coords, PdfArray.fromDoubles(coords))
      ..put(PdfName.function, function)
      ..put(PdfName.intern('Extend'),
          PdfArray.fromBooleans([extendStart, extendEnd]));
    return PdfShading(dictionary);
  }

  static void _checkRgb(List<double> color) {
    if (color.length != 3 || color.any((v) => v < 0 || v > 1)) {
      throw ArgumentError.value(color, 'color', 'Expected three values 0..1.');
    }
  }
}
