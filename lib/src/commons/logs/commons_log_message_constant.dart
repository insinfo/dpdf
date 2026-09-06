/// Log message constants for commons module.
class CommonsLogMessageConstant {
  CommonsLogMessageConstant._();

  /// Message notifies that base64 encoding or decoding failed.
  static const String base64Exception =
      'Exception during base64 encoding or decoding.';

  /// Invalid statistics name was received.
  static const String invalidStatisticsName =
      'Statistics name {0} is invalid. Cannot find corresponding statistics aggregator.';

  /// Files archiving operation failed.
  static const String localFileCompressionFailed =
      'Cannot archive files into zip. Exception message: {0}.';

  /// Archive is suspicious to be a zip bomb (ratio).
  static const String ratioIsHighlySuspicious =
      'Ratio between compressed and uncompressed data is highly suspicious, '
      'looks like a Zip Bomb Attack. Threshold ratio is {0}.';

  /// Archive is suspicious to be a zip bomb (entries).
  static const String tooMuchEntriesInArchive =
      'Too much entries in this archive, can lead to inodes exhaustion of the system, '
      'looks like a Zip Bomb Attack. Threshold number of file entries is {0}.';

  /// Exception during JSON deserialization.
  static const String unableToDeserializeJson =
      'Unable to deserialize json. Exception {0} was thrown with the message: {1}.';

  /// Exception during JSON serialization.
  static const String unableToSerializeObject =
      'Unable to serialize object. Exception {0} was thrown with the message: {1}.';

  /// Archive is suspicious to be a zip bomb (size).
  static const String uncompressedDataSizeIsTooMuch =
      'The uncompressed data size is too much for the application resource capacity, '
      'looks like a Zip Bomb Attack. Threshold size is {0}.';

  /// Unknown placeholder was ignored during parsing.
  static const String unknownPlaceholderWasIgnored =
      'Unknown placeholder {0} was ignored';

  /// Event is at confirmation stage but not known.
  static const String unreportedEvent =
      'Event for the product {0} with type {1} attempted to be confirmed but it had not been reported yet. '
      'Probably appropriate process fail';
}
