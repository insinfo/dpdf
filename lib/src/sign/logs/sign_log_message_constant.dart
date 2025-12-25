/// Sign module log message constants.
class SignLogMessageConstant {
  SignLogMessageConstant._();

  static const String countrySpecificFetchingFailed =
      'Country specific Lotl fetching with schema name "{0}" failed because of:\n "{1}"';

  static const String exceptionWithoutMessage =
      'Unexpected exception without message was thrown during keystore processing';

  static const String unableToParseAiaCert =
      'Unable to parse certificates coming from authority info access extension. '
      'Those won\'t be included into the certificate chain.';

  static const String revocationDataNotAddedValidityAssured =
      'Revocation data for certificate: "{0}" is not added due to validity '
      'assured - short term extension.';

  static const String unableToParseRevInfo =
      'Unable to parse signed data revocation info item since it is incorrect '
      'or unsupported (e.g. SCVP Request and Response).';

  static const String validCertificateIsRevoked =
      'The certificate was valid on the verification date, but has been revoked since {0}.';

  static const String updatingMainLotlToCacheFailed =
      'Unable to update cache with main Lotl file. '
      'Downloading of the main Lotl file failed.\n{0}';

  static const String updatingPivotToCacheFailed =
      'Unable to pivot files because of pivot file fetching failure.\n{0}';

  static const String failedToFetchCountrySpecificLotl =
      'Problem occurred while fetching country specific Lotl files.\n{0}';

  static const String noCountrySpecificLotlFetched =
      'Zero country specific Lotl files were fetched.';

  static const String failedToFetchEuJournalCertificates =
      'Problem occurred while fetching EU Journal certificates.\n{0}';

  static const String ojTransitionPeriod =
      'Main LOTL file contains two Official Journal of European Union links. '
      'This usually indicates that transition period for Official Journal has started. '
      'Newest version of Official Journal should be used from now on '
      'to retrieve trusted certificates and LOTL location.';

  static const String countryNotRequiredByConfiguration =
      'Country "{0}" is not required by lotlFetchingProperties, '
      'and not be used when validating.';
}
