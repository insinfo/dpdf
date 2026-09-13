import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

/// Names used by the encryption dictionaries of ISO 32000-1:2008, 7.6, that
/// the shared [PdfName] registry does not expose yet.
class EncryptionNames {
  EncryptionNames._();

  /// `/Recipients`, Tables 23 and 27.
  static final PdfName recipients = PdfName.intern('Recipients');

  /// `/SubFilter` values of 7.6.4.2.
  static final PdfName adbePkcs7s3 = PdfName.intern('adbe.pkcs7.s3');
  static final PdfName adbePkcs7s4 = PdfName.intern('adbe.pkcs7.s4');
  static final PdfName adbePkcs7s5 = PdfName.intern('adbe.pkcs7.s5');

  /// `/Filter` value of the public-key security handler preferred by 7.6.4.2.
  static final PdfName adobePubSec = PdfName.intern('Adobe.PubSec');

  /// The crypt filter names 7.6.3.1 reserves for public-key handlers.
  static final PdfName defaultCryptFilter =
      PdfName.intern('DefaultCryptFilter');
  static final PdfName defEmbeddedFile = PdfName.intern('DefEmbeddedFile');

  /// `/Type` of a crypt filter dictionary, Table 25.
  static final PdfName cryptFilter = PdfName.intern('CryptFilter');

  /// `/Type` of a Crypt filter decode parameters dictionary, Table 14.
  static final PdfName cryptFilterDecodeParms =
      PdfName.intern('CryptFilterDecodeParms');

  /// `/Name` of a Crypt filter decode parameters dictionary, Table 14.
  static final PdfName name = PdfName.intern('Name');

  /// The `None` crypt filter method of Table 25.
  static final PdfName none = PdfName.intern('None');
}

/// Crypt filter methods of ISO 32000-1:2008, Table 25, extended with the
/// `AESV3` method introduced by Adobe Extension Level 3 and adopted by
/// ISO 32000-2.
enum CryptFilterMethod {
  /// `None`: the conforming reader shall not decrypt the data but shall direct
  /// the input stream to the security handler for decryption.
  none,

  /// `V2`: RC4, keyed through "Algorithm 1".
  v2,

  /// `AESV2`: AES-128 in CBC mode, keyed through "Algorithm 1".
  aesV2,

  /// `AESV3`: AES-256 in CBC mode; the file encryption key is used as is.
  aesV3,

  /// The standard `Identity` filter of Table 26: data passes through.
  identity,
}

/// A crypt filter, as described by ISO 32000-1:2008, 7.6.5 "Crypt Filters".
///
/// Instances model both the entries common to every crypt filter dictionary
/// (Table 25) and the additional entries used by public-key security handlers
/// (Table 27).
class CryptFilter {
  /// The name under which the filter appears in `/CF`, or one of the standard
  /// names of Table 26.
  final PdfName name;

  /// The `/CFM` method. Table 25 gives `None` as the default value.
  final CryptFilterMethod method;

  /// The raw `/Length` entry, or `null` when the filter omits it.
  ///
  /// Table 25 notes that the standard security handler "expresses the length
  /// in multiples of 8 (16 means 128)" while the public-key security handler
  /// "expresses it as is (128 means 128)". [keyLengthInBits] normalises both.
  final int? length;

  /// The `/AuthEvent` entry; `DocOpen` by default.
  final PdfName authEvent;

  /// The `/EncryptMetadata` entry of Table 27; `true` by default.
  final bool encryptMetadata;

  /// The `/Recipients` entry of Table 27: binary-encoded PKCS#7 objects.
  final List<Uint8List> recipients;

  CryptFilter({
    required this.name,
    required this.method,
    this.length,
    PdfName? authEvent,
    this.encryptMetadata = true,
    List<Uint8List>? recipients,
  })  : authEvent = authEvent ?? PdfName.docOpen,
        recipients = List.unmodifiable(recipients ?? const <Uint8List>[]);

  /// The standard `Identity` filter of Table 26.
  static final CryptFilter identity =
      CryptFilter(name: PdfName.identity, method: CryptFilterMethod.identity);

  /// Whether this filter passes the input data through without processing.
  bool get isIdentity => method == CryptFilterMethod.identity;

  /// Normalises [length] into a key length expressed in bits.
  ///
  /// AESV3 keys are always 256 bits, whatever the dictionary claims.
  int keyLengthInBits(int defaultBits) {
    if (method == CryptFilterMethod.aesV3) return 256;
    final declared = length;
    if (declared == null) return defaultBits;
    return declared <= 64 ? declared * 8 : declared;
  }

  /// Parses a `/CFM` name into a [CryptFilterMethod].
  static CryptFilterMethod methodFromName(PdfName? cfm) {
    if (cfm == null) return CryptFilterMethod.none;
    switch (cfm.getValue()) {
      case 'None':
        return CryptFilterMethod.none;
      case 'V2':
        return CryptFilterMethod.v2;
      case 'AESV2':
        return CryptFilterMethod.aesV2;
      case 'AESV3':
        return CryptFilterMethod.aesV3;
      case 'Identity':
        return CryptFilterMethod.identity;
      default:
        // Table 25: "Applications that encounter other values shall report
        // that the file is encrypted with an unsupported algorithm."
        throw PdfException(
            KernelExceptionMessageConstant.noCompatibleEncryptionFound);
    }
  }

  /// Renders a [CryptFilterMethod] back into its `/CFM` name.
  static PdfName nameFromMethod(CryptFilterMethod method) {
    switch (method) {
      case CryptFilterMethod.none:
        return EncryptionNames.none;
      case CryptFilterMethod.v2:
        return PdfName.v2;
      case CryptFilterMethod.aesV2:
        return PdfName.aesV2;
      case CryptFilterMethod.aesV3:
        return PdfName.aesV3;
      case CryptFilterMethod.identity:
        return PdfName.identity;
    }
  }

  /// Reads a single crypt filter dictionary (Tables 25 and 27).
  static Future<CryptFilter> fromDictionary(
      PdfName name, PdfDictionary dictionary) async {
    final recipients = <Uint8List>[];
    final recipientsEntry =
        await dictionary.get(EncryptionNames.recipients, true);
    if (recipientsEntry is PdfArray) {
      for (var i = 0; i < recipientsEntry.size(); i++) {
        final entry = await recipientsEntry.get(i);
        if (entry is PdfString) {
          recipients.add(entry.getValueBytes() ?? Uint8List(0));
        }
      }
    } else if (recipientsEntry is PdfString) {
      recipients.add(recipientsEntry.getValueBytes() ?? Uint8List(0));
    }
    final lengthEntry = await dictionary.numberEntry(PdfName.length);
    final encryptMetadata =
        await dictionary.booleanEntry(PdfName.encryptMetadata);
    return CryptFilter(
      name: name,
      method: methodFromName(await dictionary.nameEntry(PdfName.cfm)),
      length: lengthEntry?.intValue(),
      authEvent: await dictionary.nameEntry(PdfName.authEvent),
      encryptMetadata: encryptMetadata?.getValue() ?? true,
      recipients: recipients,
    );
  }

  /// Serialises the filter into a crypt filter dictionary (Tables 25 and 27).
  PdfDictionary toDictionary() {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, EncryptionNames.cryptFilter);
    dictionary.put(PdfName.cfm, nameFromMethod(method));
    dictionary.put(PdfName.authEvent, authEvent);
    if (length != null) {
      dictionary.put(PdfName.length, PdfNumber.fromInt(length!));
    }
    if (recipients.isNotEmpty) {
      final array = PdfArray();
      for (final recipient in recipients) {
        array.add(PdfString.fromBytes(recipient, true));
      }
      dictionary.put(EncryptionNames.recipients, array);
      if (!encryptMetadata) {
        dictionary.put(PdfName.encryptMetadata, PdfBoolean.pdfFalse);
      }
    }
    return dictionary;
  }
}

/// The resolved crypt filter configuration of an encryption dictionary: the
/// `/CF` map plus the `/StmF`, `/StrF` and `/EFF` selections of Table 20.
class CryptFilterConfiguration {
  /// Every named filter of the `/CF` dictionary.
  final Map<String, CryptFilter> filters;

  /// The default filter for streams (`/StmF`); `Identity` when absent.
  final CryptFilter streamFilter;

  /// The default filter for strings (`/StrF`); `Identity` when absent.
  final CryptFilter stringFilter;

  /// The filter for embedded file streams (`/EFF`).
  ///
  /// Table 20: when the entry is absent and an embedded file stream carries no
  /// crypt filter specifier of its own, the stream is encrypted with the
  /// default stream filter named by `/StmF`.
  final CryptFilter embeddedFileFilter;

  CryptFilterConfiguration({
    required this.filters,
    required this.streamFilter,
    required this.stringFilter,
    required this.embeddedFileFilter,
  });

  /// The configuration implied by `/V` values below 4, where a single
  /// algorithm covers strings, streams and embedded files alike.
  factory CryptFilterConfiguration.uniform(CryptFilter filter) {
    return CryptFilterConfiguration(
      filters: {filter.name.getValue(): filter},
      streamFilter: filter,
      stringFilter: filter,
      embeddedFileFilter: filter,
    );
  }

  /// Looks a filter up by name, honouring the standard `Identity` name.
  CryptFilter? byName(PdfName? name) {
    if (name == null) return null;
    if (name.getValue() == PdfName.identity.getValue()) {
      return CryptFilter.identity;
    }
    return filters[name.getValue()];
  }

  /// Reads `/CF`, `/StmF`, `/StrF` and `/EFF` from an encryption dictionary.
  static Future<CryptFilterConfiguration> fromEncryptionDictionary(
      PdfDictionary encryptionDictionary) async {
    final filters = <String, CryptFilter>{};
    final cf = await encryptionDictionary.dictionaryEntry(PdfName.cf);
    if (cf != null) {
      for (final key in cf.keySet()) {
        final value = await cf.dictionaryEntry(key);
        if (value != null) {
          filters[key.getValue()] =
              await CryptFilter.fromDictionary(key, value);
        }
      }
    }
    final lookup = CryptFilterConfiguration(
      filters: filters,
      streamFilter: CryptFilter.identity,
      stringFilter: CryptFilter.identity,
      embeddedFileFilter: CryptFilter.identity,
    );
    final stream =
        lookup.byName(await encryptionDictionary.nameEntry(PdfName.stmF)) ??
            CryptFilter.identity;
    final string =
        lookup.byName(await encryptionDictionary.nameEntry(PdfName.strF)) ??
            CryptFilter.identity;
    final embedded =
        lookup.byName(await encryptionDictionary.nameEntry(PdfName.eff)) ??
            stream;
    return CryptFilterConfiguration(
      filters: filters,
      streamFilter: stream,
      stringFilter: string,
      embeddedFileFilter: embedded,
    );
  }
}
