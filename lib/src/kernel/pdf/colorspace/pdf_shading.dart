import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';

class PdfShading extends PdfObjectWrapper<PdfDictionary> {
  PdfShading(PdfDictionary pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;

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
