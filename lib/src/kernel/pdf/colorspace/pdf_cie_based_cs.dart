import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';

/// Abstract class for CIE-based color spaces.
abstract class CraftPdfCieBasedCs extends CraftPdfColorSpace {
  CraftPdfCieBasedCs(CraftPdfArray super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;
}

/// Represents a CalGray color space.
class PdfCieBasedCsCalGray extends CraftPdfCieBasedCs {
  PdfCieBasedCsCalGray(super.pdfObject);

  @override
  int getNumberOfComponents() => 1;
}

/// Represents a CalRGB color space.
class PdfCieBasedCsCalRgb extends CraftPdfCieBasedCs {
  PdfCieBasedCsCalRgb(super.pdfObject);

  @override
  int getNumberOfComponents() => 3;
}

/// Represents a Lab color space.
class PdfCieBasedCsLab extends CraftPdfCieBasedCs {
  PdfCieBasedCsLab(super.pdfObject);

  @override
  int getNumberOfComponents() => 3;
}

/// Represents an ICCBased color space.
class PdfCieBasedCsIccBased extends CraftPdfCieBasedCs {
  PdfCieBasedCsIccBased(super.pdfObject);

  @override
  int getNumberOfComponents() {
    // Should read from the stream dictionary (N entry).
    // TODO: Implement reading N from ICC profile stream
    return 0;
  }
}
