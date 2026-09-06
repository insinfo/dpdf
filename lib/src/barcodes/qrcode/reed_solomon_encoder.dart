import 'gf_256.dart';
import 'gf_256_poly.dart';

/// Implements Reed-Solomon encoding, as the name implies.
class ReedSolomonEncoder {
  final GF256 _field;
  late List<GF256Poly> _cachedGenerators;

  /// Creates a SolomonEncoder object based on a GF256 object.
  ReedSolomonEncoder(this._field) {
    if (GF256.QR_CODE_FIELD != _field) {
      throw UnsupportedError("Only QR Code is supported at this time");
    }
    _cachedGenerators = [];
    _cachedGenerators.add(GF256Poly(_field, [1]));
  }

  GF256Poly _buildGenerator(int degree) {
    if (degree >= _cachedGenerators.length) {
      GF256Poly lastGenerator = _cachedGenerators[_cachedGenerators.length - 1];
      for (int d = _cachedGenerators.length; d <= degree; d++) {
        GF256Poly nextGenerator =
            lastGenerator.multiply(GF256Poly(_field, [1, _field.exp(d - 1)]));
        _cachedGenerators.add(nextGenerator);
        lastGenerator = nextGenerator;
      }
    }
    return _cachedGenerators[degree];
  }

  /// Encodes the provided data.
  ///
  /// [toEncode] - data to encode (modified in place)
  /// [ecBytes] - error correction bytes
  void encode(List<int> toEncode, int ecBytes) {
    if (ecBytes == 0) {
      throw ArgumentError("No error correction bytes");
    }
    int dataBytes = toEncode.length - ecBytes;
    if (dataBytes <= 0) {
      throw ArgumentError("No data bytes provided");
    }
    GF256Poly generator = _buildGenerator(ecBytes);
    List<int> infoCoefficients = List<int>.filled(dataBytes, 0);
    List.copyRange(infoCoefficients, 0, toEncode, 0, dataBytes);
    GF256Poly info = GF256Poly(_field, infoCoefficients);
    info = info.multiplyByMonomial(ecBytes, 1);
    GF256Poly remainder = info.divide(generator)[1];
    List<int> coefficients = remainder.getCoefficients();
    int numZeroCoefficients = ecBytes - coefficients.length;
    for (int i = 0; i < numZeroCoefficients; i++) {
      toEncode[dataBytes + i] = 0;
    }
    List.copyRange(toEncode, dataBytes + numZeroCoefficients, coefficients);
  }
}
