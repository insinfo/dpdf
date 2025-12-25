import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/src/sign/asn1_utils.dart';
import 'package:dpdf/src/sign/tsa_client_bouncy_castle.dart';
import 'package:dpdf/src/sign/digest_algorithms.dart';
import 'package:dpdf/src/sign/oid.dart';

void main() {
  group('ASN1Utils Encoding', () {
    test('createInteger encodes positive integer', () {
      final result = ASN1Utils.createInteger(BigInt.from(256));
      expect(result[0], equals(0x02)); // INTEGER tag
      expect(result.length, greaterThan(2));
    });

    test('createInteger encodes zero', () {
      final result = ASN1Utils.createInteger(BigInt.zero);
      expect(result[0], equals(0x02)); // INTEGER tag
      expect(result[1], equals(1)); // length
      expect(result[2], equals(0)); // value
    });

    test('createIntegerFromInt works correctly', () {
      final result = ASN1Utils.createIntegerFromInt(42);
      expect(result[0], equals(0x02)); // INTEGER tag
      expect(result[1], equals(1)); // length
      expect(result[2], equals(42)); // value
    });

    test('createOctetString encodes correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = ASN1Utils.createOctetString(data);
      expect(result[0], equals(0x04)); // OCTET STRING tag
      expect(result[1], equals(5)); // length
      expect(result.sublist(2), equals(data));
    });

    test('createNull encodes correctly', () {
      final result = ASN1Utils.createNull();
      expect(result[0], equals(0x05)); // NULL tag
      expect(result[1], equals(0)); // length
      expect(result.length, equals(2));
    });

    test('createBoolean encodes true', () {
      final result = ASN1Utils.createBoolean(true);
      expect(result[0], equals(0x01)); // BOOLEAN tag
      expect(result[1], equals(1)); // length
      expect(result[2], equals(0xFF)); // TRUE
    });

    test('createBoolean encodes false', () {
      final result = ASN1Utils.createBoolean(false);
      expect(result[0], equals(0x01)); // BOOLEAN tag
      expect(result[1], equals(1)); // length
      expect(result[2], equals(0x00)); // FALSE
    });

    test('createOID encodes SHA-256 OID', () {
      final result = ASN1Utils.createOID(OID.sha256);
      expect(result[0], equals(0x06)); // OID tag
      expect(result.length, greaterThan(2));
    });

    test('createSequence encodes correctly', () {
      final elements = [
        ASN1Utils.createIntegerFromInt(1),
        ASN1Utils.createOctetString(Uint8List.fromList([0xAB, 0xCD])),
      ];
      final result = ASN1Utils.createSequence(elements);
      expect(result[0], equals(0x30)); // SEQUENCE tag
    });

    test('createSet encodes correctly', () {
      final elements = [
        ASN1Utils.createIntegerFromInt(1),
        ASN1Utils.createIntegerFromInt(2),
      ];
      final result = ASN1Utils.createSet(elements);
      expect(result[0], equals(0x31)); // SET tag
    });

    test('createUtcTime encodes correctly', () {
      final date = DateTime.utc(2025, 12, 25, 10, 30, 0);
      final result = ASN1Utils.createUtcTime(date);
      expect(result[0], equals(0x17)); // UTC TIME tag
      // Format should be YYMMDDHHMMSSZ
      final content = String.fromCharCodes(result.sublist(2));
      expect(content, equals('251225103000Z'));
    });

    test('createTagged creates context-specific tag', () {
      final content = ASN1Utils.createIntegerFromInt(42);
      final result = ASN1Utils.createTagged(0, content);
      expect(result[0], equals(0xA0)); // Context-specific [0] constructed
    });

    test('createUtf8String encodes correctly', () {
      final result = ASN1Utils.createUtf8String('Hello');
      expect(result[0], equals(0x0C)); // UTF8 STRING tag
      expect(result[1], equals(5)); // length
    });

    test('createPrintableString encodes correctly', () {
      final result = ASN1Utils.createPrintableString('Test');
      expect(result[0], equals(0x13)); // PRINTABLE STRING tag
      expect(result[1], equals(4)); // length
    });

    test('createBitString encodes correctly', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final result = ASN1Utils.createBitString(data);
      expect(result[0], equals(0x03)); // BIT STRING tag
      expect(result[1], equals(4)); // length (including unused bits byte)
      expect(result[2], equals(0)); // unused bits
      expect(result.sublist(3), equals(data));
    });
  });

  group('ASN1Utils Parsing', () {
    test('parse decodes simple integer', () {
      final encoded = Uint8List.fromList([0x02, 0x01, 0x2A]); // INTEGER 42
      final result = ASN1Utils.parse(encoded);
      expect(result.tag, equals(0x02));
      expect(result.content.length, equals(1));
      expect(result.content[0], equals(42));
    });

    test('parse decodes long length', () {
      // Create an OCTET STRING with 256 bytes
      final content = Uint8List(256);
      for (int i = 0; i < 256; i++) {
        content[i] = i % 256;
      }
      final encoded = ASN1Utils.createOctetString(content);
      final result = ASN1Utils.parse(encoded);
      expect(result.tag, equals(0x04));
      expect(result.content.length, equals(256));
    });

    test('parseSequence decodes correctly', () {
      // Create a sequence with two integers
      final seq = ASN1Utils.createSequence([
        ASN1Utils.createIntegerFromInt(1),
        ASN1Utils.createIntegerFromInt(2),
      ]);
      final elements = ASN1Utils.parseSequence(seq);
      expect(elements.length, equals(2));
      expect(elements[0].isInteger, isTrue);
      expect(elements[1].isInteger, isTrue);
    });

    test('parseElements handles empty content', () {
      final elements = ASN1Utils.parseElements(Uint8List(0));
      expect(elements, isEmpty);
    });

    test('ASN1ParseResult properties work correctly', () {
      final seq = ASN1Utils.createSequence([ASN1Utils.createNull()]);
      final result = ASN1Utils.parse(seq);
      expect(result.isSequence, isTrue);
      expect(result.isSet, isFalse);
      expect(result.isInteger, isFalse);
      expect(result.isOctetString, isFalse);
      expect(result.isContextSpecific, isFalse);
    });
  });

  group('TSAClientBouncyCastle', () {
    test('constructor sets properties correctly', () {
      final client = TSAClientBouncyCastle(
        'http://timestamp.example.com',
        digestAlgorithm: 'SHA-256',
        tokenSizeEstimate: 4096,
      );

      expect(client.getUrl(), equals('http://timestamp.example.com'));
      expect(client.getDigestAlgorithm(), equals('SHA-256'));
      expect(client.getTokenSizeEstimate(), equals(4096));
    });

    test('setTokenSizeEstimate updates estimate', () {
      final client = TSAClientBouncyCastle('http://example.com');
      client.setTokenSizeEstimate(8192);
      expect(client.getTokenSizeEstimate(), equals(8192));
    });

    test('getMessageDigest returns working digest', () {
      final client = TSAClientBouncyCastle('http://example.com');
      final digest = client.getMessageDigest();
      digest.update(Uint8List.fromList([1, 2, 3]));
      final result = digest.digest();
      expect(result.length, equals(32)); // SHA-256
    });

    test('buildTimeStampRequest creates valid ASN.1', () {
      final client = TSAClientBouncyCastle('http://example.com');
      final imprint = DigestAlgorithms.digestBytes(
        Uint8List.fromList([1, 2, 3, 4, 5]),
        'SHA-256',
      );

      final request = client.buildTimeStampRequest(imprint);

      // Should be a valid ASN.1 SEQUENCE
      expect(request[0], equals(0x30)); // SEQUENCE tag
      expect(
          request.length, greaterThan(50)); // Should have significant content
    });

    test('getAuthorizationHeader returns null without credentials', () {
      final client = TSAClientBouncyCastle('http://example.com');
      expect(client.getAuthorizationHeader(), isNull);
    });

    test('getAuthorizationHeader returns Basic auth with credentials', () {
      final client = TSAClientBouncyCastle(
        'http://example.com',
        username: 'user',
        password: 'pass',
      );
      final header = client.getAuthorizationHeader();
      expect(header, startsWith('Basic '));
    });

    test('getTimeStampToken throws UnimplementedError', () {
      final client = TSAClientBouncyCastle('http://example.com');
      expect(
        () async => await client.getTimeStampToken(Uint8List(32)),
        throwsUnimplementedError,
      );
    });
  });

  group('SimpleTSAClient factories', () {
    test('freeTsa creates correct URL', () {
      final client = SimpleTSAClient.freeTsa();
      expect(client.getUrl(), equals('https://freetsa.org/tsr'));
    });

    test('digiCert creates correct URL', () {
      final client = SimpleTSAClient.digiCert();
      expect(client.getUrl(), equals('http://timestamp.digicert.com'));
    });

    test('symantec creates correct URL', () {
      final client = SimpleTSAClient.symantec();
      expect(client.getUrl(), contains('symantec.com'));
    });

    test('globalSign creates correct URL', () {
      final client = SimpleTSAClient.globalSign();
      expect(client.getUrl(), contains('globalsign.com'));
    });
  });
}
