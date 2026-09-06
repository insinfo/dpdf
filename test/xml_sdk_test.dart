import 'package:test/test.dart';
import 'package:pdfcraft/src/kernel/xmp/xmp_meta.dart';
import 'package:pdfcraft/src/kernel/xmp/xmp_const.dart';

void main() {
  test('Unicode element and attribute names preserve spelling and namespaces',
      () {
    final doc = XmlDocument.parse(
        '<Preço xmlns:名="urn:unicode" 名:属性="ação"><名:商品>茶</名:商品>'
        '<𐀀item a\u0301="1"/><a·b/><a\u203fb/></Preço>');
    expect(doc.rootElement.name.local, 'Preço');
    expect(doc.rootElement.getAttribute('名:属性'), 'ação');
    expect(doc.findAllElements('商品', namespace: 'urn:unicode').single.innerText,
        '茶');
    expect(doc.findAllElements('𐀀item').single.getAttribute('a\u0301'), '1');
    final roundtrip = XmlDocument.parse(doc.toXmlString());
    expect(roundtrip.rootElement.name.local, 'Preço');
    expect(roundtrip.findAllElements('a·b').length, 1);
    expect(roundtrip.findAllElements('a\u203fb').length, 1);
    expect(roundtrip.findAllElements('商品', namespace: 'urn:unicode').length, 1);
  });
  test('Unicode name boundaries reject punctuation and invalid starts', () {
    for (final name in [
      '1bad',
      '.bad',
      '-bad',
      '\u0301bad',
      '\u00b7bad',
      '\u203fbad',
      'a\u00d7b',
      'a\u00f7b',
      'a\u037eb',
      'a\u200bb',
      'a\u206fb',
      'a\u2ff0b',
      'a\u3000b',
      'a\ue000b',
      'a\ufdd0b',
      'a\u{f0000}b',
      ':bad',
      'p:',
      'p:1bad',
      'p:a:b',
    ]) {
      expect(() => XmlDocument.parse('<$name xmlns:p="urn:p"/>'),
          throwsFormatException,
          reason: name);
      expect(() => XmlDocument.parse('<r xmlns:p="urn:p" $name="x"/>'),
          throwsFormatException,
          reason: 'attribute $name');
    }
    for (final code in [
      0xc0,
      0xd6,
      0xd8,
      0xf6,
      0xf8,
      0x2ff,
      0x370,
      0x37d,
      0x37f,
      0x1fff,
      0x200c,
      0x200d,
      0x2070,
      0x218f,
      0x2c00,
      0x2fef,
      0x3001,
      0xd7ff,
      0xf900,
      0xfdcf,
      0xfdf0,
      0xfffd,
      0x10000,
      0xeffff
    ]) {
      final name = '${String.fromCharCode(code)}item';
      expect(XmlDocument.parse('<$name/>').rootElement.name.local, name);
    }
  });
  test('isolated subtree retains inherited namespace declarations', () {
    final doc = XmlDocument.parse(
        '<x:root xmlns:x="urn:x" xmlns:a="urn:attrs"><x:data a:id="42"/></x:root>');
    final data = doc.findAllElements('data', namespace: 'urn:x').single;
    final packet = XmlDocument.parse(data.toXmlString());
    expect(packet.rootElement.name.namespaceUri, 'urn:x');
    expect(packet.rootElement.getAttribute('a:id'), '42');
  });
  test('resource limits reject excessive nesting', () {
    expect(
        () => XmlDocument.parse(
            '${List.filled(258, '<r>').join()}${List.filled(258, '</r>').join()}'),
        throwsFormatException);
  });
  test('namespace, mixed content, entities, CDATA, comments and PI roundtrip',
      () {
    final doc = XmlDocument.parse(
        '<?xml version="1.0"?><r xmlns="urn:r" xmlns:q="urn:q"><q:item a="&quot;&#10;&amp;">A&lt;&#x1F600;<![CDATA[<literal>]]><!-- comment --></q:item></r>');
    final item = doc.findAllElements('item', namespace: 'urn:q').single;
    expect(item.innerText, 'A<😀<literal>');
    expect(item.getAttribute('a'), '"\n&');
    final again = XmlDocument.parse(doc.toXmlString());
    expect(again.findAllElements('item', namespace: 'urn:q').single.innerText,
        item.innerText);
    expect(again.rootElement.name.namespaceUri, 'urn:r');
  });
  test('reject malformed XML and external entities', () {
    for (final input in [
      '<!DOCTYPE r SYSTEM "file:///secret"><r/>',
      '<r>&custom;</r>',
      '<r>&#0;</r>',
      '<r><a></r>',
      '<r a="1" a="2"/>',
      '<r/><s/>',
      '<q:r/>',
      '<r>]]></r>',
      '<r a="<"/>'
    ]) {
      expect(() => XmlDocument.parse(input), throwsFormatException,
          reason: input);
    }
  });
  test('metadata edit and serialization roundtrip', () {
    final xmp = CraftXMPMeta.create();
    xmp.setProperty(CraftXMPConst.NS_PDF, 'Producer', 'A & B <C>');
    final parsed = CraftXMPMetaFactory.parseFromBuffer(
        CraftXMPMetaFactory.serializeToBuffer(xmp));
    expect(parsed.getPropertyString(CraftXMPConst.NS_PDF, 'Producer'),
        'A & B <C>');
    parsed.setProperty(CraftXMPConst.NS_PDF, 'Producer', 'Updated');
    expect(
        parsed.getPropertyString(CraftXMPConst.NS_PDF, 'Producer'), 'Updated');
  });
  test('metadata supports alternate RDF prefixes', () {
    final xmp = CraftXMPMetaFactory.parseFromString(
        '<m xmlns:z="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><z:RDF><z:Description xmlns:p="http://ns.adobe.com/pdf/1.3/"><p:Producer>Original</p:Producer></z:Description></z:RDF></m>');
    expect(xmp.getPropertyString(CraftXMPConst.NS_PDF, 'Producer'), 'Original');
  });
}
