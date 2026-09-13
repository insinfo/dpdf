import 'dart:typed_data';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../forms/pdf_acro_form.dart';
import '../forms/pdf_sig_field_lock.dart';
import 'access_permissions.dart';
import 'pdf_signature.dart';
import 'pdf_signature_reference.dart';
import 'pdf_pkcs7.dart';
import 'signature_modification_analyzer.dart';

/// Why a signature was rejected, ISO 32000-1 12.8.3 and 12.8.2.2.2.
enum SignatureValidationIssue {
  /// The signature dictionary is missing `/Contents`, `/SubFilter` or a well
  /// formed `/ByteRange`.
  malformedSignatureDictionary,

  /// The byte range digest does not match the signed bytes, or the embedded
  /// CMS signature does not verify against the signing certificate.
  invalidDigest,

  /// The byte range leaves bytes of the document outside the digest, so the
  /// signature only attests part of the file.
  incompleteCoverage,

  /// A later revision changed something the DocMDP transform parameters do not
  /// permit.
  docMdpViolation,

  /// A later revision changed a form field that a FieldMDP transform or a
  /// signature field lock dictionary froze.
  fieldMdpViolation,
}

/// The outcome of validating one signature.
class SignatureValidationReport {
  /// Name of the validated signature field.
  final String fieldName;

  /// Whether the byte range digest and the CMS signature verified.
  final bool digestValid;

  /// Whether the byte range spans the whole document except the `/Contents`
  /// hole.
  final bool coversWholeDocument;

  /// The DocMDP access permissions this signature declares.
  final AccessPermissions certificationLevel;

  /// The differences between the signed revision and the current document, or
  /// null when the revision could not be compared.
  final DocumentModificationReport? modifications;

  /// Every reason the signature was rejected; empty when it is valid.
  final List<SignatureValidationIssue> issues;

  /// Human readable detail for each issue, in the same order.
  final List<String> details;

  const SignatureValidationReport({
    required this.fieldName,
    required this.digestValid,
    required this.coversWholeDocument,
    required this.certificationLevel,
    required this.modifications,
    required this.issues,
    required this.details,
  });

  /// True when no issue was found.
  bool get isValid => issues.isEmpty;

  @override
  String toString() => isValid
      ? 'signature $fieldName is valid'
      : 'signature $fieldName: ${details.join('; ')}';
}

/// Queries PDF signature fields and their associated data.
class SignatureUtil {
  final PdfDocument _document;

  // Cached signature names
  Map<String, _SignatureFieldInfo>? _sigNames;
  List<String>? _orderedSignatureNames;
  int _totalRevisions = 0;

  /// Creates a SignatureUtil instance.
  ///
  /// @param document PdfDocument to be inspected
  SignatureUtil(this._document);

  /// Get PdfSignature dictionary based on the provided name.
  ///
  /// @param name signature name
  /// @return PdfSignature instance corresponding to the provided name, null otherwise
  Future<PdfSignature?> getSignature(String name) async {
    final sigDict = await getSignatureDictionary(name);
    if (sigDict != null) {
      return PdfSignature.fromDictionary(sigDict);
    }
    return null;
  }

  /// Gets the signature dictionary, the one keyed by /V.
  ///
  /// @param name the field name
  /// @return the signature dictionary keyed by /V or null if the field is not a signature
  Future<PdfDictionary?> getSignatureDictionary(String name) async {
    final merged = await getSignatureFormFieldDictionary(name);
    if (merged == null) return null;

    final v = await merged.dictionaryEntry(PdfName.v);
    return v;
  }

  /// Gets the signature form field dictionary.
  ///
  /// @param name the field name
  /// @return the form field dictionary or null
  Future<PdfDictionary?> getSignatureFormFieldDictionary(String name) async {
    await getSignatureNames();

    if (_sigNames == null || !_sigNames!.containsKey(name)) {
      return null;
    }

    return _sigNames![name]!.fieldDict;
  }

  /// Lists fields containing populated signatures, in signing order.
  ///
  /// ISO 32000-1 table 252: the ordering of signatures is determined by the
  /// value of `/ByteRange`, because every signature results in an incremental
  /// save and therefore covers more bytes than the previous one.
  ///
  /// @return names of populated signature fields
  Future<List<String>> getSignatureNames() async {
    if (_sigNames != null) {
      return List.from(_orderedSignatureNames!);
    }

    _sigNames = {};
    _orderedSignatureNames = [];

    await _populateSignatureNames();

    return List.from(_orderedSignatureNames!);
  }

  /// Gets the field names that have blank signatures.
  ///
  /// @return names of unsigned signature fields
  Future<List<String>> getBlankSignatureNames() async {
    await getSignatureNames();

    final blankSigs = <String>[];

    try {
      final acroForm = await PdfAcroForm.getAcroForm(_document, false);
      final fields = await acroForm.getFormFields();

      for (final entry in fields.entries) {
        final fieldDict = entry.value.pdfRepresentation();
        final ft = await fieldDict.nameEntry(PdfName.ft);
        if (ft == PdfName.sig) {
          // Check if it has a value
          final v = await fieldDict.dictionaryEntry(PdfName.v);
          if (v == null) {
            blankSigs.add(entry.key);
          }
        }
      }
    } catch (e) {
      // AcroForm might not exist
    }

    return blankSigs;
  }

  /// Get the amount of signed document revisions.
  ///
  /// @return int amount of signed document revisions
  Future<int> getTotalRevisions() async {
    await getSignatureNames();
    return _totalRevisions;
  }

  /// Get signed document revision number, which corresponds to the provided signature name.
  ///
  /// @param field signature name
  /// @return int revision number
  Future<int> getRevision(String field) async {
    await getSignatureNames();

    if (_sigNames == null || !_sigNames!.containsKey(field)) {
      return 0;
    }

    return _sigNames![field]!.revision;
  }

  /// Checks if the signature covers the entire document (except for signature's Contents).
  ///
  /// ISO 32000-1 12.8.1 recommends the byte range to span the entire file
  /// including the signature dictionary but excluding the signature value. The
  /// check therefore requires the range to start at zero, to resume exactly
  /// after the hexadecimal string that holds `/Contents`, and to reach the end
  /// of the file.
  ///
  /// @param name the signature field name
  /// @return whether the signed byte ranges span the whole document
  Future<bool> signatureCoversWholeDocument(String name) async {
    await getSignatureNames();

    final info = _sigNames?[name];
    final byteRange = info?.byteRange;
    if (byteRange == null || byteRange.length != 4) {
      return false;
    }

    final source = _document.inputReader()?.getOriginalBytes();
    if (source == null) return false;

    return byteRangeCoversDocument(byteRange, source);
  }

  /// Checks a `/ByteRange` against the bytes of the document it belongs to.
  ///
  /// The range shall be `[0, gapStart, gapEnd, rest]`, the gap shall hold a
  /// hexadecimal string delimited by `<` and `>`, and `gapEnd + rest` shall
  /// reach the end of the file. Only trailing end of line bytes are tolerated
  /// after the covered region.
  static bool byteRangeCoversDocument(List<int> byteRange, Uint8List source) {
    if (byteRange.length != 4) return false;
    final start = byteRange[0],
        firstLength = byteRange[1],
        gapEnd = byteRange[2],
        secondLength = byteRange[3];
    if (start != 0 || firstLength <= 0 || secondLength < 0) return false;
    if (gapEnd <= firstLength) return false;
    if (gapEnd > source.length) return false;
    if (secondLength > source.length - gapEnd) return false;

    // The gap shall be exactly the hexadecimal string of /Contents.
    if (source[firstLength] != 0x3C || source[gapEnd - 1] != 0x3E) {
      return false;
    }
    for (var index = firstLength + 1; index < gapEnd - 1; index++) {
      if (!_isHexDigit(source[index])) return false;
    }

    final covered = gapEnd + secondLength;
    for (var index = covered; index < source.length; index++) {
      final byte = source[index];
      if (byte != 0x0A && byte != 0x0D && byte != 0x20 && byte != 0x09) {
        return false;
      }
    }
    return true;
  }

  static bool _isHexDigit(int byte) =>
      (byte >= 0x30 && byte <= 0x39) ||
      (byte >= 0x41 && byte <= 0x46) ||
      (byte >= 0x61 && byte <= 0x66);

  /// Checks whether a name exists as a signature field or not.
  ///
  /// @param name name of the field
  /// @return boolean does the signature field exist
  Future<bool> doesSignatureFieldExist(String name) async {
    final blankNames = await getBlankSignatureNames();
    final signedNames = await getSignatureNames();
    return blankNames.contains(name) || signedNames.contains(name);
  }

  /// Prepares a PdfPKCS7 instance for the given signature.
  ///
  /// @param signatureFieldName the signature field name
  /// @return a PdfPKCS7 instance or null
  Future<PdfPKCS7?> readSignatureData(String signatureFieldName) async {
    final signature = await getSignature(signatureFieldName);
    if (signature == null) {
      return null;
    }

    try {
      final sub = await signature.getSubFilter();
      final contents = await signature.getContents();

      if (sub == null || contents == null) {
        return null;
      }

      final contentsBytes = contents.getValueBytes();
      if (contentsBytes == null) {
        return null;
      }
      final ranges = await getByteRange(signatureFieldName);
      final source = _document.inputReader()?.getOriginalBytes();
      if (source == null ||
          ranges == null ||
          ranges.length != 4 ||
          ranges[0] != 0 ||
          ranges[1] < 0 ||
          ranges[2] < ranges[1] ||
          ranges[3] < 0 ||
          ranges[2] > source.length ||
          ranges[3] > source.length - ranges[2]) {
        return null;
      }
      final verifier = PdfPKCS7.forVerifying(contentsBytes, sub);
      verifier.update(source, ranges[0], ranges[1]);
      verifier.update(source, ranges[2], ranges[3]);
      return verifier;
    } catch (e) {
      // Signature parsing failed
      return null;
    }
  }

  /// Reads the `/Reference` array of a signature, ISO 32000-1 table 252.
  ///
  /// @param name the signature field name
  /// @return the signature reference dictionaries, empty when there are none
  Future<List<PdfSignatureReference>> getSignatureReferences(
      String name) async {
    final dictionary = await getSignatureDictionary(name);
    if (dictionary == null) return const [];
    return PdfSignatureReference.readAll(dictionary);
  }

  /// The certification level a signature declares through its DocMDP transform
  /// parameters, ISO 32000-1 12.8.2.2.
  ///
  /// @param name the signature field name
  /// @return the declared access permissions, unspecified for an approval
  ///         signature
  Future<AccessPermissions> getCertificationLevel(String name) async {
    for (final reference in await getSignatureReferences(name)) {
      final permission = await reference.getDocMdpPermission();
      if (permission != null) {
        return PdfSignatureReference.accessPermissionsOf(permission);
      }
    }
    return AccessPermissions.unspecified;
  }

  /// The name of the certification signature of the document, or null when the
  /// document carries none.
  ///
  /// ISO 32000-1 12.8.2.2.1 allows at most one DocMDP signature and requires it
  /// to be the first signed field.
  Future<String?> getCertificationSignatureName() async {
    for (final name in await getSignatureNames()) {
      if (await getCertificationLevel(name) != AccessPermissions.unspecified) {
        return name;
      }
    }
    return null;
  }

  /// The `/P` value of the DocMDP entry of the permissions dictionary, ISO
  /// 32000-1 12.8.4, or null when the document is not certified.
  Future<int?> getDocMdpPermission() async {
    final permissions =
        await _document.rootCatalog().pdfRepresentation().dictionaryEntry(
              PdfName.perms,
            );
    final signature = await permissions?.dictionaryEntry(PdfName.docMDP);
    if (signature == null) return null;
    for (final reference in await PdfSignatureReference.readAll(signature)) {
      final permission = await reference.getDocMdpPermission();
      if (permission != null) return permission;
    }
    return null;
  }

  /// Validates a signature against ISO 32000-1 12.8.3 and 12.8.2.2.2.
  ///
  /// The byte range digest is verified first; the modifications made after the
  /// signed revision are then checked against the DocMDP transform parameters
  /// of the certification signature, against the FieldMDP transform parameters
  /// of this signature and against the signature field lock dictionaries that
  /// were in force when it was applied.
  ///
  /// @param name the signature field name
  /// @return the validation report
  Future<SignatureValidationReport> validateSignature(String name) async {
    final issues = <SignatureValidationIssue>[];
    final details = <String>[];

    final verifier = await readSignatureData(name);
    if (verifier == null) {
      return SignatureValidationReport(
        fieldName: name,
        digestValid: false,
        coversWholeDocument: false,
        certificationLevel: AccessPermissions.unspecified,
        modifications: null,
        issues: const [SignatureValidationIssue.malformedSignatureDictionary],
        details: const ['signature dictionary could not be read'],
      );
    }

    var digestValid = false;
    try {
      digestValid = verifier.verify();
    } catch (_) {
      digestValid = false;
    }
    if (!digestValid) {
      issues.add(SignatureValidationIssue.invalidDigest);
      details.add('the byte range digest does not match the signed bytes');
    }

    final covers = await signatureCoversWholeDocument(name);
    DocumentModificationReport? modifications;
    if (!covers) {
      final source = _document.inputReader()?.getOriginalBytes();
      final revision = await extractRevisionDocument(name);
      if (source != null && revision != null && revision.length < source.length) {
        try {
          modifications =
              await SignatureModificationAnalyzer.compare(revision, source);
        } catch (_) {
          modifications = null;
        }
      }
      if (modifications == null) {
        issues.add(SignatureValidationIssue.incompleteCoverage);
        details.add('the byte range does not cover the whole document');
      }
    }

    final certificationLevel = await getCertificationLevel(name);
    if (modifications != null) {
      final documentLevel = await _effectiveCertificationLevel();
      final violations = modifications.violationsFor(documentLevel);
      if (violations.isNotEmpty) {
        issues.add(SignatureValidationIssue.docMdpViolation);
        details.add('DocMDP level ${_levelNumber(documentLevel)} forbids '
            '${violations.map((v) => v.toString()).join(', ')}');
      }
      final locked = await _lockedFieldsAt(name);
      final touched = modifications.changedFieldValues
          .where((field) => locked.any((lock) =>
              lock == field || field.startsWith('$lock.')))
          .toList();
      if (touched.isNotEmpty) {
        issues.add(SignatureValidationIssue.fieldMdpViolation);
        details.add('locked form fields were changed: ${touched.join(', ')}');
      }
    }

    return SignatureValidationReport(
      fieldName: name,
      digestValid: digestValid,
      coversWholeDocument: covers,
      certificationLevel: certificationLevel,
      modifications: modifications,
      issues: List.unmodifiable(issues),
      details: List.unmodifiable(details),
    );
  }

  Future<AccessPermissions> _effectiveCertificationLevel() async {
    final declared = await getDocMdpPermission();
    if (declared != null) {
      return PdfSignatureReference.accessPermissionsOf(declared);
    }
    final certification = await getCertificationSignatureName();
    if (certification == null) return AccessPermissions.unspecified;
    return getCertificationLevel(certification);
  }

  static int _levelNumber(AccessPermissions permissions) =>
      PdfSignatureReference.docMdpPermissionOf(permissions);

  /// The fully qualified names of the form fields that [name] freezes.
  ///
  /// Both the FieldMDP transform parameters of the signature (12.8.2.4) and
  /// the `/Lock` dictionary of the signature field (table 233) are consulted.
  Future<List<String>> _lockedFieldsAt(String name) async {
    final candidates = <String>{};
    final allFields = <String>{};
    try {
      final acroForm = await PdfAcroForm.getAcroForm(_document, false);
      allFields.addAll((await acroForm.getFormFields()).keys);
    } catch (_) {
      // No interactive form: nothing can be locked.
      return const [];
    }

    Future<void> applyLock(LockAction? action, List<String> fields) async {
      if (action == null) return;
      switch (action) {
        case LockAction.all:
          candidates.addAll(allFields);
          break;
        case LockAction.include:
          candidates.addAll(fields);
          break;
        case LockAction.exclude:
          candidates.addAll(allFields.where((field) => !fields.any(
              (excluded) =>
                  excluded == field || field.startsWith('$excluded.'))));
          break;
      }
    }

    for (final reference in await getSignatureReferences(name)) {
      await applyLock(await reference.getFieldMdpAction(),
          await reference.getFieldMdpFields());
    }

    final field = await getSignatureFormFieldDictionary(name);
    final lockDictionary = await field?.dictionaryEntry(PdfName.lock);
    if (lockDictionary != null) {
      final lock = PdfSigFieldLock.fromDictionary(lockDictionary);
      await applyLock(
          await lock.getFieldLockAction(), await lock.getFieldLockFields());
    }

    // A signature never locks itself out of existence.
    candidates.remove(name);
    return candidates.toList(growable: false);
  }

  /// Populates the signature names from the AcroForm.
  Future<void> _populateSignatureNames() async {
    try {
      final acroForm = await PdfAcroForm.getAcroForm(_document, false);
      final fields = await acroForm.getFormFields();

      final signedFields = <String, _SignatureFieldInfo>{};

      for (final entry in fields.entries) {
        final fieldDict = entry.value.pdfRepresentation();
        final ft = await fieldDict.nameEntry(PdfName.ft);

        if (ft == PdfName.sig) {
          // Check if it has a value (is signed)
          final v = await fieldDict.dictionaryEntry(PdfName.v);
          if (v != null) {
            // Get byte range
            final byteRangeArray = await v.arrayEntry(PdfName.byteRange);
            List<int>? byteRange;

            if (byteRangeArray != null) {
              byteRange = [];
              for (int i = 0; i < byteRangeArray.size(); i++) {
                final num = await byteRangeArray.numberEntry(i);
                if (num != null) {
                  byteRange.add(num.intValue());
                }
              }
            }

            signedFields[entry.key] = _SignatureFieldInfo(
              fieldDict: fieldDict,
              sigDict: v,
              byteRange: byteRange,
              revision: 0, // Will be calculated later
            );
          }
        }
      }

      // Table 252: later signatures cover more bytes, so the covered length
      // orders the revisions.
      final ordered = signedFields.keys.toList()
        ..sort((a, b) {
          final left = _coveredLength(signedFields[a]!.byteRange);
          final right = _coveredLength(signedFields[b]!.byteRange);
          return left != right ? left.compareTo(right) : a.compareTo(b);
        });

      for (var index = 0; index < ordered.length; index++) {
        final info = signedFields[ordered[index]]!;
        _sigNames![ordered[index]] = _SignatureFieldInfo(
          fieldDict: info.fieldDict,
          sigDict: info.sigDict,
          byteRange: info.byteRange,
          revision: index + 1,
        );
      }

      _orderedSignatureNames!.addAll(ordered);
      _totalRevisions = ordered.length;
      if (ordered.isNotEmpty &&
          !await signatureCoversWholeDocument(ordered.last)) {
        // The bytes appended after the last signature form one more revision.
        _totalRevisions++;
      }
    } catch (e) {
      // AcroForm might not exist or other error
      _sigNames = {};
      _orderedSignatureNames = [];
    }
  }

  static int _coveredLength(List<int>? byteRange) =>
      byteRange != null && byteRange.length == 4
          ? byteRange[2] + byteRange[3]
          : 0;

  /// Extracts the bytes a signature actually signed.
  ///
  /// The two segments of the `/ByteRange` are concatenated, so the result is
  /// the input of the digest and not a standalone document. Use
  /// [extractRevisionDocument] to obtain the revision as a readable PDF.
  ///
  /// @param field the signature field name
  /// @return the signed bytes, or null if not a signature field
  Future<Uint8List?> extractRevision(String field) async {
    await getSignatureNames();

    final info = _sigNames?[field];
    final byteRange = info?.byteRange;
    if (byteRange == null || byteRange.length != 4) {
      return null;
    }

    // The revision ends at byteRange[2] + byteRange[3]
    final reader = _document.inputReader();
    if (reader == null) return null;

    final raf = reader.getSafeFile();
    try {
      final length1 = byteRange[1];
      final offset2 = byteRange[2];
      final length2 = byteRange[3];

      final buffer1 = Uint8List(length1);
      final buffer2 = Uint8List(length2);

      raf.seek(byteRange[0]);
      raf.readFully(buffer1);

      raf.seek(offset2);
      raf.readFully(buffer2);

      final result = BytesBuilder(copy: false);
      result.add(buffer1);
      result.add(buffer2);

      return result.toBytes();
    } finally {
      raf.close();
    }
  }

  /// Extracts the document revision a signature covers.
  ///
  /// The result is the prefix of the file that ends where the `/ByteRange`
  /// ends, which is a complete PDF because every later change is an
  /// incremental update (ISO 32000-1 7.5.6 and note 1 of 12.8.1).
  ///
  /// @param field the signature field name
  /// @return the revision bytes, or null if not a signature field
  Future<Uint8List?> extractRevisionDocument(String field) async {
    await getSignatureNames();

    final info = _sigNames?[field];
    final byteRange = info?.byteRange;
    if (byteRange == null || byteRange.length != 4) {
      return null;
    }
    final source = _document.inputReader()?.getOriginalBytes();
    if (source == null) return null;
    final end = byteRange[2] + byteRange[3];
    if (end <= 0 || end > source.length) return null;
    return Uint8List.sublistView(source, 0, end);
  }

  /// Gets the byte range for a signature.
  ///
  /// @param name the signature field name
  /// @return the byte range array, or null
  Future<List<int>?> getByteRange(String name) async {
    await getSignatureNames();

    if (_sigNames == null || !_sigNames!.containsKey(name)) {
      return null;
    }

    return _sigNames![name]!.byteRange;
  }
}

/// Internal class to hold signature field information.
class _SignatureFieldInfo {
  final PdfDictionary fieldDict;
  final PdfDictionary sigDict;
  final List<int>? byteRange;
  final int revision;

  _SignatureFieldInfo({
    required this.fieldDict,
    required this.sigDict,
    this.byteRange,
    required this.revision,
  });
}
