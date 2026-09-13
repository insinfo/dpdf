import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_40.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/encryption_constants.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_encryption.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_version.dart';
import 'package:test/test.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

final Uint8List documentId =
    Uint8List.fromList(List<int>.generate(16, (i) => (i * 7 + 3) & 0xFF));

const int samplePermissions = EncryptionConstants.allowPrinting |
    EncryptionConstants.allowCopy |
    EncryptionConstants.allowScreenreaders;

PdfEncryption writeStandard(int algorithm,
    {Uint8List? user, Uint8List? owner, PdfVersion? version}) {
  return PdfEncryption.standard(
    userPassword: user ?? bytes('user-secret'),
    ownerPassword: owner ?? bytes('owner-secret'),
    permissions: samplePermissions,
    encryptionAlgorithm: algorithm,
    documentId: documentId,
    version: version,
  );
}

Future<PdfEncryption> readBack(PdfEncryption written, Uint8List password) {
  return PdfEncryption.createFromDictionary(
      written.pdfRepresentation(), password, documentId);
}

void main() {
  group('Standard security handler dictionary', () {
    test('revision 2 writes /V 1 and /R 2 with 32-byte /O and /U', () async {
      final encryption =
          writeStandard(EncryptionConstants.standardEncryption40);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.nameEntry(PdfName.filter))!.getValue(),
          'Standard');
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 1);
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 2);
      expect((await dictionary.stringEntry(PdfName.o))!.getValueBytes()!.length,
          32);
      expect((await dictionary.stringEntry(PdfName.u))!.getValueBytes()!.length,
          32);
      expect(encryption.getFileEncryptionKey().length, 5);
    });

    test('revision 3 writes /V 2 with a 128-bit /Length', () async {
      final encryption =
          writeStandard(EncryptionConstants.standardEncryption128);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 2);
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 3);
      expect((await dictionary.numberEntry(PdfName.length))!.intValue(), 128);
      expect(encryption.getFileEncryptionKey().length, 16);
    });

    test('AES-128 writes /V 4 with an AESV2 StdCF crypt filter', () async {
      final encryption = writeStandard(EncryptionConstants.encryptionAes128);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 4);
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 4);
      expect((await dictionary.nameEntry(PdfName.stmF))!.getValue(), 'StdCF');
      expect((await dictionary.nameEntry(PdfName.strF))!.getValue(), 'StdCF');
      final cf = await dictionary.dictionaryEntry(PdfName.cf);
      final stdcf = await cf!.dictionaryEntry(PdfName.stdCF);
      expect((await stdcf!.nameEntry(PdfName.cfm))!.getValue(), 'AESV2');
      expect((await stdcf.nameEntry(PdfName.authEvent))!.getValue(), 'DocOpen');
    });

    test('AES-256 writes /V 5, /R 6 and the AESV3 filter for PDF 2.0',
        () async {
      final encryption = writeStandard(EncryptionConstants.encryptionAes256,
          version: PdfVersion.PDF_2_0);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 5);
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 6);
      expect((await dictionary.stringEntry(PdfName.o))!.getValueBytes()!.length,
          48);
      expect((await dictionary.stringEntry(PdfName.u))!.getValueBytes()!.length,
          48);
      expect(
          (await dictionary.stringEntry(PdfName.oe))!.getValueBytes()!.length,
          32);
      expect(
          (await dictionary.stringEntry(PdfName.ue))!.getValueBytes()!.length,
          32);
      expect(
          (await dictionary.stringEntry(PdfName.perms))!
              .getValueBytes()!
              .length,
          16);
      expect(encryption.getFileEncryptionKey().length, 32);
    });

    test('AES-256 without an explicit version writes revision 5', () async {
      final encryption = writeStandard(EncryptionConstants.encryptionAes256);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 5);
    });

    test('the encryption dictionary strings are direct and hexadecimal',
        () async {
      // 7.6.1: "strings in the encryption dictionary shall be direct objects"
      // and their contents are never encrypted.
      final encryption = writeStandard(EncryptionConstants.encryptionAes256);
      final dictionary = encryption.pdfRepresentation();
      for (final key in [PdfName.o, PdfName.u, PdfName.oe, PdfName.ue]) {
        final value = await dictionary.stringEntry(key);
        expect(value, isNotNull, reason: '$key is missing');
        expect(value!.isHexWriting(), isTrue);
        expect(value.indirectHandle(), isNull);
      }
    });
  });

  group('Password authentication', () {
    for (final entry in {
      'RC4 40': EncryptionConstants.standardEncryption40,
      'RC4 128': EncryptionConstants.standardEncryption128,
      'AES 128': EncryptionConstants.encryptionAes128,
      'AES 256': EncryptionConstants.encryptionAes256,
    }.entries) {
      test('${entry.key} recovers the same file key from the user password',
          () async {
        final written = writeStandard(entry.value);
        final read = await readBack(written, bytes('user-secret'));
        expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
        expect(read.isOwnerPasswordUsed(), isFalse);
      });

      test('${entry.key} recovers the same file key from the owner password',
          () async {
        final written = writeStandard(entry.value);
        final read = await readBack(written, bytes('owner-secret'));
        expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
        expect(read.isOwnerPasswordUsed(), isTrue);
      });

      test('${entry.key} rejects a wrong password', () async {
        final written = writeStandard(entry.value);
        expect(readBack(written, bytes('not-the-password')),
            throwsA(isA<PdfException>()));
      });

      test('${entry.key} preserves the permission flags', () async {
        final written = writeStandard(entry.value);
        final read = await readBack(written, bytes('user-secret'));
        expect(read.getPermissions(), written.getPermissions());
        expect(read.getPermissions()! & EncryptionConstants.allowCopy,
            EncryptionConstants.allowCopy);
        expect(read.getPermissions()! & EncryptionConstants.allowModifyContents,
            0);
      });
    }

    test('revision 6 authenticates through the Algorithm 2.B hardening',
        () async {
      final written = writeStandard(EncryptionConstants.encryptionAes256,
          version: PdfVersion.PDF_2_0);
      final read = await readBack(written, bytes('user-secret'));
      expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
      expect(
          (written.getSecurityHandler() as dynamic).isRevision6(), isTrue);
    });

    test('an empty user password opens the document', () async {
      final written = PdfEncryption.standard(
        userPassword: Uint8List(0),
        ownerPassword: bytes('owner-only'),
        permissions: samplePermissions,
        encryptionAlgorithm: EncryptionConstants.encryptionAes128,
        documentId: documentId,
      );
      final read = await readBack(written, Uint8List(0));
      expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
      expect(read.isOwnerPasswordUsed(), isFalse);
    });

    test('a password longer than 32 bytes is truncated for revision 4',
        () async {
      final long = bytes('x' * 40);
      final written = PdfEncryption.standard(
        userPassword: long,
        ownerPassword: bytes('owner'),
        permissions: samplePermissions,
        encryptionAlgorithm: EncryptionConstants.encryptionAes128,
        documentId: documentId,
      );
      final truncated = Uint8List.fromList(long.sublist(0, 32));
      final read = await readBack(written, truncated);
      expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
    });

    test('a password longer than 127 bytes is truncated for AES-256',
        () async {
      final long = bytes('y' * 200);
      final written = PdfEncryption.standard(
        userPassword: long,
        ownerPassword: bytes('owner'),
        permissions: samplePermissions,
        encryptionAlgorithm: EncryptionConstants.encryptionAes256,
        documentId: documentId,
        version: PdfVersion.PDF_2_0,
      );
      final read = await readBack(
          written, Uint8List.fromList(long.sublist(0, 127)));
      expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
    });
  });

  group('Algorithm 2 inputs', () {
    test('the document identifier changes the file encryption key', () {
      final a = writeStandard(EncryptionConstants.standardEncryption128);
      final b = PdfEncryption.standard(
        userPassword: bytes('user-secret'),
        ownerPassword: bytes('owner-secret'),
        permissions: samplePermissions,
        encryptionAlgorithm: EncryptionConstants.standardEncryption128,
        documentId: Uint8List.fromList(List<int>.filled(16, 9)),
      );
      expect(a.getFileEncryptionKey(), isNot(b.getFileEncryptionKey()));
    });

    test('the permission bits change the file encryption key', () {
      final a = writeStandard(EncryptionConstants.standardEncryption128);
      final b = PdfEncryption.standard(
        userPassword: bytes('user-secret'),
        ownerPassword: bytes('owner-secret'),
        permissions: EncryptionConstants.allowPrinting,
        encryptionAlgorithm: EncryptionConstants.standardEncryption128,
        documentId: documentId,
      );
      expect(a.getFileEncryptionKey(), isNot(b.getFileEncryptionKey()));
    });

    test('revision 2 forces the reserved permission bits of Table 22', () {
      final encryption =
          writeStandard(EncryptionConstants.standardEncryption40);
      // Bits 1, 2 are zero and bits 7, 8 and 13 to 32 are one.
      final permissions = encryption.getPermissions()!;
      expect(permissions & 0x3, 0);
      expect(permissions & 0xC0, 0xC0);
    });

    test('padPassword reproduces the padding string of Algorithm 2', () {
      final handler = StandardHandlerUsingStandard40.read(
          PdfDictionary(), Uint8List(0), documentId, true);
      expect(handler.padPassword(null), StandardHandlerUsingStandard40.pad);
      final padded = handler.padPassword(bytes('ab'));
      expect(padded.length, 32);
      expect(padded.sublist(0, 2), bytes('ab'));
      expect(padded.sublist(2),
          StandardHandlerUsingStandard40.pad.sublist(0, 30));
    });
  });

  group('EncryptMetadata and embedded files only', () {
    test('doNotEncryptMetadata writes /EncryptMetadata false', () async {
      final encryption = writeStandard(EncryptionConstants.encryptionAes128 |
          EncryptionConstants.doNotEncryptMetadata);
      final dictionary = encryption.pdfRepresentation();
      expect(
          (await dictionary.booleanEntry(PdfName.encryptMetadata))!.getValue(),
          isFalse);
      expect(encryption.isMetadataEncrypted(), isFalse);
      final read = await readBack(encryption, bytes('user-secret'));
      expect(read.isMetadataEncrypted(), isFalse);
      expect(read.getFileEncryptionKey(), encryption.getFileEncryptionKey());
    });

    test('AES-256 records EncryptMetadata inside /Perms', () async {
      final encryption = writeStandard(EncryptionConstants.encryptionAes256 |
          EncryptionConstants.doNotEncryptMetadata);
      final read = await readBack(encryption, bytes('user-secret'));
      expect(read.isMetadataEncrypted(), isFalse);
    });

    test('embeddedFilesOnly points /StmF and /StrF at Identity', () async {
      final encryption = writeStandard(EncryptionConstants.encryptionAes128 |
          EncryptionConstants.embeddedFilesOnly);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.nameEntry(PdfName.stmF))!.getValue(),
          'Identity');
      expect((await dictionary.nameEntry(PdfName.strF))!.getValue(),
          'Identity');
      expect((await dictionary.nameEntry(PdfName.eff))!.getValue(), 'StdCF');
      final cf = await dictionary.dictionaryEntry(PdfName.cf);
      final stdcf = await cf!.dictionaryEntry(PdfName.stdCF);
      expect((await stdcf!.nameEntry(PdfName.authEvent))!.getValue(), 'EFOpen');

      final filters = encryption.getCryptFilters()!;
      expect(filters.streamFilter.isIdentity, isTrue);
      expect(filters.stringFilter.isIdentity, isTrue);
      expect(filters.embeddedFileFilter.method, CryptFilterMethod.aesV2);
    });
  });
}
