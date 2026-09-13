import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/conformance/pdf_a_verifier.dart';
import 'package:dpdf/src/conformance/pdf_conformance.dart';
import 'package:dpdf/src/conformance/pdf_conformance_report.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_output_intent.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

/// A 160 byte ICC profile: header only, which is all a conformance check reads.
Uint8List iccProfile({
  String colourSpace = 'RGB ',
  String deviceClass = 'prtr',
  int majorVersion = 2,
  bool signature = true,
  int? declaredSize,
}) {
  final data = Uint8List(160);
  final size = declaredSize ?? data.length;
  data[0] = (size >> 24) & 0xFF;
  data[1] = (size >> 16) & 0xFF;
  data[2] = (size >> 8) & 0xFF;
  data[3] = size & 0xFF;
  data[8] = majorVersion;
  data[9] = 0x20;
  data.setRange(12, 16, ascii.encode(deviceClass));
  data.setRange(16, 20, ascii.encode(colourSpace));
  if (signature) data.setRange(36, 40, ascii.encode('acsp'));
  return data;
}

String packet({
  String part = '2',
  String? conformance = 'B',
  String? title,
  String? creator,
  String? createDate,
  String? modifyDate,
  String namespaces = '',
  String properties = '',
  String schemas = '',
}) {
  final buffer = StringBuffer()
    ..writeln('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>')
    ..writeln('<x:xmpmeta xmlns:x="adobe:ns:meta/">')
    ..writeln('<rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">')
    ..writeln('<rdf:Description rdf:about="" '
        'xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" '
        'xmlns:pdf="http://ns.adobe.com/pdf/1.3/" '
        'xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
        'xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/" '
        'xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#" '
        '$namespaces'
        'xmlns:dc="http://purl.org/dc/elements/1.1/">')
    ..writeln('<pdfaid:part>$part</pdfaid:part>');
  if (conformance != null) {
    buffer.writeln('<pdfaid:conformance>$conformance</pdfaid:conformance>');
  }
  if (title != null) {
    buffer.writeln('<dc:title><rdf:Alt><rdf:li xml:lang="x-default">'
        '$title</rdf:li></rdf:Alt></dc:title>');
  }
  if (creator != null) {
    buffer.writeln('<dc:creator><rdf:Seq><rdf:li>$creator</rdf:li>'
        '</rdf:Seq></dc:creator>');
  }
  if (createDate != null) {
    buffer.writeln('<xmp:CreateDate>$createDate</xmp:CreateDate>');
  }
  if (modifyDate != null) {
    buffer.writeln('<xmp:ModifyDate>$modifyDate</xmp:ModifyDate>');
  }
  buffer
    ..writeln(properties)
    ..writeln(schemas)
    ..writeln('</rdf:Description>')
    ..writeln('</rdf:RDF>')
    ..writeln('</x:xmpmeta>')
    ..writeln('<?xpacket end="w"?>');
  return buffer.toString();
}

/// Builds a one page document with exactly the pieces a rule needs.
Future<Uint8List> buildDocument({
  String? xmp,
  bool outputIntent = true,
  Uint8List? profile,
  int? profileComponents,
  String? content,
  PdfDictionary? resources,
  Map<String, PdfObject> pageEntries = const {},
  Map<String, PdfObject> catalogEntries = const {},
  Map<String, String> info = const {},
  DateTime? fixedDate,
}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();

  if (content != null) {
    page.pdfRepresentation().put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(ascii.encode(content)), 0));
  }
  if (resources != null) {
    page.pdfRepresentation().put(PdfName.resources, resources);
  }
  pageEntries.forEach(
      (key, value) => page.pdfRepresentation().put(PdfName(key), value));

  if (outputIntent) {
    PdfStream? destination;
    if (profile != null) {
      destination = PdfStream.withBytes(profile, 0);
      if (profileComponents != null) {
        destination.put(PdfName('N'), PdfNumber(profileComponents.toDouble()));
      }
    }
    document.registerOutputProfile(PdfOutputIntent.create(
      'Custom condition',
      'Custom condition',
      'http://www.color.org',
      'Custom condition',
      destination,
    ));
  }

  final catalog = document.rootCatalog().pdfRepresentation();
  catalogEntries.forEach((key, value) => catalog.put(PdfName(key), value));

  final details = document.documentDetailsSync();
  if (fixedDate != null) {
    details
      ..setCreationDate(fixedDate)
      ..setModDate(fixedDate);
  }
  info.forEach((key, value) =>
      details.pdfRepresentation().put(PdfName(key), PdfString(value)));

  if (xmp != null) {
    await document.assignMetadataPayload(Uint8List.fromList(utf8.encode(xmp)));
  }
  await document.close();
  return output.takeBytes();
}

Future<Set<String>> codes(
  Uint8List bytes, {
  PdfAConformanceLevel level = PdfAConformanceLevel.a2b,
}) async {
  final report = await PdfAVerifier.verify(bytes, level: level);
  return report.violations.map((f) => f.code).toSet();
}

/// A simple font that breaks no rule on its own.
PdfDictionary soundFont() => PdfDictionary()
  ..put(PdfName.subtype, PdfName('Type1'))
  ..put(PdfName.baseFont, PdfName('AAAAAA+Sample'))
  ..put(PdfName.encoding, PdfName('WinAnsiEncoding'))
  ..put(PdfName('FirstChar'), PdfNumber(65))
  ..put(PdfName('LastChar'), PdfNumber(66))
  ..put(PdfName.widths, PdfArray.fromList([PdfNumber(500), PdfNumber(500)]))
  ..put(
      PdfName.fontDescriptor,
      PdfDictionary()
        ..put(PdfName('Flags'), PdfNumber(32))
        ..put(PdfName.fontFile3, PdfStream.withBytes(Uint8List(8), 0)));

PdfDictionary fontResources(PdfDictionary font, [String name = 'F1']) =>
    PdfDictionary()
      ..put(PdfName.font, PdfDictionary()..put(PdfName(name), font));

PdfStream toUnicodeMap(String body) => PdfStream.withBytes(
    Uint8List.fromList(ascii.encode('/CIDInit /ProcSet findresource begin '
        '1 begincodespacerange <00> <FF> endcodespacerange $body endcmap')),
    0);

void main() {
  group('output intent ICC profile', () {
    test('rejects a destination profile that is not an ICC profile', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(signature: false),
      ));

      expect(found, contains('output-profile-not-icc'));
    });

    test('accepts a well formed sRGB header', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        profileComponents: 3,
      ));

      expect(found, isNot(contains('output-profile-not-icc')));
      expect(found, isNot(contains('output-profile-invalid')));
      expect(found, isNot(contains('output-profile-component-count')));
      expect(found, isNot(contains('output-intent-without-profile')));
    });

    test('rejects a profile shorter than its own header says', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(declaredSize: 4096),
      ));

      expect(found, contains('output-profile-invalid'));
    });

    test('rejects a device class that is not an output condition', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(deviceClass: 'link'),
      ));

      expect(found, contains('output-profile-invalid'));
    });

    test('rejects an /N that disagrees with the ICC colour space', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(colourSpace: 'CMYK'),
        profileComponents: 3,
      ));

      expect(found, contains('output-profile-component-count'));
    });

    test('rejects an ICC version 4 profile in PDF/A-1', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '1', conformance: 'B'),
          profile: iccProfile(majorVersion: 4),
        ),
        level: PdfAConformanceLevel.a1b,
      );

      expect(found, contains('output-profile-version'));
    });
  });

  group('device colour against the output intent', () {
    test('rejects DeviceRGB under a grayscale output intent', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(colourSpace: 'GRAY'),
        content: '1 0 0 rg 0 0 10 10 re f',
      ));

      expect(found, contains('device-rgb-without-rgb-output-intent'));
    });

    test('accepts DeviceRGB under an RGB output intent', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: '1 0 0 rg 0 0 10 10 re f',
      ));

      expect(found, isNot(contains('device-rgb-without-rgb-output-intent')));
    });

    test('rejects DeviceCMYK under an RGB output intent', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: '0 0 0 1 k 0 0 10 10 re f',
      ));

      expect(found, contains('device-cmyk-without-cmyk-output-intent'));
    });

    test('follows a Separation alternate space to the device', () async {
      final separation = PdfArray.fromList([
        PdfName('Separation'),
        PdfName('Spot'),
        PdfName('DeviceCMYK'),
        PdfDictionary()..put(PdfName('FunctionType'), PdfNumber(2)),
      ]);
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: '/Spot cs 1 scn 0 0 10 10 re f',
        resources: PdfDictionary()
          ..put(PdfName.colorSpace,
              PdfDictionary()..put(PdfName('Spot'), separation)),
      ));

      expect(found, contains('device-cmyk-without-cmyk-output-intent'));
    });

    test(
        'accepts an image in DeviceRGB under an RGB intent and rejects it '
        'under a grayscale one', () async {
      PdfStream image() => PdfStream.withBytes(Uint8List(12), 0)
        ..put(PdfName.subtype, PdfName('Image'))
        ..put(PdfName('Width'), PdfNumber(2))
        ..put(PdfName('Height'), PdfNumber(2))
        ..put(PdfName('BitsPerComponent'), PdfNumber(8))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'));

      final rgb = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: PdfDictionary()
          ..put(PdfName.xObject, PdfDictionary()..put(PdfName('Im0'), image())),
      ));
      final gray = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(colourSpace: 'GRAY'),
        resources: PdfDictionary()
          ..put(PdfName.xObject, PdfDictionary()..put(PdfName('Im0'), image())),
      ));

      expect(rgb, isNot(contains('device-rgb-without-rgb-output-intent')));
      expect(gray, contains('device-rgb-without-rgb-output-intent'));
    });
  });

  group('content stream integrity', () {
    test('reports a graphics state that is never restored', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: 'q 0 0 10 10 re f',
      ));

      expect(found, contains('unbalanced-graphics-state'));
    });

    test('accepts a balanced content stream', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: 'q 0 0 10 10 re f Q',
      ));

      expect(found, isNot(contains('unbalanced-graphics-state')));
      expect(found, isNot(contains('unbalanced-text-object')));
      expect(found, isNot(contains('content-stream-unparsable')));
    });

    test('reports a text object that is never ended', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: 'BT /F1 12 Tf (A) Tj',
        resources: fontResources(soundFont()),
      ));

      expect(found, contains('unbalanced-text-object'));
    });

    test('reports a font the resource dictionary does not define', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: 'BT /F9 12 Tf (A) Tj ET',
        resources: fontResources(soundFont()),
      ));

      expect(found, contains('undefined-resource'));
    });

    test('accepts a font the resource dictionary does define', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: 'BT /F1 12 Tf (A) Tj ET',
        resources: fontResources(soundFont()),
      ));

      expect(found, isNot(contains('undefined-resource')));
    });

    test('reports a stream that is not content at all', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        content: List.filled(600, '1').join(' '),
      ));

      expect(found, contains('content-stream-unparsable'));
    });
  });

  group('fonts', () {
    test('reports a /Widths array that does not cover the code range',
        () async {
      final font = soundFont()..put(PdfName('LastChar'), PdfNumber(90));
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(font),
      ));

      expect(found, contains('font-widths-inconsistent'));
    });

    test('accepts widths that match the code range', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(soundFont()),
      ));

      expect(found, isNot(contains('font-widths-inconsistent')));
      expect(found, isNot(contains('font-without-widths')));
      expect(found, isNot(contains('font-without-char-range')));
      expect(found, isNot(contains('font-not-embedded')));
    });

    test('reports widths with no code range to attach them to', () async {
      final font = soundFont()..remove(PdfName('FirstChar'));
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(font),
      ));

      expect(found, contains('font-without-char-range'));
    });

    test('reports an /Encoding on a symbolic TrueType font', () async {
      final font = PdfDictionary()
        ..put(PdfName.subtype, PdfName('TrueType'))
        ..put(PdfName.baseFont, PdfName('Symbols'))
        ..put(PdfName.encoding, PdfName('WinAnsiEncoding'))
        ..put(PdfName('FirstChar'), PdfNumber(65))
        ..put(PdfName('LastChar'), PdfNumber(65))
        ..put(PdfName.widths, PdfArray.fromList([PdfNumber(500)]))
        ..put(
            PdfName.fontDescriptor,
            PdfDictionary()
              ..put(PdfName('Flags'), PdfNumber(4))
              ..put(PdfName.fontFile2, PdfStream.withBytes(Uint8List(8), 0)));
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(font),
      ));

      expect(found, contains('symbolic-truetype-with-encoding'));
    });

    test('accepts a symbolic TrueType font with no /Encoding', () async {
      final font = PdfDictionary()
        ..put(PdfName.subtype, PdfName('TrueType'))
        ..put(PdfName.baseFont, PdfName('Symbols'))
        ..put(PdfName('FirstChar'), PdfNumber(65))
        ..put(PdfName('LastChar'), PdfNumber(65))
        ..put(PdfName.widths, PdfArray.fromList([PdfNumber(500)]))
        ..put(
            PdfName.fontDescriptor,
            PdfDictionary()
              ..put(PdfName('Flags'), PdfNumber(4))
              ..put(PdfName.fontFile2, PdfStream.withBytes(Uint8List(8), 0)));
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(font),
      ));

      expect(found, isNot(contains('symbolic-truetype-with-encoding')));
    });
  });

  group('CIDFonts', () {
    PdfDictionary compositeFont({
      bool cidSet = true,
      PdfObject? cidToGidMap,
      String descendantSubtype = 'CIDFontType2',
    }) {
      final descriptor = PdfDictionary()
        ..put(PdfName('Flags'), PdfNumber(4))
        ..put(PdfName.fontFile2, PdfStream.withBytes(Uint8List(8), 0));
      if (cidSet) {
        descriptor.put(PdfName('CIDSet'), PdfStream.withBytes(Uint8List(4), 0));
      }
      final descendant = PdfDictionary()
        ..put(PdfName.subtype, PdfName(descendantSubtype))
        ..put(PdfName.baseFont, PdfName('AAAAAA+Composite'))
        ..put(PdfName.fontDescriptor, descriptor);
      if (cidToGidMap != null) {
        descendant.put(PdfName('CIDToGIDMap'), cidToGidMap);
      }
      return PdfDictionary()
        ..put(PdfName.subtype, PdfName('Type0'))
        ..put(PdfName.baseFont, PdfName('AAAAAA+Composite'))
        ..put(PdfName.encoding, PdfName('Identity-H'))
        ..put(PdfName('DescendantFonts'), PdfArray.fromList([descendant]))
        ..put(PdfName.toUnicode,
            toUnicodeMap('1 beginbfchar <0041> <0041> endbfchar'));
    }

    test('reports an embedded CIDFont whose descriptor has no /CIDSet',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(
            compositeFont(cidSet: false, cidToGidMap: PdfName('Identity'))),
      ));

      expect(found, contains('cidfont-without-cidset'));
    });

    test('accepts an embedded CIDFont that declares its /CIDSet', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources:
            fontResources(compositeFont(cidToGidMap: PdfName('Identity'))),
      ));

      expect(found, isNot(contains('cidfont-without-cidset')));
      expect(found, isNot(contains('cidfont-bad-cidtogidmap')));
    });

    test('reports a /CIDToGIDMap that is neither Identity nor a stream',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: fontResources(compositeFont(cidToGidMap: PdfName('Custom'))),
      ));

      expect(found, contains('cidfont-bad-cidtogidmap'));
    });

    test('requires /CIDToGIDMap to be present in PDF/A-1', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '1', conformance: 'B'),
          profile: iccProfile(),
          resources: fontResources(compositeFont()),
        ),
        level: PdfAConformanceLevel.a1b,
      );

      expect(found, contains('cidfont-without-cidtogidmap'));
    });
  });

  group('/ToUnicode coverage', () {
    PdfDictionary mappedFont(String body) => soundFont()
      ..put(PdfName.encoding, PdfName('WinAnsiEncoding'))
      ..put(PdfName.toUnicode, toUnicodeMap(body));

    test('reports a code the map does not cover', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '2', conformance: 'U'),
          profile: iccProfile(),
          content: 'BT /F1 12 Tf <41425A> Tj ET',
          resources:
              fontResources(mappedFont('1 beginbfchar <41> <0041> endbfchar')),
        ),
        level: PdfAConformanceLevel.a2u,
      );

      expect(found, contains('tounicode-incomplete'));
    });

    test('accepts a map that covers every code drawn', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '2', conformance: 'U'),
          profile: iccProfile(),
          content: 'BT /F1 12 Tf <41> Tj ET',
          resources:
              fontResources(mappedFont('1 beginbfchar <41> <0041> endbfchar')),
        ),
        level: PdfAConformanceLevel.a2u,
      );

      expect(found, isNot(contains('tounicode-incomplete')));
      expect(found, isNot(contains('font-without-tounicode')));
    });

    test('reports a simple font with no map and no standard encoding',
        () async {
      final font = soundFont()..remove(PdfName.encoding);
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '2', conformance: 'U'),
          profile: iccProfile(),
          resources: fontResources(font),
        ),
        level: PdfAConformanceLevel.a2u,
      );

      expect(found, contains('font-without-tounicode'));
    });

    test('accepts a simple font that uses a named standard encoding', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '2', conformance: 'U'),
          profile: iccProfile(),
          resources: fontResources(soundFont()),
        ),
        level: PdfAConformanceLevel.a2u,
      );

      expect(found, isNot(contains('font-without-tounicode')));
    });
  });

  group('forbidden features', () {
    test('reports a named action that is not page navigation', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        catalogEntries: {
          'OpenAction': PdfDictionary()
            ..put(PdfName.s, PdfName('Named'))
            ..put(PdfName.n, PdfName('Print')),
        },
      ));

      expect(found, contains('forbidden-named-action'));
    });

    test('accepts a named action that only turns the page', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        catalogEntries: {
          'OpenAction': PdfDictionary()
            ..put(PdfName.s, PdfName('Named'))
            ..put(PdfName.n, PdfName('NextPage')),
        },
      ));

      expect(found, isNot(contains('forbidden-named-action')));
    });

    test('reports an XFA form', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        catalogEntries: {
          'AcroForm': PdfDictionary()
            ..put(PdfName('XFA'), PdfArray.fromList([])),
        },
      ));

      expect(found, contains('acroform-xfa'));
    });

    test('reports a form that asks the reader to build its appearances',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        catalogEntries: {
          'AcroForm': PdfDictionary()
            ..put(PdfName('NeedAppearances'), PdfBoolean(true)),
        },
      ));

      expect(found, contains('acroform-needappearances'));
    });

    test('accepts a form with stored appearances', () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        catalogEntries: {
          'AcroForm': PdfDictionary()
            ..put(PdfName('Fields'), PdfArray.fromList([])),
        },
      ));

      expect(found, isNot(contains('acroform-xfa')));
      expect(found, isNot(contains('acroform-needappearances')));
    });

    test('reports JPXDecode in PDF/A-1 and accepts it in PDF/A-2', () async {
      PdfStream image() => PdfStream.withBytes(Uint8List(12), 0)
        ..put(PdfName.subtype, PdfName('Image'))
        ..put(PdfName('Width'), PdfNumber(2))
        ..put(PdfName('Height'), PdfNumber(2))
        ..put(PdfName('BitsPerComponent'), PdfNumber(8))
        ..put(PdfName.colorSpace, PdfName('DeviceGray'))
        ..put(PdfName.filter, PdfName('JPXDecode'));

      final one = await codes(
        await buildDocument(
          xmp: packet(part: '1', conformance: 'B'),
          profile: iccProfile(),
          resources: PdfDictionary()
            ..put(
                PdfName.xObject, PdfDictionary()..put(PdfName('Im0'), image())),
        ),
        level: PdfAConformanceLevel.a1b,
      );
      final two = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        resources: PdfDictionary()
          ..put(PdfName.xObject, PdfDictionary()..put(PdfName('Im0'), image())),
      ));

      expect(one, contains('jpxdecode-filter'));
      expect(two, isNot(contains('jpxdecode-filter')));
    });

    test('reports an annotation with additional actions', () async {
      final annotation = PdfDictionary()
        ..put(PdfName.subtype, PdfName('Widget'))
        ..put(PdfName('F'), PdfNumber(4))
        ..put(PdfName('AA'), PdfDictionary())
        ..put(PdfName('AP'), PdfDictionary()..put(PdfName.n, PdfDictionary()));
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        pageEntries: {
          'Annots': PdfArray.fromList([annotation])
        },
      ));

      expect(found, contains('annotation-additional-actions'));
    });
  });

  group('embedded files', () {
    PdfDictionary tree(PdfDictionary specification) => PdfDictionary()
      ..put(
          PdfName('EmbeddedFiles'),
          PdfDictionary()
            ..put(PdfName('Names'),
                PdfArray.fromList([PdfString('data.csv'), specification])));

    test(
        'reports an attachment that does not say how it relates to the '
        'document', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '3', conformance: 'B'),
          profile: iccProfile(),
          catalogEntries: {
            'Names': tree(PdfDictionary()
              ..put(PdfName.type, PdfName('Filespec'))
              ..put(PdfName('F'), PdfString('data.csv'))),
          },
        ),
        level: PdfAConformanceLevel.a3b,
      );

      expect(found, contains('embedded-file-without-relationship'));
    });

    test('accepts an attachment that declares /AFRelationship', () async {
      final found = await codes(
        await buildDocument(
          xmp: packet(part: '3', conformance: 'B'),
          profile: iccProfile(),
          catalogEntries: {
            'Names': tree(PdfDictionary()
              ..put(PdfName.type, PdfName('Filespec'))
              ..put(PdfName('F'), PdfString('data.csv'))
              ..put(PdfName('AFRelationship'), PdfName('Data'))),
          },
        ),
        level: PdfAConformanceLevel.a3b,
      );

      expect(found, isNot(contains('embedded-file-without-relationship')));
    });
  });

  group('XMP', () {
    final date = DateTime(2024, 1, 2, 3, 4, 5);

    test(
        'reports a title the XMP packet and the information dictionary '
        'disagree about', () async {
      final found = await codes(await buildDocument(
        xmp: packet(title: 'The XMP title'),
        profile: iccProfile(),
        info: {'Title': 'The Info title'},
        fixedDate: date,
      ));

      expect(found, contains('xmp-info-mismatch'));
    });

    test('reports an information entry the XMP packet does not carry',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(),
        profile: iccProfile(),
        info: {'Title': 'A title'},
        fixedDate: date,
      ));

      expect(found, contains('xmp-info-missing-property'));
    });

    test('accepts a packet that agrees with the information dictionary',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(
          title: 'A title',
          creator: 'A writer',
          createDate: '2024-01-02T03:04:05',
          modifyDate: '2024-01-02T03:04:05',
        ),
        profile: iccProfile(),
        info: {'Title': 'A title', 'Author': 'A writer'},
        fixedDate: date,
      ));

      expect(found, isNot(contains('xmp-info-mismatch')));
      expect(found, isNot(contains('xmp-info-missing-property')));
    });

    test('reports a pdfaid pair that names no profile', () async {
      final found = await codes(await buildDocument(
        xmp: packet(part: '2', conformance: null),
        profile: iccProfile(),
      ));

      expect(found, contains('unknown-pdfaid'));
    });

    test('reports a property in a namespace no extension schema describes',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(
          namespaces: 'xmlns:acme="http://acme.example/ns/1.0/" ',
          properties: '<acme:invoice>42</acme:invoice>',
        ),
        profile: iccProfile(),
      ));

      expect(found, contains('xmp-extension-schema-missing'));
    });

    test('accepts a property whose namespace an extension schema declares',
        () async {
      final found = await codes(await buildDocument(
        xmp: packet(
          namespaces: 'xmlns:acme="http://acme.example/ns/1.0/" ',
          properties: '<acme:invoice>42</acme:invoice>',
          schemas: '<pdfaExtension:schemas><rdf:Bag><rdf:li>'
              '<pdfaSchema:namespaceURI>http://acme.example/ns/1.0/'
              '</pdfaSchema:namespaceURI>'
              '</rdf:li></rdf:Bag></pdfaExtension:schemas>',
        ),
        profile: iccProfile(),
      ));

      expect(found, isNot(contains('xmp-extension-schema-missing')));
    });

    test('accepts a packet that uses only predefined schemas', () async {
      final found = await codes(await buildDocument(
        xmp: packet(title: 'Plain'),
        profile: iccProfile(),
      ));

      expect(found, isNot(contains('xmp-extension-schema-missing')));
    });
  });

  group('unverified rules', () {
    test('shrinks to what genuinely needs a renderer or a font program',
        () async {
      final basic = await PdfAVerifier.verify(
        await buildDocument(xmp: packet(), profile: iccProfile()),
        level: PdfAConformanceLevel.a2b,
      );
      final accessible = await PdfAVerifier.verify(
        await buildDocument(
            xmp: packet(conformance: 'A'), profile: iccProfile()),
        level: PdfAConformanceLevel.a2a,
      );

      expect(basic.unverifiedRules, hasLength(1));
      expect(basic.unverifiedRules.single, contains('Glyph presence'));
      expect(accessible.unverifiedRules, hasLength(2));
      expect(accessible.unverifiedRules.join(' '), contains('reading order'));
    });

    test('reports what it did check even when nothing is wrong', () async {
      final report = await PdfAVerifier.verify(
        await buildDocument(
            xmp: packet(), profile: iccProfile(), profileComponents: 3),
        level: PdfAConformanceLevel.a2b,
      );

      expect(report, isA<PdfConformanceReport>());
      expect(report.profile, equals('PDF/A-2b'));
      expect(report.claimedProfile, equals('PDF/A-2b'));
    });
  });
}
