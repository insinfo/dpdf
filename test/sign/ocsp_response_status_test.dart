import 'dart:typed_data';

import 'package:dpdf/src/sign/der_objects.dart';
import 'package:dpdf/src/sign/http_ocsp_client.dart';
import 'package:test/test.dart';

/// A minimal BasicOCSPResponse body; the tests only need it to survive the
/// transport extraction, not to carry a valid signature.
Uint8List _basicResponse() {
  final body = ASN1Sequence();
  body.add(ASN1Integer(BigInt.from(42)));
  return body.encode();
}

/// Builds an `OCSPResponse` of RFC 6960 section 4.2.1.
Uint8List _response(int status,
    {bool withBytes = true,
    String responseType = HttpOcspClient.basicResponseOid,
    Uint8List? response}) {
  final outer = ASN1Sequence();
  outer.add(ASN1Enumerated(BigInt.from(status)));
  if (withBytes) {
    final responseBytes = ASN1Sequence();
    responseBytes.add(ASN1ObjectIdentifier.fromIdentifierString(responseType));
    responseBytes
        .add(ASN1OctetString(octets: response ?? _basicResponse()));
    final explicit = ASN1Sequence(tag: 0xa0);
    explicit.add(responseBytes);
    outer.add(explicit);
  }
  return outer.encode();
}

void main() {
  group('RFC 6960 OCSPResponseStatus', () {
    test('every defined status maps to and from its wire value', () {
      expect(OcspResponseStatus.successful.value, 0);
      expect(OcspResponseStatus.malformedRequest.value, 1);
      expect(OcspResponseStatus.internalError.value, 2);
      expect(OcspResponseStatus.tryLater.value, 3);
      expect(OcspResponseStatus.sigRequired.value, 5);
      expect(OcspResponseStatus.unauthorized.value, 6);
      for (final status in OcspResponseStatus.values) {
        expect(OcspResponseStatus.fromValue(status.value), status);
      }
      // The value 4 is explicitly not used by RFC 6960.
      expect(OcspResponseStatus.fromValue(4), isNull);
      expect(OcspResponseStatus.fromValue(7), isNull);
    });

    test('a successful response yields the basic response', () {
      final basic = HttpOcspClient.parseBasicResponse(_response(0));
      expect(basic, isA<ASN1Sequence>());
      expect((basic as ASN1Sequence).elements, hasLength(1));
    });

    test('the status is read before the response bytes are trusted', () {
      final sequence =
          ASN1Parser(_response(3)).nextObject() as ASN1Sequence;
      expect(HttpOcspClient.readResponseStatusValue(sequence), 3);
    });

    for (final status in [
      OcspResponseStatus.malformedRequest,
      OcspResponseStatus.internalError,
      OcspResponseStatus.tryLater,
      OcspResponseStatus.sigRequired,
      OcspResponseStatus.unauthorized,
    ]) {
      test('${status.name} is reported instead of being taken as success', () {
        expect(
            () => HttpOcspClient.parseBasicResponse(
                _response(status.value, withBytes: false)),
            throwsA(isA<OcspResponseStatusException>()
                .having((e) => e.status, 'status', status)
                .having((e) => e.value, 'value', status.value)));
      });

      test('${status.name} is rejected even when response bytes are present',
          () {
        // A responder that violates the syntax must not be able to smuggle a
        // usable response past the status check.
        expect(
            () => HttpOcspClient.parseBasicResponse(_response(status.value)),
            throwsA(isA<OcspResponseStatusException>()));
      });
    }

    test('the unassigned status 4 is rejected as unknown', () {
      expect(
          () => HttpOcspClient.parseBasicResponse(
              _response(4, withBytes: false)),
          throwsA(isA<OcspResponseStatusException>()
              .having((e) => e.status, 'status', isNull)
              .having((e) => e.value, 'value', 4)));
    });

    test('a successful response without response bytes is malformed', () {
      expect(
          () => HttpOcspClient.parseBasicResponse(
              _response(0, withBytes: false)),
          throwsA(isA<FormatException>()));
    });

    test('an unsupported response type is rejected', () {
      expect(
          () => HttpOcspClient.parseBasicResponse(
              _response(0, responseType: '1.3.6.1.5.5.7.48.1.2')),
          throwsA(isA<FormatException>()));
    });

    test('a response that is not a SEQUENCE is rejected', () {
      expect(
          () => HttpOcspClient.parseBasicResponse(
              Uint8List.fromList(ASN1Null().encode())),
          throwsA(isA<FormatException>()));
    });

    test('a first element that is not an ENUMERATED is rejected', () {
      final outer = ASN1Sequence();
      outer.add(ASN1Integer(BigInt.zero));
      expect(
          () => HttpOcspClient.parseBasicResponse(
              Uint8List.fromList(outer.encode())),
          throwsA(isA<FormatException>()));
    });

    test('an empty response is rejected', () {
      expect(
          () => HttpOcspClient.parseBasicResponse(
              Uint8List.fromList(ASN1Sequence().encode())),
          throwsA(isA<FormatException>()));
    });

    test('the exception describes the status it rejected', () {
      expect(
          OcspResponseStatusException(OcspResponseStatus.tryLater, 3)
              .toString(),
          contains('tryLater'));
      expect(OcspResponseStatusException(null, 4).toString(),
          contains('unknown status'));
    });

    test('a fresh client has not seen any response status yet', () {
      expect(HttpOcspClient().getLastResponseStatus(), isNull);
    });
  });
}
