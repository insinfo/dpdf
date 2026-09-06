/// Diagnostic templates for PDFCraft. Public identifiers and format slots are stable.
class CraftSignLogMessageConstant {
  CraftSignLogMessageConstant._();

  static const String countrySpecificFetchingFailed =
      'Fetching the national LOTL for schema "{0}" failed: {1}.';

  static const String exceptionWithoutMessage =
      'Keystore processing raised an exception with no diagnostic message.';

  static const String unableToParseAiaCert =
      'Certificates from the Authority Information Access extension could not be decoded; omitting them from the chain.';

  static const String revocationDataNotAddedValidityAssured =
      'Certificate "{0}" declares the short-term validity-assured extension; omitting its revocation data.';

  static const String unableToParseRevInfo =
      'SignedData contains malformed or unsupported revocation information; SCVP request/response items cannot be parsed here.';

  static const String validCertificateIsRevoked =
      'The certificate was valid at the verification time but was subsequently revoked on {0}.';

  static const String updatingMainLotlToCacheFailed =
      'The main LOTL download failed, so its cache entry was not updated: {0}.';

  static const String updatingPivotToCacheFailed =
      'Pivot processing stopped because a pivot file could not be fetched: {0}.';

  static const String failedToFetchCountrySpecificLotl =
      'Fetching national LOTL files failed: {0}.';

  static const String noCountrySpecificLotlFetched =
      'No national LOTL files were retrieved.';

  static const String failedToFetchEuJournalCertificates =
      'Fetching EU Official Journal certificates failed: {0}.';

  static const String ojTransitionPeriod =
      'Two EU Official Journal links appear in the main LOTL, indicating a possible transition. Use the newer journal for trusted certificates and the LOTL address.';

  static const String countryNotRequiredByConfiguration =
      'Country "{0}" is excluded by lotlFetchingProperties and will not participate in validation.';
}
