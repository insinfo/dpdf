import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/forms/pdf_sig_field_lock.dart';
import 'package:dpdf/src/kernel/pdf/stamping_properties.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/access_permissions.dart';
import 'package:dpdf/src/sign/pdf_signature_reference.dart';
import 'package:dpdf/src/sign/signature_modification_analyzer.dart';
import 'package:dpdf/src/sign/signature_util.dart';
import 'package:dpdf/src/sign/signature_mechanism_params.dart';
import 'package:test/test.dart';

/// Ephemeral signing identity; it proves the integration, not a trust anchor.
class _Identity {
  final RSAPrivateKey key;
  final List<Uint8List> chain;
  _Identity(this.key, this.chain);

  static _Identity create() {
    final keys = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    final privateKey = keys.privateKey as RSAPrivateKey;
    final certificate = PkiUtils.createCertificate(
      subjectDN: 'CN=DPDF transform test',
      issuerDN: 'CN=DPDF transform test',
      issuerPrivateKey: privateKey,
      subjectPublicKey: keys.publicKey as RSAPublicKey,
      serialNumber: BigInt.one,
      notBefore: DateTime.utc(2026),
      notAfter: DateTime.utc(2027),
    );
    return _Identity(privateKey, [certificate]);
  }
}

class _LocalSignature implements ExternalSignature {
  final RSAPrivateKey key;
  _LocalSignature(this.key);
  @override
  String getDigestAlgorithmName() => 'SHA-256';
  @override
  String getSignatureAlgorithmName() => 'RSA';
  @override
  SignatureMechanismParams? getSignatureMechanismParameters() => null;
  @override
  Future<Uint8List> sign(Uint8List message) async {
    final signer = Signer('SHA-256/RSA')..init(true, PrivateKeyParameter(key));
    return signer.generateSignature(message).bytes;
  }
}

Future<Uint8List> _blankDocument() async {
  final bytes = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  await document.appendBlankPage();
  await document.close();
  return bytes.takeBytes();
}

Future<Uint8List> _documentWithTextField(String name, String value) async {
  final bytes = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final page = await document.appendBlankPage();
  final form = await PdfAcroForm.getAcroForm(document, true);
  await form.addField(
      await PdfTextFormField.createText(document, name, value,
          PdfWidgetAnnotation.fromRect(Rectangle(20, 500, 200, 24))),
      page);
  await document.close();
  return bytes.takeBytes();
}

Future<Uint8List> _sign(
  Uint8List input,
  _Identity identity, {
  String? fieldName,
  AccessPermissions certification = AccessPermissions.unspecified,
  PdfSigFieldLock? fieldLock,
  PdfName? subFilter,
}) async {
  final output = BytesBuilder();
  final signer = PdfSigner.fromBytesBuilder(input, output);
  final properties = signer.getSignerProperties()
    ..setCertificationLevel(certification)
    ..setFieldLockDict(fieldLock)
    ..setClaimedSignDate(DateTime.utc(2026, 3, 14, 15, 9, 26));
  if (fieldName != null) properties.setFieldName(fieldName);
  await signer.signDetached(_LocalSignature(identity.key), identity.chain,
      subFilter: subFilter);
  return output.takeBytes();
}

Future<T> _withDocument<T>(
    Uint8List bytes, Future<T> Function(PdfDocument) body) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return await body(document);
  } finally {
    await document.close();
  }
}

void main() {
  group('signature dictionary entries of ISO 32000-1 table 252', () {
    test('a detached signature declares SubFilter, ByteRange and M', () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity);
      await _withDocument(signed, (document) async {
        final util = SignatureUtil(document);
        final name = (await util.getSignatureNames()).single;
        final signature = (await util.getSignature(name))!;
        expect((await signature.getSubFilter())!.getValue(),
            'adbe.pkcs7.detached');
        expect((await signature.getByteRange())!.size(), 4);
        expect((await signature.getDate())!.getValue(), startsWith('D:2026'));
        expect(await util.signatureCoversWholeDocument(name), isTrue);
        expect((await util.readSignatureData(name))!.verify(), isTrue);
      });
    });

    test('the claimed sign date drives /M rather than the wall clock',
        () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity);
      await _withDocument(signed, (document) async {
        final util = SignatureUtil(document);
        final name = (await util.getSignatureNames()).single;
        final signature = (await util.getSignature(name))!;
        expect((await signature.getDate())!.getValue(),
            startsWith('D:20260314150926'));
      });
    });

    test('adbe.pkcs7.sha1 encapsulates the SHA1 digest of the byte range',
        () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity,
          subFilter: PdfName.adbePkcs7Sha1);
      await _withDocument(signed, (document) async {
        final util = SignatureUtil(document);
        final name = (await util.getSignatureNames()).single;
        final verifier = (await util.readSignatureData(name))!;
        expect(verifier.getFilterSubtype(), PdfName.adbePkcs7Sha1);
        expect(verifier.getEncapMessageContent(), hasLength(20));
        expect(verifier.verify(), isTrue);
        expect(verifier.verifyDigest(), isTrue);
      });
    });

    test('ETSI.CAdES.detached verifies and is reported as CAdES', () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity,
          subFilter: PdfName.etsiCadesDetached);
      await _withDocument(signed, (document) async {
        final util = SignatureUtil(document);
        final name = (await util.getSignatureNames()).single;
        final verifier = (await util.readSignatureData(name))!;
        expect(verifier.isCades(), isTrue);
        expect(verifier.verify(), isTrue);
      });
    });

    test('an unsupported SubFilter is rejected before anything is written',
        () async {
      final identity = _Identity.create();
      final blank = await _blankDocument();
      await expectLater(
          _sign(blank, identity,
              subFilter: PdfName.intern('adbe.x509.rsa_sha1')),
          throwsA(isA<PdfException>()));
    });
  });

  group('DocMDP transform method of ISO 32000-1 12.8.2.2', () {
    test('a certification signature writes Perms/DocMDP and its /P', () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity,
          certification: AccessPermissions.noChangesPermitted);
      await _withDocument(signed, (document) async {
        final util = SignatureUtil(document);
        final name = (await util.getSignatureNames()).single;
        expect(await util.getDocMdpPermission(), 1);
        expect(await util.getCertificationSignatureName(), name);
        expect(await util.getCertificationLevel(name),
            AccessPermissions.noChangesPermitted);
        final references = await util.getSignatureReferences(name);
        expect(references, hasLength(1));
        expect(await references.single.getTransformMethod(),
            SignatureTransformMethod.docMdp);
        expect(await references.single.getDocMdpPermission(), 1);
        expect(await util.validateSignature(name), isA<SignatureValidationReport>()
            .having((r) => r.isValid, 'isValid', isTrue));
      });
    });

    test('each certification level lands in the transform parameters',
        () async {
      for (final entry in {
        AccessPermissions.noChangesPermitted: 1,
        AccessPermissions.formFieldsModification: 2,
        AccessPermissions.annotationModification: 3,
      }.entries) {
        final identity = _Identity.create();
        final signed = await _sign(await _blankDocument(), identity,
            certification: entry.key);
        await _withDocument(signed, (document) async {
          expect(await SignatureUtil(document).getDocMdpPermission(),
              entry.value);
        });
      }
    });

    test('level 1 invalidates the certification once another revision is added',
        () async {
      final identity = _Identity.create();
      final certified = await _sign(await _blankDocument(), identity,
          fieldName: 'Certification',
          certification: AccessPermissions.noChangesPermitted);
      final twice =
          await _sign(certified, identity, fieldName: 'Approval');

      await _withDocument(twice, (document) async {
        final util = SignatureUtil(document);
        expect(await util.getSignatureNames(), ['Certification', 'Approval']);
        // The byte range digest of the first signature still matches: the
        // second signature was an incremental update (12.8.1, note 1).
        expect((await util.readSignatureData('Certification'))!.verify(),
            isTrue);
        expect(await util.signatureCoversWholeDocument('Certification'),
            isFalse);
        final report = await util.validateSignature('Certification');
        expect(report.digestValid, isTrue);
        expect(report.issues, contains(SignatureValidationIssue.docMdpViolation));
        expect(report.modifications, isNotNull);
        // The signature applied last always covers the whole file.
        expect(await util.signatureCoversWholeDocument('Approval'), isTrue);
        expect((await util.validateSignature('Approval')).isValid, isTrue);
      });
    });

    test('level 2 tolerates a later signature but not a new page', () async {
      final identity = _Identity.create();
      final certified = await _sign(await _blankDocument(), identity,
          fieldName: 'Certification',
          certification: AccessPermissions.formFieldsModification);
      final twice = await _sign(certified, identity, fieldName: 'Approval');
      await _withDocument(twice, (document) async {
        final report =
            await SignatureUtil(document).validateSignature('Certification');
        expect(report.isValid, isTrue,
            reason: report.modifications?.changes.toString());
      });

      final withExtraPage = await _appendPage(certified);
      await _withDocument(withExtraPage, (document) async {
        final report =
            await SignatureUtil(document).validateSignature('Certification');
        expect(report.issues,
            contains(SignatureValidationIssue.docMdpViolation));
      });
    });

    test('two incremental signatures both verify and keep their revisions',
        () async {
      final identity = _Identity.create();
      final first =
          await _sign(await _blankDocument(), identity, fieldName: 'First');
      final second = await _sign(first, identity, fieldName: 'Second');
      await _withDocument(second, (document) async {
        final util = SignatureUtil(document);
        expect(await util.getSignatureNames(), ['First', 'Second']);
        expect(await util.getRevision('First'), 1);
        expect(await util.getRevision('Second'), 2);
        expect(await util.getTotalRevisions(), 2);
        expect((await util.readSignatureData('First'))!.verify(), isTrue);
        expect((await util.readSignatureData('Second'))!.verify(), isTrue);
        // The revision the first signature covers is the first signed file.
        final revision = (await util.extractRevisionDocument('First'))!;
        expect(revision.length, first.length);
        expect(revision, orderedEquals(first));
        // Table 252: /Changes records the work done since the last signature.
        final changes = await (await util.getSignatureDictionary('Second'))!
            .arrayEntry(PdfName.intern('Changes'));
        expect(changes?.size(), 3);
      });
    });
  });

  group('FieldMDP transform method of ISO 32000-1 12.8.2.4', () {
    test('the field lock action and fields are copied into the signature',
        () async {
      final identity = _Identity.create();
      final lock = PdfSigFieldLock()
        ..setFieldLock(LockAction.include, ['nome']);
      final signed = await _sign(
          await _documentWithTextField('nome', 'antes'), identity,
          fieldName: 'Aprovacao', fieldLock: lock);

      await _withDocument(signed, (document) async {
        final util = SignatureUtil(document);
        final references = await util.getSignatureReferences('Aprovacao');
        expect(references, hasLength(1));
        expect(await references.single.getTransformMethod(),
            SignatureTransformMethod.fieldMdp);
        expect(await references.single.getFieldMdpAction(), LockAction.include);
        expect(await references.single.getFieldMdpFields(), ['nome']);

        final field = (await util.getSignatureFormFieldDictionary('Aprovacao'))!;
        final stored = await field.dictionaryEntry(PdfName.lock);
        expect(stored, isNotNull);
        final wrapper = PdfSigFieldLock.fromDictionary(stored!);
        expect(await wrapper.getFieldLockAction(), LockAction.include);
        expect(await wrapper.getFieldLockFields(), ['nome']);
      });
    });

    test('changing a locked field invalidates the signature that locked it',
        () async {
      final identity = _Identity.create();
      final lock = PdfSigFieldLock()
        ..setFieldLock(LockAction.include, ['nome']);
      final signed = await _sign(
          await _documentWithTextField('nome', 'antes'), identity,
          fieldName: 'Aprovacao', fieldLock: lock);
      final edited = await _editTextField(signed, 'nome', 'depois');

      await _withDocument(edited, (document) async {
        final util = SignatureUtil(document);
        final report = await util.validateSignature('Aprovacao');
        expect(report.digestValid, isTrue);
        expect(report.modifications!.changedFieldValues, contains('nome'));
        expect(report.issues,
            contains(SignatureValidationIssue.fieldMdpViolation));
      });
    });

    test('an Exclude lock leaves the listed field free to change', () async {
      final identity = _Identity.create();
      final lock = PdfSigFieldLock()
        ..setFieldLock(LockAction.exclude, ['nome']);
      final signed = await _sign(
          await _documentWithTextField('nome', 'antes'), identity,
          fieldName: 'Aprovacao', fieldLock: lock);
      final edited = await _editTextField(signed, 'nome', 'depois');

      await _withDocument(edited, (document) async {
        final report =
            await SignatureUtil(document).validateSignature('Aprovacao');
        expect(report.issues,
            isNot(contains(SignatureValidationIssue.fieldMdpViolation)));
      });
    });

    test('locksField follows the All, Include and Exclude actions', () async {
      final all = PdfSigFieldLock()..setFieldLock(LockAction.all, const []);
      expect(await all.locksField('qualquer'), isTrue);
      expect(await all.pdfRepresentation().arrayEntry(PdfName.fields), isNull);

      final include = PdfSigFieldLock()
        ..setFieldLock(LockAction.include, ['a', 'b']);
      expect(await include.locksField('a'), isTrue);
      expect(await include.locksField('a.filho'), isTrue);
      expect(await include.locksField('c'), isFalse);

      final exclude = PdfSigFieldLock()
        ..setFieldLock(LockAction.exclude, ['a']);
      expect(await exclude.locksField('a'), isFalse);
      expect(await exclude.locksField('a.filho'), isFalse);
      expect(await exclude.locksField('c'), isTrue);
    });

    test('the document permissions of table 233 round trip', () async {
      final lock = PdfSigFieldLock()
        ..setDocumentPermissions(LockPermissions.formFillingAndAnnotation);
      expect(await lock.getDocumentPermissions(),
          LockPermissions.formFillingAndAnnotation);
    });
  });

  group('negative validation', () {
    test('a flipped byte inside the byte range breaks the digest', () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity);
      final tampered = Uint8List.fromList(signed);
      tampered[7] = tampered[7] == 55 ? 54 : 55;
      await _withDocument(tampered, (document) async {
        final util = SignatureUtil(document);
        final name = (await util.getSignatureNames()).single;
        expect((await util.readSignatureData(name))!.verify(), isFalse);
        final report = await util.validateSignature(name);
        expect(report.isValid, isFalse);
        expect(report.issues, contains(SignatureValidationIssue.invalidDigest));
      });
    });

    test('a byte range that stops short of the file is not full coverage', () {
      // "<00>" occupies the four bytes at offset 10.
      final source = Uint8List.fromList(
          '0123456789<00>abcdefghij'.codeUnits);
      expect(SignatureUtil.byteRangeCoversDocument([0, 10, 14, 10], source),
          isTrue);
      expect(SignatureUtil.byteRangeCoversDocument([0, 10, 14, 5], source),
          isFalse);
      expect(SignatureUtil.byteRangeCoversDocument([1, 9, 14, 10], source),
          isFalse);
      // The gap has to be the hexadecimal string itself.
      expect(SignatureUtil.byteRangeCoversDocument([0, 9, 14, 10], source),
          isFalse);
      expect(SignatureUtil.byteRangeCoversDocument([0, 10, 15, 9], source),
          isFalse);
      expect(SignatureUtil.byteRangeCoversDocument([0, 10, 14], source),
          isFalse);
    });

    test('trailing end of line bytes still count as full coverage', () {
      final source =
          Uint8List.fromList('0123456789<00>abcdefghij\r\n'.codeUnits);
      expect(SignatureUtil.byteRangeCoversDocument([0, 10, 14, 10], source),
          isTrue);
    });

    test('a non hexadecimal gap is rejected', () {
      final source =
          Uint8List.fromList('0123456789<zz>abcdefghij'.codeUnits);
      expect(SignatureUtil.byteRangeCoversDocument([0, 10, 14, 10], source),
          isFalse);
    });
  });

  group('revision comparison', () {
    test('an appended page is reported as an altered page', () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity);
      final grown = await _appendPage(signed);
      final report = await SignatureModificationAnalyzer.compare(signed, grown);
      expect(report.isEmpty, isFalse);
      expect(report.alteredPages, greaterThan(0));
      expect(report.violationsFor(AccessPermissions.annotationModification),
          isNotEmpty);
      expect(report.violationsFor(AccessPermissions.unspecified), isEmpty);
    });

    test('an untouched incremental save reports no field changes', () async {
      final identity = _Identity.create();
      final signed = await _sign(await _blankDocument(), identity);
      final resaved = await _appendNothing(signed);
      final report =
          await SignatureModificationAnalyzer.compare(signed, resaved);
      expect(report.changedFieldValues, isEmpty);
      expect(report.alteredPages, 0);
    });
  });
}

Future<Uint8List> _appendPage(Uint8List input) async {
  final output = BytesBuilder();
  final document = PdfDocument(
      reader: PdfReader.fromBytes(input),
      writer: PdfWriter.fromBytesBuilder(output),
      properties: StampingProperties()..useAppendMode());
  await document.load();
  await document.appendBlankPage();
  await document.close();
  return output.takeBytes();
}

Future<Uint8List> _appendNothing(Uint8List input) async {
  final output = BytesBuilder();
  final document = PdfDocument(
      reader: PdfReader.fromBytes(input),
      writer: PdfWriter.fromBytesBuilder(output),
      properties: StampingProperties()..useAppendMode());
  await document.load();
  await document.close();
  return output.takeBytes();
}

Future<Uint8List> _editTextField(
    Uint8List input, String name, String value) async {
  final output = BytesBuilder();
  final document = PdfDocument(
      reader: PdfReader.fromBytes(input),
      writer: PdfWriter.fromBytesBuilder(output),
      properties: StampingProperties()..useAppendMode());
  await document.load();
  final form = await PdfAcroForm.getAcroForm(document, false);
  (await form.getField(name))!.setValue(value);
  await document.close();
  return output.takeBytes();
}
