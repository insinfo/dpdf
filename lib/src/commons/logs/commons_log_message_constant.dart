/// Diagnostic templates for DPDF. Public identifiers and format slots are stable.
class CraftCommonsLogMessageConstant {
  CraftCommonsLogMessageConstant._();

  static const String base64Exception =
      'Base64 conversion could not be completed.';

  static const String invalidStatisticsName =
      'No statistics aggregator is registered for name {0}.';

  static const String localFileCompressionFailed =
      'ZIP creation failed while archiving local files: {0}.';

  static const String ratioIsHighlySuspicious =
      'Archive expansion ratio exceeds the configured limit {0}; processing could exhaust resources (possible ZIP bomb).';

  static const String tooMuchEntriesInArchive =
      'Archive entry count exceeds limit {0}; extracting it could exhaust filesystem inodes (possible ZIP bomb).';

  static const String unableToDeserializeJson =
      'JSON decoding failed with {0}: {1}.';

  static const String unableToSerializeObject =
      'Object serialization failed with {0}: {1}.';

  static const String uncompressedDataSizeIsTooMuch =
      'Expanded archive size exceeds resource limit {0}; processing could exhaust memory or storage (possible ZIP bomb).';

  static const String unknownPlaceholderWasIgnored =
      'Skipping unrecognized placeholder {0}.';

  static const String unreportedEvent =
      'Cannot confirm product {0} event {1}: no report was recorded; the reporting operation may have failed.';
}
