import 'pdf_name.dart';

/// This class represents all official PDF versions.
class CraftPdfVersion implements Comparable<CraftPdfVersion> {
  static final List<CraftPdfVersion> _values = [];

  static final CraftPdfVersion PDF_1_0 = _createPdfVersion(1, 0);
  static final CraftPdfVersion PDF_1_1 = _createPdfVersion(1, 1);
  static final CraftPdfVersion PDF_1_2 = _createPdfVersion(1, 2);
  static final CraftPdfVersion PDF_1_3 = _createPdfVersion(1, 3);
  static final CraftPdfVersion PDF_1_4 = _createPdfVersion(1, 4);
  static final CraftPdfVersion PDF_1_5 = _createPdfVersion(1, 5);
  static final CraftPdfVersion PDF_1_6 = _createPdfVersion(1, 6);
  static final CraftPdfVersion PDF_1_7 = _createPdfVersion(1, 7);
  static final CraftPdfVersion PDF_2_0 = _createPdfVersion(2, 0);

  final int _major;
  final int _minor;

  /// Creates a PdfVersion class.
  CraftPdfVersion(this._major, this._minor);

  @override
  String toString() {
    return 'PDF-$_major.$_minor';
  }

  /// Gets the PDF version in "X.Y" format.
  CraftPdfName toPdfName() {
    return CraftPdfName('$_major.$_minor');
  }

  /// Parses a version string when the requested version
  /// can be found.
  static CraftPdfVersion fromString(String value) {
    if (value == '1.7' || value == 'PDF-1.7') return PDF_1_7;
    if (value == '1.6' || value == 'PDF-1.6') return PDF_1_6;
    if (value == '1.5' || value == 'PDF-1.5') return PDF_1_5;
    if (value == '1.4' || value == 'PDF-1.4') return PDF_1_4;
    if (value == '1.3' || value == 'PDF-1.3') return PDF_1_3;
    if (value == '1.2' || value == 'PDF-1.2') return PDF_1_2;
    if (value == '1.1' || value == 'PDF-1.1') return PDF_1_1;
    if (value == '1.0' || value == 'PDF-1.0') return PDF_1_0;
    if (value == '2.0' || value == 'PDF-2.0') return PDF_2_0;

    throw ArgumentError('The provided pdf version was not found: $value');
  }

  /// Creates a PdfVersion class from a [PdfName] object if the specified version
  /// can be found.
  static CraftPdfVersion fromPdfName(CraftPdfName name) {
    for (final version in _values) {
      if (version.toPdfName() == name) {
        return version;
      }
    }
    throw ArgumentError('The provided pdf version was not found.');
  }

  @override
  int compareTo(CraftPdfVersion other) {
    if (_major != other._major) {
      return _major.compareTo(other._major);
    }
    return _minor.compareTo(other._minor);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CraftPdfVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode => _major.hashCode ^ _minor.hashCode;

  static CraftPdfVersion _createPdfVersion(int major, int minor) {
    final pdfVersion = CraftPdfVersion(major, minor);
    _values.add(pdfVersion);
    return pdfVersion;
  }
}
