import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';

/// Abstract class for special color spaces (Pattern, Indexed, Separation, DeviceN).
abstract class CraftPdfSpecialCs extends CraftPdfColorSpace {
  CraftPdfSpecialCs(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;
}

/// Represents a Pattern color space.
class PdfSpecialCsPattern extends CraftPdfSpecialCs {
  /// Creates a new [PdfSpecialCsPattern] object.
  PdfSpecialCsPattern() : super(CraftPdfName.pattern);

  // TODO: Support /Pattern CS with underlying CS (Array form)

  @override
  int getNumberOfComponents() {
    // This is hard to determine without more context (tiling vs shading, uncolored vs colored)
    // For specific instances we might know.
    return -1;
  }
}
