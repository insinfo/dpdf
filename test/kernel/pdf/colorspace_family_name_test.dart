import 'package:dpdf/src/kernel/pdf/colorspace/pdf_cie_based_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_special_cs.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:test/test.dart';

void main() {
  test('PDF family names do not depend on implementation class names', () {
    expect(PdfSpecialCsPattern().getName(), PdfName.pattern);
    expect(PdfCieBasedCsCalGray(PdfArray.fromList([PdfName.calGray])).getName(),
        PdfName.calGray);
    expect(PdfCieBasedCsLab(PdfArray.fromList([PdfName.lab])).getName(),
        PdfName.lab);
    expect(() => PdfCieBasedCsLab(PdfArray()).getName(), throwsStateError);
  });
}
