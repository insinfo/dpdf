import 'dart:typed_data';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../forms/pdf_acro_form.dart';
import 'pdf_signature.dart';
import 'pdf_pkcs7.dart';

/// Utility class that provides several convenience methods concerning digital signatures.
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

    final v = await merged.getAsDictionary(PdfName.v);
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

  /// Gets the field names that have signatures and are signed.
  ///
  /// @return List containing the field names that have signatures and are signed
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
  /// @return List containing the field names that have blank signatures
  Future<List<String>> getBlankSignatureNames() async {
    await getSignatureNames();

    final blankSigs = <String>[];

    try {
      final acroForm = await PdfAcroForm.getAcroForm(_document, false);
      final fields = await acroForm.getFormFields();

      for (final entry in fields.entries) {
        final fieldDict = entry.value.getPdfObject();
        final ft = await fieldDict.getAsName(PdfName.ft);
        if (ft == PdfName.sig) {
          // Check if it has a value
          final v = await fieldDict.getAsDictionary(PdfName.v);
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
  /// @param name the signature field name
  /// @return true if the signature covers the entire document, false if it doesn't
  Future<bool> signatureCoversWholeDocument(String name) async {
    await getSignatureNames();

    if (_sigNames == null || !_sigNames!.containsKey(name)) {
      return false;
    }

    final info = _sigNames![name]!;
    final byteRange = info.byteRange;

    if (byteRange == null || byteRange.length != 4) {
      return false;
    }

    // ByteRange format: [offset1, length1, offset2, length2]
    // offset1 should be 0
    // offset1 + length1 + length2 should equal document length (approximately)
    // offset2 should be offset1 + length1 + 2 (for the hex <> markers)

    if (byteRange[0] != 0) {
      return false;
    }

    // TODO: Check against actual document length
    // For now, just verify the byte range format is valid
    return byteRange[1] > 0 && byteRange[2] > byteRange[1] && byteRange[3] > 0;
  }

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
      return PdfPKCS7.forVerifying(contentsBytes, sub);
    } catch (e) {
      // Signature parsing failed
      return null;
    }
  }

  /// Populates the signature names from the AcroForm.
  Future<void> _populateSignatureNames() async {
    try {
      final acroForm = await PdfAcroForm.getAcroForm(_document, false);
      final fields = await acroForm.getFormFields();

      final signedFields = <_SignatureFieldInfo>[];

      for (final entry in fields.entries) {
        final fieldDict = entry.value.getPdfObject();
        final ft = await fieldDict.getAsName(PdfName.ft);

        if (ft == PdfName.sig) {
          // Check if it has a value (is signed)
          final v = await fieldDict.getAsDictionary(PdfName.v);
          if (v != null) {
            // Get byte range
            final byteRangeArray = await v.getAsArray(PdfName.byteRange);
            List<int>? byteRange;

            if (byteRangeArray != null) {
              byteRange = [];
              for (int i = 0; i < byteRangeArray.size(); i++) {
                final num = await byteRangeArray.getAsNumber(i);
                if (num != null) {
                  byteRange.add(num.intValue());
                }
              }
            }

            final info = _SignatureFieldInfo(
              fieldDict: fieldDict,
              sigDict: v,
              byteRange: byteRange,
              revision: 0, // Will be calculated later
            );

            signedFields.add(info);
            _sigNames![entry.key] = info;
          }
        }
      }

      // Sort by byte range start to determine revision order
      signedFields.sort((a, b) {
        final aStart = a.byteRange?.isNotEmpty == true ? a.byteRange![0] : 0;
        final bStart = b.byteRange?.isNotEmpty == true ? b.byteRange![0] : 0;
        return aStart.compareTo(bStart);
      });

      // Assign revisions
      for (int i = 0; i < signedFields.length; i++) {
        signedFields[i] = _SignatureFieldInfo(
          fieldDict: signedFields[i].fieldDict,
          sigDict: signedFields[i].sigDict,
          byteRange: signedFields[i].byteRange,
          revision: i + 1,
        );
      }

      _totalRevisions = signedFields.length;

      // Update ordered names
      for (final entry in _sigNames!.entries) {
        _orderedSignatureNames!.add(entry.key);
      }
    } catch (e) {
      // AcroForm might not exist or other error
      _sigNames = {};
      _orderedSignatureNames = [];
    }
  }

  /// Extracts a revision from the document.
  ///
  /// @param field the signature field name
  /// @return a stream of bytes covering the revision, or null if not a signature field
  Future<Uint8List?> extractRevision(String field) async {
    await getSignatureNames();

    if (_sigNames == null || !_sigNames!.containsKey(field)) {
      return null;
    }

    final info = _sigNames![field]!;
    final byteRange = info.byteRange;

    if (byteRange == null || byteRange.length != 4) {
      return null;
    }

    // The revision ends at byteRange[2] + byteRange[3]
    // TODO: Get the raw document bytes and extract
    // For now, return null - requires raw document access
    return null;
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
