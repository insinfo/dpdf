import 'pdf_name.dart';

/// This class represents all official PDF versions.
class PdfVersion implements Comparable<PdfVersion> {
  static final List<PdfVersion> _values = [];

  static final PdfVersion PDF_1_0 = _createPdfVersion(1, 0);
  static final PdfVersion PDF_1_1 = _createPdfVersion(1, 1);
  static final PdfVersion PDF_1_2 = _createPdfVersion(1, 2);
  static final PdfVersion PDF_1_3 = _createPdfVersion(1, 3);
  static final PdfVersion PDF_1_4 = _createPdfVersion(1, 4);
  static final PdfVersion PDF_1_5 = _createPdfVersion(1, 5);
  static final PdfVersion PDF_1_6 = _createPdfVersion(1, 6);
  static final PdfVersion PDF_1_7 = _createPdfVersion(1, 7);
  static final PdfVersion PDF_2_0 = _createPdfVersion(2, 0);

  final int _major;
  final int _minor;

  /// Creates a PdfVersion class.
  PdfVersion(this._major, this._minor);

  @override
  String toString() {
    return 'PDF-$_major.$_minor';
  }

  /// Gets the PDF version in "X.Y" format.
  PdfName toPdfName() {
    return PdfName('$_major.$_minor');
  }

  /// Creates a PdfVersion class from a String object if the specified version
  /// can be found.
  static PdfVersion fromString(String value) {
    for (final version in _values) {
      if (version.toString() == value ||
          version.toPdfName().getValue() == value) {
        return version;
      }
    }
    throw ArgumentError('The provided pdf version was not found.');
  }

  /// Creates a PdfVersion class from a [PdfName] object if the specified version
  /// can be found.
  static PdfVersion fromPdfName(PdfName name) {
    for (final version in _values) {
      if (version.toPdfName() == name) {
        return version;
      }
    }
    throw ArgumentError('The provided pdf version was not found.');
  }

  @override
  int compareTo(PdfVersion other) {
    if (_major != other._major) {
      return _major.compareTo(other._major);
    }
    return _minor.compareTo(other._minor);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode => _major.hashCode ^ _minor.hashCode;

  static PdfVersion _createPdfVersion(int major, int minor) {
    final pdfVersion = PdfVersion(major, minor);
    _values.add(pdfVersion);
    return pdfVersion;
  }
}
