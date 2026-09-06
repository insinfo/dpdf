import 'dart:typed_data';

import 'i_external_digest.dart';

/// Time Stamp Authority client (caller) interface.
///
/// Interface used by the PdfPKCS7 digital signature builder to call
/// Time Stamp Authority providing RFC 3161 compliant time stamp token.
abstract class ITSAClient {
  /// Get the time stamp estimated token size.
  ///
  /// Implementation must return value large enough to accommodate the
  /// entire token returned by [getTimeStampToken] prior to actual
  /// [getTimeStampToken] call.
  ///
  /// @return an estimate of the token size
  int getTokenSizeEstimate();

  /// Returns the [IMessageDigest] to digest the data imprint.
  ///
  /// @return The IMessageDigest object.
  IMessageDigest getMessageDigest();

  /// Returns RFC 3161 timeStampToken.
  ///
  /// @param imprint byte[] - data imprint to be time-stamped
  /// @return byte[] - encoded, TSA signed data of the timeStampToken
  Future<Uint8List> getTimeStampToken(Uint8List imprint);
}
