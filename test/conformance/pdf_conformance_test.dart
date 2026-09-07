import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

Future<Uint8List> _plainDocument() async {
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  await document.appendBlankPage();
  await document.close();
  return output.takeBytes();
}

/// A document that carries an XMP packet declaring [part]/[conformance] and,
/// when asked, the sRGB output intent a PDF/A file needs.
Future<Uint8List> _declaringDocument({
  required String part,
  String? conformance,
  bool outputIntent = true,
  String? uaPart,
  String? title,
}) async {
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  await document.appendBlankPage();
  if (outputIntent) {
    await document.configureArchivalProfile();
  }
  await document.assignMetadataPayload(Uint8List.fromList(_packet(
    part: part,
    conformance: conformance,
    uaPart: uaPart,
    title: title,
  ).codeUnits));
  await document.close();
  return output.takeBytes();
}

String _packet({
  required String part,
  String? conformance,
  String? uaPart,
  String? title,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>')
    ..writeln('<x:xmpmeta xmlns:x="adobe:ns:meta/">')
    ..writeln('<rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">')
    ..writeln('<rdf:Description rdf:about="" '
        'xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" '
        'xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">')
    ..writeln('<pdfaid:part>$part</pdfaid:part>');
  if (conformance != null) {
    buffer.writeln('<pdfaid:conformance>$conformance</pdfaid:conformance>');
  }
  if (uaPart != null) {
    buffer.writeln('<pdfuaid:part>$uaPart</pdfuaid:part>');
  }
  if (title != null) {
    buffer.writeln('<dc:title><rdf:Alt><rdf:li xml:lang="x-default">'
        '$title</rdf:li></rdf:Alt></dc:title>');
  }
  buffer
    ..writeln('</rdf:Description>')
    ..writeln('</rdf:RDF>')
    ..writeln('</x:xmpmeta>')
    ..writeln('<?xpacket end="w"?>');
  return buffer.toString();
}

void main() {
  group('PdfAConformanceLevel', () {
    test('maps a pdfaid pair back to a profile', () {
      expect(PdfAConformanceLevel.fromIdentifier('2', 'B'),
          equals(PdfAConformanceLevel.a2b));
      expect(PdfAConformanceLevel.fromIdentifier('1', 'a'),
          equals(PdfAConformanceLevel.a1a));
      expect(PdfAConformanceLevel.fromIdentifier('9', 'B'), isNull);
    });

    test('exposes the constraints each part imposes', () {
      expect(PdfAConformanceLevel.a1b.maximumPdfVersion, equals('1.4'));
      expect(PdfAConformanceLevel.a2b.maximumPdfVersion, equals('1.7'));
      expect(PdfAConformanceLevel.a4.maximumPdfVersion, equals('2.0'));

      expect(PdfAConformanceLevel.a1b.forbidsTransparency, isTrue);
      expect(PdfAConformanceLevel.a2b.forbidsTransparency, isFalse);

      expect(PdfAConformanceLevel.a1b.allowsEmbeddedFiles, isFalse);
      expect(PdfAConformanceLevel.a3b.allowsEmbeddedFiles, isTrue);

      expect(PdfAConformanceLevel.a2a.requiresTagging, isTrue);
      expect(PdfAConformanceLevel.a2u.requiresTagging, isFalse);
      expect(PdfAConformanceLevel.a2u.requiresUnicodeMapping, isTrue);

      expect(PdfAConformanceLevel.a2b.label, equals('PDF/A-2b'));
    });
  });

  group('XmpIdentification', () {
    test('reads identifiers written as elements', () {
      final claim = XmpIdentification.parsePacket(
          _packet(part: '3', conformance: 'B', uaPart: '1', title: 'Report'));

      expect(claim.pdfALevel, equals(PdfAConformanceLevel.a3b));
      expect(claim.pdfUALevel, equals(PdfUAConformanceLevel.ua1));
      expect(claim.title, equals('Report'));
    });

    test('reads identifiers written as attributes', () {
      final claim = XmpIdentification.parsePacket(
          '<rdf:Description pdfaid:part="2" pdfaid:conformance="U"/>');

      expect(claim.pdfALevel, equals(PdfAConformanceLevel.a2u));
      expect(claim.pdfAPart, equals('2'));
      expect(claim.pdfAConformance, equals('U'));
    });

    test('returns nothing for a packet without identifiers', () {
      final claim = XmpIdentification.parsePacket('<rdf:RDF></rdf:RDF>');

      expect(claim.pdfALevel, isNull);
      expect(claim.pdfUALevel, isNull);
      expect(claim.title, isNull);
    });
  });

  group('PdfAVerifier', () {
    test('says a plain document claims no profile', () async {
      final report = await PdfAVerifier.verify(await _plainDocument());

      expect(report.isConforming, isFalse);
      expect(report.claimedProfile, isNull);
      expect(report.violations.map((f) => f.code),
          contains('no-declared-profile'));
    });

    test('lists what a plain document lacks for PDF/A-1b', () async {
      final report = await PdfAVerifier.verify(
        await _plainDocument(),
        level: PdfAConformanceLevel.a1b,
      );

      final codes = report.violations.map((f) => f.code).toSet();
      expect(report.profile, equals('PDF/A-1b'));
      expect(codes, contains('missing-pdfaid'));
      expect(codes, contains('missing-metadata'));
      expect(codes, contains('missing-output-intent'));
      expect(report.isConforming, isFalse);
    });

    test('accepts the metadata and output intent it is given', () async {
      final report = await PdfAVerifier.verify(
        await _declaringDocument(part: '2', conformance: 'B'),
        level: PdfAConformanceLevel.a2b,
      );

      final codes = report.violations.map((f) => f.code).toSet();
      expect(report.claimedProfile, equals('PDF/A-2b'));
      expect(codes, isNot(contains('missing-pdfaid')));
      expect(codes, isNot(contains('missing-metadata')));
      expect(codes, isNot(contains('no-pdfa-output-intent')));
    });

    test('reports a claim that does not match the checked profile', () async {
      final report = await PdfAVerifier.verify(
        await _declaringDocument(part: '2', conformance: 'B'),
        level: PdfAConformanceLevel.a1b,
      );

      expect(report.warnings.map((f) => f.code), contains('profile-mismatch'));
    });

    test('requires tagging only for the accessible levels', () async {
      final basic = await PdfAVerifier.verify(
        await _declaringDocument(part: '2', conformance: 'B'),
        level: PdfAConformanceLevel.a2b,
      );
      final accessible = await PdfAVerifier.verify(
        await _declaringDocument(part: '2', conformance: 'A'),
        level: PdfAConformanceLevel.a2a,
      );

      expect(
          basic.violations.map((f) => f.code), isNot(contains('not-marked')));
      expect(accessible.violations.map((f) => f.code), contains('not-marked'));
      expect(accessible.violations.map((f) => f.code),
          contains('missing-structure-tree'));
    });

    test('names the rules it did not evaluate', () async {
      final report = await PdfAVerifier.verify(
        await _declaringDocument(part: '2', conformance: 'U'),
        level: PdfAConformanceLevel.a2u,
      );

      expect(report.unverifiedRules, isNotEmpty);
      expect(report.unverifiedRules.join(' '), contains('ToUnicode'));
    });

    test('serializes to a machine readable map', () async {
      final report = await PdfAVerifier.verify(
        await _plainDocument(),
        level: PdfAConformanceLevel.a1b,
      );
      final json = report.toJson();

      expect(json['profile'], equals('PDF/A-1b'));
      expect(json['conforming'], isFalse);
      expect(json['findings'], isA<List<Object?>>());
    });
  });

  group('PdfUAVerifier', () {
    test('lists what an untagged document lacks', () async {
      final report = await PdfUAVerifier.verify(await _plainDocument());

      final codes = report.violations.map((f) => f.code).toSet();
      expect(report.profile, equals('PDF/UA-1'));
      expect(codes, contains('missing-pdfuaid'));
      expect(codes, contains('missing-markinfo'));
      expect(codes, contains('missing-lang'));
      expect(codes, contains('missing-structure-tree'));
      expect(codes, contains('title-not-displayed'));
      expect(report.isConforming, isFalse);
    });

    test('accepts a declared identifier and title', () async {
      final report = await PdfUAVerifier.verify(
        await _declaringDocument(
            part: '2', conformance: 'A', uaPart: '1', title: 'Invoice 42'),
      );

      final codes = report.violations.map((f) => f.code).toSet();
      expect(report.claimedProfile, equals('PDF/UA-1'));
      expect(codes, isNot(contains('missing-pdfuaid')));
      expect(codes, isNot(contains('missing-title')));
    });

    test('names the judgements a person still has to make', () async {
      final report = await PdfUAVerifier.verify(await _plainDocument());

      expect(report.unverifiedRules.join(' '), contains('reading order'));
    });
  });
}
