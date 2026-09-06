import 'package:test/test.dart';
import 'package:pdfcraft/src/kernel/xmp/xmp_meta.dart';
import 'package:pdfcraft/src/kernel/xmp/xmp_const.dart';
import 'package:pdfcraft/src/kernel/xmp/pdf_const.dart';

void main() {
  group('XMPMeta Tests', () {
    test('create creates a valid XMP structure', () {
      final xmp = CraftXMPMetaFactory.create();
      expect(xmp, isNotNull);
      final xmlStr = xmp.getDocument().toXmlString();
      expect(xmlStr, contains('x:xmpmeta'));
      expect(xmlStr, contains('rdf:RDF'));
    });

    test('setProperty adds property to rdf:Description', () {
      final xmp = CraftXMPMetaFactory.create();
      xmp.setProperty(
          CraftXMPConst.NS_DC, CraftPdfConst.Format, "application/pdf");

      final val =
          xmp.getPropertyString(CraftXMPConst.NS_DC, CraftPdfConst.Format);
      expect(val, equals("application/pdf"));

      final xmlStr = xmp.getDocument().toXmlString();
      expect(xmlStr, contains('dc:format>application/pdf</dc:format>'));
    });

    test('serialize and parse round trip', () {
      final xmp = CraftXMPMetaFactory.create();
      xmp.setProperty(
          CraftXMPConst.NS_DC, CraftPdfConst.Format, "application/pdf");

      final bytes = CraftXMPMetaFactory.serializeToBuffer(xmp);
      final xmp2 = CraftXMPMetaFactory.parseFromBuffer(bytes);

      final val =
          xmp2.getPropertyString(CraftXMPConst.NS_DC, CraftPdfConst.Format);
      expect(val, equals("application/pdf"));
    });
  });
}
