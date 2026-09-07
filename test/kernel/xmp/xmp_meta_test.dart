import 'package:test/test.dart';
import 'package:dpdf/src/kernel/xmp/xmp_meta.dart';
import 'package:dpdf/src/kernel/xmp/xmp_const.dart';
import 'package:dpdf/src/kernel/xmp/pdf_const.dart';

void main() {
  group('XMPMeta Tests', () {
    test('create creates a valid XMP structure', () {
      final xmp = XMPMetaFactory.create();
      expect(xmp, isNotNull);
      final xmlStr = xmp.getDocument().toXmlString();
      expect(xmlStr, contains('x:xmpmeta'));
      expect(xmlStr, contains('rdf:RDF'));
    });

    test('setProperty adds property to rdf:Description', () {
      final xmp = XMPMetaFactory.create();
      xmp.setProperty(XMPConst.NS_DC, PdfConst.Format, "application/pdf");

      final val = xmp.getPropertyString(XMPConst.NS_DC, PdfConst.Format);
      expect(val, equals("application/pdf"));

      final xmlStr = xmp.getDocument().toXmlString();
      expect(xmlStr, contains('dc:format>application/pdf</dc:format>'));
    });

    test('serialize and parse round trip', () {
      final xmp = XMPMetaFactory.create();
      xmp.setProperty(XMPConst.NS_DC, PdfConst.Format, "application/pdf");

      final bytes = XMPMetaFactory.serializeToBuffer(xmp);
      final xmp2 = XMPMetaFactory.parseFromBuffer(bytes);

      final val = xmp2.getPropertyString(XMPConst.NS_DC, PdfConst.Format);
      expect(val, equals("application/pdf"));
    });
  });
}
