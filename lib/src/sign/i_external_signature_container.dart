import 'dart:typed_data';

import '../kernel/pdf/pdf_dictionary.dart';

/// Interface to sign a document.
///
/// The signing is fully done externally, including the container composition.
abstract class IExternalSignatureContainer {
  /// Produces the container with the signature.
  ///
  /// @param data the data to sign (as a stream of bytes)
  /// @return a container with the signature and other objects, like CRL and OCSP.
  ///         The container will generally be a PKCS7 one.
  Future<Uint8List> sign(Stream<List<int>> data);

  /// Modifies the signature dictionary to suit the container.
  ///
  /// At least the keys PdfName.Filter and PdfName.SubFilter will have to be set.
  ///
  /// @param signDic the signature dictionary
  void modifySigningDictionary(PdfDictionary signDic);
}
