import 'package:itext/src/kernel/pdf/pdf_name.dart';
import 'package:itext/src/kernel/pdf/colorspace/pdf_color_space.dart';

abstract class PdfDeviceCs extends PdfColorSpace {
  PdfDeviceCs(PdfName pdfObject) : super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() {
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
}
