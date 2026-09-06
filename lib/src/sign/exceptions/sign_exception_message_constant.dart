/// Sign module exception message constants.
class SignExceptionMessageConstant {
  SignExceptionMessageConstant._();

  static const String algorithmsNotSupported =
      'Signing algorithms {0} and {1} are not supported.';

  static const String authenticatedAttributeIsMissingTheDigest =
      'Authenticated attribute is missing the digest.';

  static const String availableSpaceIsNotEnoughForSignature =
      'Available space is not enough for signature.';

  static const String tokenEstimationSizeIsNotLargeEnough =
      'Timestamp token estimation size is not large enough to accommodate the '
      'entire timestamp token. Timestamp token estimation size is: {0} bytes, '
      'however real timestamp token size is: {1} bytes.';

  static const String cannotDecodePkcs7SignedDataObject =
      'Cannot decode PKCS#7 SignedData object.';

  static const String cannotFindSigningCertificateWithThisSerial =
      'Cannot find signing certificate with serial {0}.';

  static const String cannotBeVerifiedCertificateChain =
      'Cannot be verified against the KeyStore or the certificate chain.';

  static const String
      certificationSignatureCreationFailedDocShallNotContainSigs =
      'Certification signature creation failed. Document shall not contain any '
      'certification or approval signatures before signing with certification signature.';

  static const String certificateTemplateForExceptionMessage =
      'Certificate {0} failed: {1}';

  static const String defaultClientsCannotBeCreated =
      'Default implementation of OCSP and CRL clients cannot be created, '
      'because signing certificate doesn\'t contain revocation data sources. '
      'Please try to explicitly add OCSP or CRL client.';

  static const String dictionaryThisKeyIsNotAName =
      'Dictionary key {0} is not a name.';

  static const String digestAlgorithmsAreNotSame =
      'Digest algorithm used in the provided IExternalSignature shall be the '
      'same as digest algorithm in the provided CMSContainer. Digest algorithm '
      'in CMS container: "{0}". Digest algorithm in IExternalSignature: "{1}"';

  static const String documentAlreadyPreClosed =
      'Document has been already pre closed.';

  static const String documentMustBePreClosed = 'Document must be preClosed.';

  static const String documentMustHaveReader = 'Document must have reader.';

  static const String failedToGetTsaResponse =
      'Failed to get TSA response from {0}.';

  static const String fieldAlreadySigned = 'Field has been already signed.';

  static const String fieldNamesCannotContainADot =
      'Field names cannot contain a dot.';

  static const String fieldTypeIsNotASignatureFieldType =
      'Field type is not a signature field type.';

  static const String invalidHttpResponse = 'Invalid http response {0}.';

  static const String invalidStateWhileCheckingCertChain =
      'Invalid state. Possible circular certificate chain.';

  static const String invalidTsaResponse = 'Invalid TSA {0} response code {1}.';

  static const String noCryptoDictionaryDefined =
      'No crypto dictionary defined.';

  static const String noRevocationDataForSigningCertificate =
      'Neither ocsp nor crl data are available for the signing certificate '
      'or certificate is revoked.';

  static const String noSignaturesToProlong =
      'Document doesn\'t contain any signatures to prolong.';

  static const String notAValidPkcs7ObjectNotASequence =
      'Not a valid PKCS#7 object - not a sequence';

  static const String notAValidPkcs7ObjectNotSignedData =
      'Not a valid PKCS#7 object - not signed data.';

  static const String notEnoughSpace =
      'Not enough space allocated for the signature.';

  static const String notPossibleToEmbedMacToSignature =
      'It was not possible to embed MAC token into signature. '
      'Most likely signature container is empty.';

  static const String pathIsNotDirectory =
      'Provided path: {0} is not a directory. Please provide a directory path '
      'to store temporary pdf files which are required for signing.';

  static const String providedTsaClientIsNull =
      'Provided TSA client is null. TSA client is required for timestamp signing.';

  static const String signatureWithThisNameIsNotTheLast =
      'Signature with name {0} is not the last. It doesn\'t cover the whole document.';

  static const String thereIsNoFieldInTheDocumentWithSuchName =
      'There is no field in the document with such name: {0}.';

  static const String thisPkcs7ObjectHasMultipleSignerInfos =
      'This PKCS#7 object has multiple SignerInfos. Only one is supported at this time.';

  static const String thisInstanceOfPdfSignerAlreadyClosed =
      'This instance of PdfSigner has been already closed.';

  static const String thisTsaFailedToReturnTimeStampToken =
      'TSA {0} failed to return time stamp token: {1}.';

  static const String tooBigKey = 'The key is too big.';

  static const String tsaClientIsMissing =
      'ITSAClient must be present to reach this PAdES level. '
      'Please use setTSAClient method to provide it.';

  static const String unexpectedCloseBracket = 'Unexpected close bracket.';

  static const String unexpectedGtGt = 'unexpected >>.';

  static const String unknownHashAlgorithm = 'Unknown hash algorithm: {0}.';

  static const String couldNotDetermineSignatureMechanismOid =
      'Could not determine OID for signature algorithm {0} with digest {1}.';

  static const String verificationAlreadyOutput =
      'Verification already output.';

  static const String algoRequiresSpecificHash =
      '{0} requires the document to be digested using {1}, not {2}';

  static const String onlyMgf1SupportedInRsassaPss =
      'Only MGF1 is supported in RSASSA-PSS';

  static const String rsassaPssDigestMismatch =
      'Digest algorithm in RSASSA-PSS parameters is {0} while ambient digest algorithm is {1}';

  static const String digestAlgorithmMgfMismatch =
      'Digest algorithm in MGF1 parameters is {0} while ambient digest algorithm is {1}';

  static const String invalidArguments = 'Invalid parameters provided.';

  static const String cmsSignerInfoReadonly =
      'Updating the signed attributes of this SignerInfo instance is not '
      'possible because it has been serialized or been initiated from a serialized version.';

  static const String cmsSignerInfoNotInitialized =
      'Signer info is not yet initialized';

  static const String cmsInvalidContainerStructure =
      'Provided data is not a CMS container';

  static const String cmsOnlyOneSignerAllowed =
      'Only one signer per CMS container is allowed';

  static const String cmsCertificateNotFound =
      'Signer certificate not found in list of certificates';

  static const String cmsMissingCertificates =
      'The certificate set must at least contains the signer certificate';

  static const String failedToRetrieveCertificate =
      'Failed to retrieve certificates from binary data.';

  static const String certificateHashMismatch =
      'Certificate {0} hash mismatch.';

  static const String certificateHashNull = 'Hash was null.';
}
