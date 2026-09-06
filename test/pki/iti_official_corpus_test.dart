import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as oracle;
import 'package:pdfcraft/src/pki/jks_key_store.dart';
import 'package:pdfcraft/src/sign/x509_certificate.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/iti_assets');
  final manifest = File('test/pki/iti_corpus_manifest.json');
  final available = root.existsSync() && manifest.existsSync();
  final skipReason = available
      ? false
      : 'Corpus ITI ausente: execute o downloader fixado em tool/ antes deste teste.';
  final storeFile = File('${root.path}/jks/keystore_ICP_Brasil.jks');
  Uint8List certificateBytes(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.isNotEmpty && bytes[0] == 0x30) return bytes;
    final text = ascii.decode(bytes);
    final match = RegExp(
            r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----')
        .firstMatch(text);
    if (match == null)
      throw FormatException('Certificate is neither DER nor PEM: ${file.path}');
    return base64Decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
  }

  void inspect(Uint8List bytes) {
    final certificate = X509Certificate(bytes);
    expect(certificate.getEncoded(), bytes);
    expect(certificate.getSubjectDN(), isNotEmpty);
    expect(certificate.getIssuerDN(), isNotEmpty);
    expect(certificate.getSerialNumber() >= BigInt.zero, isTrue);
    expect(
        certificate.getNotBefore().isBefore(certificate.getNotAfter()), isTrue);
    expect(certificate.getPublicKey(), isNotEmpty);
    expect(certificate.getSigAlgOID(), isNotEmpty);
    expect(certificate.getTbsCertificate(), isNotEmpty);
  }

  test('official ITI cached files match pinned inventory', () {
    final parsed =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    var count = 0;
    for (final archive in parsed['archives'] as List) {
      final bundle = File('${root.path}/${archive['name']}.zip');
      final archived = bundle.readAsBytesSync();
      expect(archived.length, archive['size']);
      expect(oracle.sha512.convert(archived).toString(), archive['sha512']);
      final extracted = Directory('${root.path}/${archive['name']}')
          .listSync(recursive: true)
          .whereType<File>()
          .length;
      expect(extracted, (archive['files'] as List).length);
      for (final item in archive['files'] as List) {
        final file = File('${root.path}/${item['path']}');
        expect(file.existsSync(), isTrue, reason: file.path);
        final bytes = file.readAsBytesSync();
        expect(bytes.length, item['size'], reason: file.path);
        expect(oracle.sha256.convert(bytes).toString(), item['sha256'],
            reason: file.path);
        count++;
      }
    }
    expect(count, greaterThan(0));
  }, skip: skipReason);
  test('official JKS authentication and every certificate decode', () {
    final store =
        JksKeyStore.read(storeFile.readAsBytesSync(), password: '12345678');
    var count = 0;
    final fingerprints = <String>[];
    for (final entry in store.entries.values) {
      final certificates = switch (entry) {
        JksTrustedCertificate() => [entry.certificate],
        JksPrivateKey() => entry.certificateChain,
      };
      for (final certificate in certificates) {
        inspect(certificate.bytes);
        fingerprints.add(oracle.sha256.convert(certificate.bytes).toString());
        count++;
      }
    }
    final pinned = (jsonDecode(manifest.readAsStringSync())
        as Map<String, dynamic>)['jks_oracle'];
    expect(store.entries.length, pinned['entry_count']);
    fingerprints.sort();
    expect(fingerprints, pinned['sha256_certificates']);
    expect(count, greaterThan(0));
    print('ITI JKS: ${store.entries.length} entries, $count certificates');
  }, skip: skipReason);
  test('official JKS rejects wrong password and tampered data', () {
    final bytes = storeFile.readAsBytesSync();
    expect(() => JksKeyStore.read(bytes, password: 'incorrect'),
        throwsFormatException);
    final changed = Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 1;
    expect(() => JksKeyStore.read(changed, password: '12345678'),
        throwsFormatException);
  }, skip: skipReason);
  test('every ZIP certificate decodes and fingerprints intersect JKS', () {
    final parsed =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    final archive = (parsed['archives'] as List)
        .firstWhere((item) => item['name'] == 'certificates');
    final zipHashes = <String>{};
    for (final item in archive['files'] as List) {
      final bytes = certificateBytes(File('${root.path}/${item['path']}'));
      inspect(bytes);
      zipHashes.add(oracle.sha256.convert(bytes).toString());
    }
    final store =
        JksKeyStore.read(storeFile.readAsBytesSync(), password: '12345678');
    final storeHashes = <String>{};
    for (final entry in store.entries.values) {
      final certificates = switch (entry) {
        JksTrustedCertificate() => [entry.certificate],
        JksPrivateKey() => entry.certificateChain,
      };
      for (final certificate in certificates) {
        storeHashes.add(oracle.sha256.convert(certificate.bytes).toString());
      }
    }
    final shared = zipHashes.intersection(storeHashes);
    expect(shared, isNotEmpty);
    print(
        'ITI fingerprint sets: ZIP=${zipHashes.length}, JKS=${storeHashes.length}, shared=${shared.length}, ZIP-only=${zipHashes.difference(storeHashes).length}, JKS-only=${storeHashes.difference(zipHashes).length}');
  }, skip: skipReason);
}
