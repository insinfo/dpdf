import 'dart:typed_data';
import 'package:dpdf/src/sign/asn1_utils.dart';
import 'package:dpdf/src/sign/timestamp_client.dart';
import 'package:test/test.dart';

void main() {
  final client = TimestampClient('https://example.invalid');
  Uint8List token({String oid = '1.2.840.113549.1.7.2'}) =>
      ASN1Utils.createSequence([
        ASN1Utils.createOID(oid),
        ASN1Utils.encodeTagged(0xa0, ASN1Utils.createSequence([])),
      ]);
  Uint8List response(int status, [Uint8List? value]) =>
      ASN1Utils.createSequence([
        ASN1Utils.createSequence([ASN1Utils.createIntegerFromInt(status)]),
        if (value != null) value,
      ]);

  test('both granted statuses preserve the complete CMS DER envelope', () {
    for (final status in [0, 1]) {
      final expected = token();
      final source = response(status, expected);
      final parsed = client.parseTimeStampResponse(source);
      expect(parsed, expected);
      source.fillRange(0, source.length, 0);
      expect(parsed, expected);
    }
  });
  test('non-granted status is rejected even when a token is supplied', () {
    for (var status = 2; status <= 6; status++) {
      expect(() => client.parseTimeStampResponse(response(status, token())),
          throwsFormatException);
    }
  });
  test('missing token and wrong CMS content type are rejected', () {
    for (final value in [
      response(0),
      response(0, token(oid: '1.2.840.113549.1.7.1')),
      response(0, ASN1Utils.createOctetString(Uint8List(1)))
    ]) {
      expect(() => client.parseTimeStampResponse(value), throwsFormatException);
    }
  });
  test('truncation, trailing bytes and nonminimal lengths are rejected', () {
    final valid = response(0, token());
    final malformed = <List<int>>[
      [],
      [0x30],
      [...valid, 0],
      valid.sublist(0, valid.length - 1),
      [0x30, 0x80, ...valid.sublist(2), 0, 0],
      [0x30, 0x81, valid[1], ...valid.sublist(2)],
      [0x30, 0x82, 0, valid[1], ...valid.sublist(2)],
      [0x30, 2, 0x30, 4],
    ];
    for (final bytes in malformed) {
      expect(() => client.parseTimeStampResponse(Uint8List.fromList(bytes)),
          throwsFormatException,
          reason: '$bytes');
    }
  });
  test('status integer and explicit CMS wrapper have strict framing', () {
    for (final status in [
      ASN1Utils.createNull(),
      ASN1Utils.encodeTagged(2, Uint8List.fromList([0, 0]))
    ]) {
      expect(
          () => client.parseTimeStampResponse(ASN1Utils.createSequence([
                ASN1Utils.createSequence([status]),
                token()
              ])),
          throwsFormatException);
    }
    final wrongWrapper = ASN1Utils.createSequence([
      ASN1Utils.createOID('1.2.840.113549.1.7.2'),
      ASN1Utils.encodeTagged(0xa0, ASN1Utils.createNull()),
    ]);
    expect(() => client.parseTimeStampResponse(response(0, wrongWrapper)),
        throwsFormatException);
  });
}
