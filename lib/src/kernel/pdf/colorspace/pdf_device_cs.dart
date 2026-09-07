import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';

abstract class CraftPdfDeviceCs extends CraftPdfColorSpace {
  CraftPdfDeviceCs(CraftPdfName super.pdfObject);

  @override
  bool requiresIndirectStorage() {
    return false;
  }
}

class PdfDeviceCsGray extends CraftPdfDeviceCs {
  PdfDeviceCsGray() : super(CraftPdfName.deviceGray);

  @override
  int getNumberOfComponents() {
    return 1;
  }

  @override
  CraftPdfName getName() {
    return CraftPdfName.deviceGray;
  }

  @override
  List<double> toRgb(List<double> components) {
    return grayToRgb(CraftPdfColorSpace.componentAt(components, 0));
  }

  /// Grey is the same value on all three channels.
  static List<double> grayToRgb(double gray) {
    final g = CraftPdfColorSpace.clampUnit(gray);
    return <double>[g, g, g];
  }
}

class PdfDeviceCsRgb extends CraftPdfDeviceCs {
  PdfDeviceCsRgb() : super(CraftPdfName.deviceRgb);

  @override
  int getNumberOfComponents() {
    return 3;
  }

  @override
  CraftPdfName getName() {
    return CraftPdfName.deviceRgb;
  }

  @override
  List<double> toRgb(List<double> components) {
    return <double>[
      CraftPdfColorSpace.clampUnit(
          CraftPdfColorSpace.componentAt(components, 0)),
      CraftPdfColorSpace.clampUnit(
          CraftPdfColorSpace.componentAt(components, 1)),
      CraftPdfColorSpace.clampUnit(
          CraftPdfColorSpace.componentAt(components, 2)),
    ];
  }
}

class PdfDeviceCsCmyk extends CraftPdfDeviceCs {
  PdfDeviceCsCmyk() : super(CraftPdfName.deviceCmyk);

  @override
  int getNumberOfComponents() {
    return 4;
  }

  @override
  CraftPdfName getName() {
    return CraftPdfName.deviceCmyk;
  }

  @override
  List<double> toRgb(List<double> components) {
    return cmykToRgb(
        CraftPdfColorSpace.componentAt(components, 0),
        CraftPdfColorSpace.componentAt(components, 1),
        CraftPdfColorSpace.componentAt(components, 2),
        CraftPdfColorSpace.componentAt(components, 3));
  }

  /// The naive `(1 - c) * (1 - k)` conversion.
  ///
  /// This is not a colour-managed conversion: it ignores ink behaviour, dot
  /// gain and the output profile, so saturated inks come out brighter than a
  /// press would print them. It is the single formula this library uses for
  /// CMYK, shared with [CraftDeviceCmyk.makeLighter] and friends, so that a
  /// rasterized page and a converted colour object never disagree
  /// (CraftDeviceCmyk delegates here).
  static List<double> cmykToRgb(double c, double m, double y, double k) {
    return <double>[
      CraftPdfColorSpace.clampUnit((1.0 - c) * (1.0 - k)),
      CraftPdfColorSpace.clampUnit((1.0 - m) * (1.0 - k)),
      CraftPdfColorSpace.clampUnit((1.0 - y) * (1.0 - k)),
    ];
  }
}
