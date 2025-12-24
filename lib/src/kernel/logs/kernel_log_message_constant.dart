/// Log message constants for Kernel module.
class KernelLogMessageConstant {
  KernelLogMessageConstant._();

  static const String corruptedOutlineDictionaryHasInfiniteLoop =
      'Document outline dictionary is corrupted: some outline (PDF object: "{0}") has wrong first/next link entry. '
      'Next outlines in this dictionary will be unprocessed.';

  static const String dctdecodeFilterDecoding =
      'DCTDecode filter decoding into the bit map is not supported. The stream data would be left in JPEG baseline format';

  static const String errorWhileFinalizingAesCipher =
      'Exception finalizing AES cipher.';

  static const String featureIsNotSupported =
      'Exception was thrown: {0}. The feature {1} is probably not supported by your XML processor.';

  static const String fullCompressionAppendModeXrefTableInconsistency =
      'Full compression mode requested in append mode but the original document has cross-reference table, '
      'not cross-reference stream. Falling back to cross-reference table in appended document and switching full compression off';

  static const String fullCompressionAppendModeXrefStreamInconsistency =
      'Full compression mode was requested to be switched off in append mode but the original document has '
      'cross-reference stream, not cross-reference table. Falling back to cross-reference stream in appended document and switching full compression on';

  static const String jpxdecodeFilterDecoding =
      'JPXDecode filter decoding into the bit map is not supported. The stream data would be left in JPEG2000 format';

  static const String md5IsNotFipsCompliant =
      'MD5 hash algorithm is not FIPS compliant. However we still use this algorithm since it is required according to the PDF specification.';

  static const String unableToParseColorWithinColorspace =
      'Unable to parse color {0} within {1} color space';

  static const String cannotMergeEntry =
      'Cannot merge entry {0}, entry with such key already exists.';

  static const String unknownProductInvolved =
      'Unknown product {0} was involved into PDF processing. It will be ignored';

  static const String unconfirmedEvent =
      'Event for the product {0} with type {1} was reported but was not confirmed. Probably appropriate process fail';

  static const String flatteningIsNotYetSupported =
      'Flattening annotation type {0} is not yet supported, it will not be removed from the page';

  static const String formfieldAnnotationWillNotBeFlattened =
      'Form field annotation flattening is not supported. Use the PdfAcroForm#flattenFields() method instead.';

  static const String invalidDdictionaryFieldValue =
      'The default configuration dictionary field {0} has a value of {1}, which is not the required value for this field. The field will not be processed.';

  static const String structParentIndexMissedAndRecreated =
      'StructParent index not found in tagged object, so index is recreated.';

  static const String xobjectStructParentIndexMissedAndRecreated =
      'XObject has no StructParents index in its stream, so index is recreated';

  static const String fingerprintDisabledButNoRequiredLicence =
      'Fingerprint disabling is only available in non AGPL mode. Fingerprint will be added at the end of the document.';

  static const String algorithmNotFromSpec =
      'Requested algorithm might not be supported by the pdf specification.';

  static const String memorylimitawarehandlerOverrideCreatenewinstanceMethod =
      'MemoryLimitsAwareHandler#createNewInstance method must be overriden.';
}
