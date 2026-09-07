import 'dart:typed_data';

import 'package:dpdf/src/sign/der_objects.dart';

import 'certificate_details.dart';
import 'oid.dart';
import 'sign_utils.dart';
import '../pki/rsa.dart';
import 'dart:convert';

/// Implementation of CertificateDetails using the local DER parser.
class X509Certificate implements CertificateDetails {
  final Uint8List _encoded;
  late ASN1Sequence _seq;
  late ASN1Sequence _tbsCertificate;
  late ASN1Sequence _signatureAlgorithm;

  X509Certificate(Uint8List encoded) : _encoded = Uint8List.fromList(encoded) {
    _parse();
  }

  void _parse() {
    final parser = ASN1Parser(_encoded);
    final obj = parser.readSingle();
    if (obj is! ASN1Sequence || obj.tag != 0x30) {
      throw FormatException('Not an X.509 certificate: expected SEQUENCE');
    }
    _seq = obj;
    if (_seq.elements == null || _seq.elements!.length != 3) {
      throw FormatException('Invalid X.509 certificate structure');
    }

    // TBSCertificate
    final tbs = _seq.elements![0];
    if (tbs is! ASN1Sequence || tbs.tag != 0x30) {
      throw FormatException('Invalid TBSCertificate');
    }
    _tbsCertificate = tbs;

    // SignatureAlgorithm
    final alg = _seq.elements![1];
    if (alg is! ASN1Sequence || alg.tag != 0x30) {
      throw FormatException('Invalid SignatureAlgorithm');
    }
    _signatureAlgorithm = alg;
    final fields = _getTbsFields();
    final innerAlgorithm = fields['signature'];
    if (fields.length != 6 ||
        fields['serialNumber'] is! ASN1Integer ||
        innerAlgorithm is! ASN1Sequence ||
        !_sameBytes(innerAlgorithm.encode(), alg.encode()) ||
        _seq.elements![2] is! ASN1BitString ||
        version < 1 ||
        version > 3) {
      throw FormatException('Invalid or inconsistent certificate fields');
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Gets the human-readable X.509 version (1, 2, or 3).
  int get version {
    if (_tbsCertificate.elements != null &&
        _tbsCertificate.elements!.isNotEmpty) {
      final first = _tbsCertificate.elements![0];
      if (first.tag == 0xA0) {
        if (first is! ASN1Sequence ||
            first.elements!.length != 1 ||
            first.elements!.first is! ASN1Integer) {
          throw FormatException('Invalid certificate version');
        }
        return (first.elements!.first as ASN1Integer).integer!.toInt() + 1;
      }
    }
    return 1;
  }

  @override
  String getIssuerDN() {
    final fields = _getTbsFields();
    final issuer = fields['issuer'];
    return _name(issuer);
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
    return _name(subject);
  }

  @override
  BigInt getSerialNumber() {
    final fields = _getTbsFields();
    final serial = fields['serialNumber'];
    if (serial is ASN1Integer) {
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
  Uint8List getEncoded() => Uint8List.fromList(_encoded);

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
    final key =
        SignUtils.parsePublicKeyFromSubjectPublicKeyInfo(issuerPublicKey);
    const algorithms = {
      '1.2.840.113549.1.1.5': 'SHA-1/RSA',
      '1.2.840.113549.1.1.11': 'SHA-256/RSA',
      '1.2.840.113549.1.1.12': 'SHA-384/RSA',
      '1.2.840.113549.1.1.13': 'SHA-512/RSA',
    };
    final algorithm = algorithms[getSigAlgOID()];
    if (key == null || algorithm == null) {
      throw UnsupportedError(
          'Certificate signature algorithm is not supported: ${getSigAlgOID()}');
    }
    final signature = _seq.elements![2];
    if (signature is! ASN1BitString || signature.unusedBits != 0) {
      throw FormatException('Invalid certificate signature BIT STRING');
    }
    final signer = Signer(algorithm)..init(false, PublicKeyParameter(key));
    if (!signer.verifySignature(
        getTbsCertificate(), RSASignature(signature.stringValues))) {
      throw FormatException('Certificate signature does not match issuer key');
    }
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
    if (time.isBefore(getNotBefore()) || time.isAfter(getNotAfter())) {
      throw StateError('Certificate is not valid at the requested time');
    }
  }

  @override
  DateTime getNotBefore() {
    return _validityTime(0);
  }

  @override
  DateTime getNotAfter() {
    return _validityTime(1);
  }

  DateTime _validityTime(int index) {
    final validity = _getTbsFields()['validity'];
    if (validity is! ASN1Sequence || validity.elements!.length != 2) {
      throw FormatException('Invalid certificate validity');
    }
    final value = validity.elements![index];
    final text = ascii.decode(value.valueBytes);
    final fullYear = value.tag == 24;
    if ((value.tag != 23 && !fullYear) ||
        !RegExp(fullYear ? r'^\d{14}Z$' : r'^\d{12}Z$').hasMatch(text)) {
      throw FormatException('Invalid certificate UTC time');
    }
    var pos = fullYear ? 4 : 2;
    var year = int.parse(text.substring(0, pos));
    if (!fullYear) year += year >= 50 ? 1900 : 2000;
    int field() {
      final n = int.parse(text.substring(pos, pos + 2));
      pos += 2;
      return n;
    }

    final month = field(),
        day = field(),
        hour = field(),
        minute = field(),
        second = field();
    final result = DateTime.utc(year, month, day, hour, minute, second);
    if (result.year != year ||
        result.month != month ||
        result.day != day ||
        result.hour != hour ||
        result.minute != minute ||
        result.second != second) {
      throw FormatException('Invalid certificate calendar value');
    }
    return result;
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
          return List.generate(obj.stringValues.length * 8 - obj.unusedBits,
              (i) => (obj.stringValues[i ~/ 8] & (128 >> (i % 8))) != 0);
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
          final fields = obj.elements!;
          if (fields.isEmpty ||
              fields.first is! ASN1Boolean ||
              (fields.first as ASN1Boolean).boolValue != true) {
            return -1;
          }
          if (fields.length > 1 && fields[1] is ASN1Integer) {
            final pathLength = (fields[1] as ASN1Integer).integer!;
            if (pathLength < BigInt.zero) {
              throw FormatException('Negative CA path length');
            }
            return pathLength.toInt();
          }
          return 0x7fffffff;
        }
      } catch (e) {}
    }
    return -1;
  }

  @override
  bool isCA() {
    return getBasicConstraints() >= 0;
  }

  String _name(ASN1Object? name) {
    if (name is! ASN1Sequence) {
      throw FormatException('Invalid distinguished name');
    }
    const labels = {
      '2.5.4.3': 'CN',
      '2.5.4.6': 'C',
      '2.5.4.10': 'O',
      '2.5.4.11': 'OU',
      '2.5.4.7': 'L',
      '2.5.4.8': 'ST'
    };
    final rdns = <String>[];
    for (final rdn in name.elements!) {
      if (rdn is! ASN1Set) {
        throw FormatException('Invalid relative distinguished name');
      }
      final attrs = <String>[];
      for (final attr in rdn.elements!) {
        if (attr is! ASN1Sequence ||
            attr.elements!.length != 2 ||
            attr.elements![0] is! ASN1ObjectIdentifier) {
          throw FormatException('Invalid name attribute');
        }
        final oid = (attr.elements![0] as ASN1ObjectIdentifier)
            .objectIdentifierAsString!;
        final value = attr.elements![1];
        final text = value.tag == 30
            ? String.fromCharCodes(List.generate(
                value.valueBytes.length ~/ 2,
                (i) =>
                    (value.valueBytes[i * 2] << 8) |
                    value.valueBytes[i * 2 + 1]))
            : utf8.decode(value.valueBytes, allowMalformed: true);
        attrs.add('${labels[oid] ?? oid}=$text');
      }
      rdns.add(attrs.join('+'));
    }
    return rdns.join(',');
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
