/// Diagnostic templates for PDFCraft. Public identifiers and format slots are stable.
class CraftSignExceptionMessageConstant {
  CraftSignExceptionMessageConstant._();

  static const String algorithmsNotSupported =
      'The signing combination {0} with {1} is unsupported.';

  static const String authenticatedAttributeIsMissingTheDigest =
      'The authenticated attributes do not contain a message digest.';

  static const String availableSpaceIsNotEnoughForSignature =
      'The reserved signature region is smaller than the signature data.';

  static const String tokenEstimationSizeIsNotLargeEnough =
      'The timestamp token needs {1} bytes, exceeding the {0}-byte reservation.';

  static const String cannotDecodePkcs7SignedDataObject =
      'The PKCS#7 SignedData structure could not be decoded.';

  static const String cannotFindSigningCertificateWithThisSerial =
      'No signing certificate matches serial number {0}.';

  static const String cannotBeVerifiedCertificateChain =
      'Verification failed against both the keystore and the supplied certificate chain.';

  static const String
      certificationSignatureCreationFailedDocShallNotContainSigs =
      'A certification signature requires a document with no existing certification or approval signatures.';

  static const String certificateTemplateForExceptionMessage =
      'Certificate {0} could not be processed: {1}.';

  static const String defaultClientsCannotBeCreated =
      'The signing certificate provides no revocation endpoints for default OCSP/CRL clients; supply an explicit OCSP or CRL client.';

  static const String dictionaryThisKeyIsNotAName =
      'Dictionary entry {0} must have a PDF name value.';

  static const String digestAlgorithmsAreNotSame =
      'Digest mismatch: CMSContainer uses "{0}" while IExternalSignature uses "{1}"; both must select the same digest.';

  static const String documentAlreadyPreClosed =
      'The document has already completed signature pre-close.';

  static const String documentMustBePreClosed =
      'Complete signature pre-close before this operation.';

  static const String documentMustHaveReader =
      'Signing requires a document backed by a PDF reader.';

  static const String failedToGetTsaResponse =
      'No TSA response could be obtained from {0}.';

  static const String fieldAlreadySigned =
      'The selected signature field already contains a signature.';

  static const String fieldNamesCannotContainADot =
      'A signature field name must not include a period.';

  static const String fieldTypeIsNotASignatureFieldType =
      'The selected field is not a signature field.';

  static const String invalidHttpResponse =
      'The HTTP response is invalid: {0}.';

  static const String invalidStateWhileCheckingCertChain =
      'Certificate-chain traversal reached an invalid state, possibly because the chain is cyclic.';

  static const String invalidTsaResponse =
      'TSA {0} returned an invalid response status {1}.';

  static const String noCryptoDictionaryDefined =
      'A signature cryptographic dictionary has not been configured.';

  static const String noRevocationDataForSigningCertificate =
      'The signing certificate is revoked, or neither OCSP nor CRL status data is available.';

  static const String noSignaturesToProlong =
      'The document has no signatures eligible for prolongation.';

  static const String notAValidPkcs7ObjectNotASequence =
      'PKCS#7 decoding requires an ASN.1 sequence at the root.';

  static const String notAValidPkcs7ObjectNotSignedData =
      'The PKCS#7 content type is not SignedData.';

  static const String notEnoughSpace =
      'The allocated signature placeholder cannot hold the encoded signature.';

  static const String notPossibleToEmbedMacToSignature =
      'Embedding the MAC token failed; check whether the signature container is empty.';

  static const String pathIsNotDirectory =
      'Temporary signing files require a directory, but {0} is not a directory path.';

  static const String providedTsaClientIsNull =
      'Timestamp signing requires a TSA client; none was supplied.';

  static const String signatureWithThisNameIsNotTheLast =
      'Signature {0} is not the final document signature and does not cover the complete current document.';

  static const String thereIsNoFieldInTheDocumentWithSuchName =
      'The document has no field named {0}.';

  static const String thisPkcs7ObjectHasMultipleSignerInfos =
      'PKCS#7 contains multiple SignerInfos; this implementation accepts one.';

  static const String thisInstanceOfPdfSignerAlreadyClosed =
      'This PDF signer has finished and cannot be reused.';

  static const String thisTsaFailedToReturnTimeStampToken =
      'TSA {0} did not provide a timestamp token: {1}.';

  static const String tooBigKey =
      'The cryptographic key exceeds the supported size.';

  static const String tsaClientIsMissing =
      'This PAdES level requires an ITSAClient; configure one with setTSAClient().';

  static const String unexpectedCloseBracket =
      'A closing bracket appeared outside its matching structure.';

  static const String unexpectedGtGt =
      'A dictionary terminator (>>) appeared at an invalid position.';

  static const String unknownHashAlgorithm =
      'Hash algorithm {0} is unrecognized.';

  static const String couldNotDetermineSignatureMechanismOid =
      'No signature-mechanism OID was found for algorithm {0} and digest {1}.';

  static const String verificationAlreadyOutput =
      'Verification results have already been emitted.';

  static const String algoRequiresSpecificHash =
      'Algorithm {0} requires digest {1}; the supplied digest is {2}.';

  static const String onlyMgf1SupportedInRsassaPss =
      'RSASSA-PSS supports MGF1 here; other mask-generation functions are unavailable.';

  static const String rsassaPssDigestMismatch =
      'RSASSA-PSS parameters select digest {0}, conflicting with the active digest {1}.';

  static const String digestAlgorithmMgfMismatch =
      'MGF1 parameters select digest {0}, conflicting with the active digest {1}.';

  static const String invalidArguments =
      'The supplied arguments do not satisfy this operation\'s requirements.';

  static const String cmsSignerInfoReadonly =
      'Signed attributes are immutable after SignerInfo serialization or construction from serialized data.';

  static const String cmsSignerInfoNotInitialized =
      'Initialize the CMS signer information before using it.';

  static const String cmsInvalidContainerStructure =
      'The supplied bytes do not describe a CMS container.';

  static const String cmsOnlyOneSignerAllowed =
      'A CMS container supports exactly one signer in this implementation.';

  static const String cmsCertificateNotFound =
      'The certificate list does not include the signer\'s certificate.';

  static const String cmsMissingCertificates =
      'The CMS certificate set must include at least the signing certificate.';

  static const String failedToRetrieveCertificate =
      'No certificates could be decoded from the supplied bytes.';

  static const String certificateHashMismatch =
      'The calculated hash does not match certificate {0}.';

  static const String certificateHashNull =
      'A certificate hash is required but was not provided.';
}
