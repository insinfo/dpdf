import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';

import 'i_x509_certificate.dart';
import 'oid.dart';

/// Implementation of IX509Certificate using PointyCastle ASN.1 parser.
class X509Certificate implements IX509Certificate {
  final Uint8List _encoded;
  late ASN1Sequence _seq;
  late ASN1Sequence _tbsCertificate;
  late ASN1Sequence _signatureAlgorithm;

  X509Certificate(this._encoded) {
    _parse();
  }

  void _parse() {
    final parser = ASN1Parser(_encoded);
    final obj = parser.nextObject();
    if (obj is! ASN1Sequence) {
      throw FormatException('Not an X.509 certificate: expected SEQUENCE');
    }
    _seq = obj;
    if (_seq.elements == null || _seq.elements!.length < 3) {
      throw FormatException('Invalid X.509 certificate structure');
    }

    // TBSCertificate
    final tbs = _seq.elements![0];
    if (tbs is! ASN1Sequence) {
      throw FormatException('Invalid TBSCertificate');
    }
    _tbsCertificate = tbs;

    // SignatureAlgorithm
    final alg = _seq.elements![1];
    if (alg is! ASN1Sequence) {
      throw FormatException('Invalid SignatureAlgorithm');
    }
    _signatureAlgorithm = alg;
  }

  /// Gets the version number (0, 1, or 2).
  int get version {
    if (_tbsCertificate.elements != null &&
        _tbsCertificate.elements!.isNotEmpty) {
      final first = _tbsCertificate.elements![0];
      if (first.tag == 0xA0) {
        // [0] EXPLICIT
        // Pointy Castle might wrap explicit tags
        // For now assume default v1(0) if simple parsing fails
        return 3;
      }
    }
    return 1;
  }

  @override
  String getIssuerDN() {
    final fields = _getTbsFields();
    final issuer = fields['issuer'];
    return issuer.toString();
  }

  @override
  Uint8List getIssuerX500Name() {
    final fields = _getTbsFields();
    final issuer = fields['issuer'];
    if (issuer != null) return issuer.encodedBytes!;
    return Uint8List(0);
  }

  @override
  String getSubjectDN() {
    final fields = _getTbsFields();
    final subject = fields['subject'];
    return subject.toString();
  }

  @override
  BigInt getSerialNumber() {
    final fields = _getTbsFields();
    final serial = fields['serialNumber'];
    if (serial is ASN1Integer) {
      // In PointyCastle 4.0, property is likely 'integer' or 'value'
      // Try 'integer' based on recent PC versions.
      return serial.integer ?? BigInt.zero;
    }
    return BigInt.zero;
  }

  @override
  Uint8List getPublicKey() {
    final fields = _getTbsFields();
    final subjectPublicKeyInfo = fields['subjectPublicKeyInfo'];
    if (subjectPublicKeyInfo is ASN1Sequence) {
      return subjectPublicKeyInfo.encodedBytes!;
    }
    return Uint8List(0);
  }

  @override
  String getSigAlgOID() {
    if (_signatureAlgorithm.elements != null &&
        _signatureAlgorithm.elements!.isNotEmpty) {
      final oid = _signatureAlgorithm.elements![0];
      if (oid is ASN1ObjectIdentifier) {
        return oid.objectIdentifierAsString ?? '';
      }
    }
    return '';
  }

  @override
  String getSigAlgName() {
    return getSigAlgOID();
  }

  @override
  Uint8List? getSigAlgParams() {
    if (_signatureAlgorithm.elements != null &&
        _signatureAlgorithm.elements!.length > 1) {
      final params = _signatureAlgorithm.elements![1];
      if (params is! ASN1Null) {
        return params.encodedBytes;
      }
    }
    return null;
  }

  @override
  Uint8List getEncoded() => _encoded;

  @override
  Uint8List getTbsCertificate() => _tbsCertificate.encodedBytes!;

  @override
  Uint8List? getExtensionValue(String oid) {
    final extensions = _getExtensions();
    if (extensions == null) return null;

    for (final ext in extensions.elements!) {
      if (ext is ASN1Sequence) {
        if (ext.elements!.isNotEmpty) {
          final extnID = ext.elements![0];
          if (extnID is ASN1ObjectIdentifier &&
              extnID.objectIdentifierAsString == oid) {
            ASN1OctetString? value;
            if (ext.elements!.length == 2) {
              if (ext.elements![1] is ASN1OctetString) {
                value = ext.elements![1] as ASN1OctetString;
              }
            } else if (ext.elements!.length == 3) {
              if (ext.elements![2] is ASN1OctetString) {
                value = ext.elements![2] as ASN1OctetString;
              }
            }
            return value?.octets;
          }
        }
      }
    }
    return null;
  }

  @override
  void verify(Uint8List issuerPublicKey) {
    // TODO: Implement verification
    // Use _signatureValue and _tbsCertificate
  }

  @override
  Set<String> getCriticalExtensionOids() {
    final criticals = <String>{};
    final extensions = _getExtensions();
    if (extensions != null) {
      for (final ext in extensions.elements!) {
        if (ext is ASN1Sequence) {
          if (ext.elements!.length == 3) {
            final critical = ext.elements![1];
            if (critical is ASN1Boolean && critical.boolValue == true) {
              final oid = ext.elements![0] as ASN1ObjectIdentifier;
              if (oid.objectIdentifierAsString != null) {
                criticals.add(oid.objectIdentifierAsString!);
              }
            }
          }
        }
      }
    }
    return criticals;
  }

  @override
  void checkValidity(DateTime time) {
    // TODO implementation
  }

  @override
  DateTime getNotBefore() {
    return DateTime.now(); // stub
  }

  @override
  DateTime getNotAfter() {
    return DateTime.now(); // stub
  }

  @override
  Uint8List? getSubjectKeyIdentifier() {
    final val = getExtensionValue(OID.subjectKeyIdentifier);
    if (val == null) return null;
    try {
      final p = ASN1Parser(val);
      final obj = p.nextObject();
      if (obj is ASN1OctetString) {
        return obj.octets;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  @override
  List<String>? getExtendedKeyUsage() {
    final val = getExtensionValue(OID.extendedKeyUsage);
    if (val != null) {
      try {
        final p = ASN1Parser(val);
        final obj = p.nextObject();
        if (obj is ASN1Sequence) {
          return obj.elements
              ?.map(
                  (e) => (e as ASN1ObjectIdentifier).objectIdentifierAsString!)
              .toList();
        }
      } catch (e) {
        // ignore
      }
    }
    return null;
  }

  @override
  List<bool>? getKeyUsage() {
    final val = getExtensionValue(OID.keyUsage);
    if (val != null) {
      try {
        final p = ASN1Parser(val);
        final obj = p.nextObject();
        if (obj is ASN1BitString) {
          // TODO convert bits
        }
      } catch (e) {
        // ignore
      }
    }
    return null;
  }

  @override
  int getBasicConstraints() {
    final val = getExtensionValue(OID.basicConstraints);
    if (val != null) {
      try {
        final p = ASN1Parser(val);
        final obj = p.nextObject();
        if (obj is ASN1Sequence) {
          // TODO parse basic constraints
        }
      } catch (e) {}
    }
    return -1;
  }

  @override
  bool isCA() {
    return getBasicConstraints() >= 0;
  }

  // Helper to get TBS Fields
  Map<String, ASN1Object?> _getTbsFields() {
    final map = <String, ASN1Object?>{};
    if (_tbsCertificate.elements == null) return map;

    var index = 0;
    final tbsElements = _tbsCertificate.elements!;

    // Look for version [0]
    if (index < tbsElements.length && tbsElements[index].tag == 0xA0) {
      index++;
    }

    // serialNumber
    if (index < tbsElements.length) {
      map['serialNumber'] = tbsElements[index];
      index++;
    }

    // signature
    if (index < tbsElements.length) {
      map['signature'] = tbsElements[index];
      index++;
    }

    // issuer
    if (index < tbsElements.length) {
      map['issuer'] = tbsElements[index];
      index++;
    }

    // validity
    if (index < tbsElements.length) {
      map['validity'] = tbsElements[index];
      index++;
    }

    // subject
    if (index < tbsElements.length) {
      map['subject'] = tbsElements[index];
      index++;
    }

    // subjectPublicKeyInfo
    if (index < tbsElements.length) {
      map['subjectPublicKeyInfo'] = tbsElements[index];
      index++;
    }

    return map;
  }

  ASN1Sequence? _getExtensions() {
    final tbsElements = _tbsCertificate.elements!;
    for (int i = 0; i < tbsElements.length; i++) {
      final el = tbsElements[i];
      // Extensions are tagged [3]
      if (el.tag == 0xA3) {
        if (el is ASN1Sequence &&
            el.elements != null &&
            el.elements!.isNotEmpty) {
          final inner = el.elements![0];
          if (inner is ASN1Sequence) {
            return inner;
          }
          // If not wrapping another sequence, maybe it is the sequence itself? (Implicit)
          // But X.509 uses explicit.
          // Let's assume unwrapping is correct.
        }
      }
    }
    return null;
  }
}
