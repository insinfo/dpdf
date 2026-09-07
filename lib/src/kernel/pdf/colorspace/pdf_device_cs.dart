import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';

abstract class PdfDeviceCs extends PdfColorSpace {
  PdfDeviceCs(PdfName super.pdfObject);

  @override
  bool requiresIndirectStorage() {
    return false;
  }
}

class PdfDeviceCsGray extends PdfDeviceCs {
  PdfDeviceCsGray() : super(PdfName.deviceGray);

  @override
  int getNumberOfComponents() {
    return 1;
  }

  @override
  PdfName getName() {
    return PdfName.deviceGray;
  }

  @override
  List<double> toRgb(List<double> components) {
    return grayToRgb(PdfColorSpace.componentAt(components, 0));
  }

  /// Grey is the same value on all three channels.
  static List<double> grayToRgb(double gray) {
    final g = PdfColorSpace.clampUnit(gray);
    return <double>[g, g, g];
  }
}

class PdfDeviceCsRgb extends PdfDeviceCs {
  PdfDeviceCsRgb() : super(PdfName.deviceRgb);

  @override
  int getNumberOfComponents() {
    return 3;
  }

  @override
  PdfName getName() {
    return PdfName.deviceRgb;
  }

  @override
  List<double> toRgb(List<double> components) {
    return <double>[
      PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 0)),
      PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 1)),
      PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 2)),
    ];
  }
}

class PdfDeviceCsCmyk extends PdfDeviceCs {
  PdfDeviceCsCmyk() : super(PdfName.deviceCmyk);

  @override
  int getNumberOfComponents() {
    return 4;
  }

  @override
  PdfName getName() {
    return PdfName.deviceCmyk;
  }

  @override
  List<double> toRgb(List<double> components) {
    return cmykToRgb(
        PdfColorSpace.componentAt(components, 0),
        PdfColorSpace.componentAt(components, 1),
        PdfColorSpace.componentAt(components, 2),
        PdfColorSpace.componentAt(components, 3));
  }

  /// The naive `(1 - c) * (1 - k)` conversion.
  ///
  /// This is not a colour-managed conversion: it ignores ink behaviour, dot
  /// gain and the output profile, so saturated inks come out brighter than a
  /// press would print them. It is the single formula this library uses for
  /// CMYK, shared with [DeviceCmyk.makeLighter] and friends, so that a
  /// rasterized page and a converted colour object never disagree
  /// (DeviceCmyk delegates here).
  static List<double> cmykToRgb(double c, double m, double y, double k) {
    return <double>[
      PdfColorSpace.clampUnit((1.0 - c) * (1.0 - k)),
      PdfColorSpace.clampUnit((1.0 - m) * (1.0 - k)),
      PdfColorSpace.clampUnit((1.0 - y) * (1.0 - k)),
    ];
  }
}
