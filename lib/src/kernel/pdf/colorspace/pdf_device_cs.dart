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
}
