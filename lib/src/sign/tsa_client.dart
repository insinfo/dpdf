import 'dart:typed_data';

import 'external_digest.dart';

/// Time Stamp Authority client (caller) interface.
///
/// Contract through which the signature builder requests
/// an RFC 3161 token from a timestamp authority.
abstract class TSAClient {
  /// Get the time stamp estimated token size.
  ///
  /// The estimate must reserve enough space for the
  /// entire token returned by [getTimeStampToken] prior to actual
  /// [getTimeStampToken] call.
  ///
  /// @return an estimate of the token size
  int getTokenSizeEstimate();

  /// Returns the [SigningDigest] to digest the data imprint.
  ///
  /// @return The SigningDigest object.
  SigningDigest getMessageDigest();

  /// Returns RFC 3161 timeStampToken.
  ///
  /// @param imprint byte[] - data imprint to be time-stamped
  /// @return encoded timestamp token produced by the authority
  Future<Uint8List> getTimeStampToken(Uint8List imprint);
}
