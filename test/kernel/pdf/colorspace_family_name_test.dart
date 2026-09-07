import 'package:dpdf/src/kernel/pdf/colorspace/pdf_cie_based_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_special_cs.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:test/test.dart';

void main() {
  test('PDF family names do not depend on implementation class names', () {
    expect(PdfSpecialCsPattern().getName(), CraftPdfName.pattern);
    expect(
        PdfCieBasedCsCalGray(CraftPdfArray.fromList([CraftPdfName.calGray]))
            .getName(),
        CraftPdfName.calGray);
    expect(
        PdfCieBasedCsLab(CraftPdfArray.fromList([CraftPdfName.lab])).getName(),
        CraftPdfName.lab);
    expect(() => PdfCieBasedCsLab(CraftPdfArray()).getName(), throwsStateError);
  });
}
