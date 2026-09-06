import 'dart:typed_data';
import 'asn1_utils.dart';
import 'certificate_details.dart';
import 'oid.dart';

/// Utilities for extracting information from X.509 certificates.
class CraftCertificateUtil {
  /// Gets CRL URLs from the certificate's CRL Distribution Points extension.
  static List<String> getCRLURLs(CertificateDetails certificate) {
    final urls = <String>[];
    final extensionValue =
        certificate.getExtensionValue(CraftOID.crlDistributionPoints);
    if (extensionValue == null) return urls;

    try {
      final seq = ASN1Utils.parseSequence(extensionValue);
      for (final dp in seq) {
        if (dp.isSequence) {
          final dpSeq = ASN1Utils.parseElements(dp.content);
          // DistributionPoint ::= SEQUENCE
          for (final el in dpSeq) {
            if (el.isContextSpecific && el.tagNumber == 0) {
              // DistributionPointName ::= CHOICE
              if (el.content.isNotEmpty) {
                final choice = ASN1Utils.parse(el.content);
                if (choice.isContextSpecific && choice.tagNumber == 0) {
                  // fullName [0] GeneralNames
                  final generalNames = ASN1Utils.parseElements(choice.content);
                  for (final gn in generalNames) {
                    if (gn.isContextSpecific && gn.tagNumber == 6) {
                      // URI [6]
                      final uri = String.fromCharCodes(gn.content);
                      urls.add(uri);
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      // ignore parsing errors
    }
    return urls;
  }

  /// Gets the OCSP URL from the certificate's Authority Info Access extension.
  static String? getOCSPURL(CertificateDetails certificate) {
    final extensionValue =
        certificate.getExtensionValue(CraftOID.authorityInfoAccess);
    if (extensionValue == null) return null;
    return _getAIAUrl(extensionValue, CraftOID.ocsp);
  }

  /// Gets the CA Issuer URL from the certificate's Authority Info Access extension.
  static String? getIssuerCertURL(CertificateDetails certificate) {
    final extensionValue =
        certificate.getExtensionValue(CraftOID.authorityInfoAccess);
    if (extensionValue == null) return null;
    return _getAIAUrl(extensionValue, CraftOID.caIssuers);
  }

  static String? _getAIAUrl(Uint8List extensionValue, String accessMethodOid) {
    try {
      final seq = ASN1Utils.parseSequence(extensionValue);
      for (final ad in seq) {
        if (ad.isSequence) {
          final elements = ASN1Utils.parseElements(ad.content);
          if (elements.length == 2 && elements[0].isOid) {
            final oid = ASN1Utils.parseOID(elements[0].content);
            if (oid == accessMethodOid) {
              final gn = elements[1];
              if (gn.isContextSpecific && gn.tagNumber == 6) {
                // URI
                return String.fromCharCodes(gn.content);
              }
            }
          }
        }
      }
    } catch (e) {}
    return null;
  }
}
