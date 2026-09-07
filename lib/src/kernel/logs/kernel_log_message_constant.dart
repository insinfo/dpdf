/// Diagnostic templates for DPDF. Public identifiers and format slots are stable.
class KernelLogMessageConstant {
  KernelLogMessageConstant._();

  static const String corruptedOutlineDictionaryHasInfiniteLoop =
      'Outline object "{0}" has an invalid first/next link; stopping traversal of the remaining entries to avoid a cycle.';

  static const String dctdecodeFilterDecoding =
      'DCTDecode raster decoding is unavailable; retaining the baseline JPEG stream.';

  static const String errorWhileFinalizingAesCipher =
      'The AES cipher could not complete its final block.';

  static const String featureIsNotSupported =
      'XML processing failed with {0}; the processor may lack support for feature {1}.';

  static const String fullCompressionAppendModeXrefTableInconsistency =
      'The original PDF uses an xref table. Incremental output will keep that format and disable the requested full compression.';

  static const String fullCompressionAppendModeXrefStreamInconsistency =
      'The original PDF uses an xref stream. Incremental output will keep that format and enable full compression despite the requested setting.';

  static const String jpxdecodeFilterDecoding =
      'JPXDecode raster decoding is unavailable; retaining the JPEG2000 stream.';

  static const String md5IsNotFipsCompliant =
      'This PDF operation requires MD5, which is outside FIPS-approved hashing algorithms.';

  static const String unableToParseColorWithinColorspace =
      'Color {0} cannot be interpreted using color space {1}.';

  static const String cannotMergeEntry =
      'Merge skipped key {0} because an entry with that key is already present.';

  static const String unknownProductInvolved =
      'Ignoring unrecognized processing product {0}.';

  static const String unconfirmedEvent =
      'Product {0} event {1} was reported without confirmation; processing may have failed.';

  static const String flatteningIsNotYetSupported =
      'Annotation type {0} has no flattening implementation; leaving the annotation on its page.';

  static const String formfieldAnnotationWillNotBeFlattened =
      'Field annotations require PdfAcroForm.flattenFields(); the annotation flattener will leave this field unchanged.';

  static const String invalidDdictionaryFieldValue =
      'Skipping default-configuration field {0}: value {1} does not meet this field\'s requirements.';

  static const String structParentIndexMissedAndRecreated =
      'Assigning a new StructParent index because the tagged object has none.';

  static const String xobjectStructParentIndexMissedAndRecreated =
      'Assigning a new StructParents index because the XObject stream has none.';

  static const String algorithmNotFromSpec =
      'The selected algorithm may not be defined for this PDF version.';

  static const String memorylimitawarehandlerOverrideCreatenewinstanceMethod =
      'Subclasses of MemoryLimitsAwareHandler must implement createNewInstance().';
}
