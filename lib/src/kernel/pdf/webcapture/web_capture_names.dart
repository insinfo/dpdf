import 'dart:convert';
import 'dart:typed_data';

import '../../../commons/digest/digest_bytes.dart';

/// The naming rules of Web Capture: canonical URL strings (14.10.3.2), digital
/// identifiers (14.10.3.3) and unique name generation (14.10.3.4) of
/// ISO 32000-1:2008.
abstract final class WebCaptureNames {
  /// The default ports removed by step f of the URL string algorithm.
  static const Map<String, int> defaultPorts = {'http': 80, 'ftp': 21};

  /// Reduces [url] to the canonical form used as a key in the `/URLS` name
  /// tree, following the algorithm of 14.10.3.2.
  ///
  /// The steps are applied in the order the clause gives them:
  ///
  /// a) a relative URL is resolved against [base], when one is supplied;
  /// b) the URL is truncated before the first NUMBER SIGN;
  /// c) the scheme is lowercased;
  /// d) the host is lowercased;
  /// e) a `file` URL whose host is `localhost` loses the host;
  /// f) a default port for the scheme is dropped;
  /// g) `.` and `..` path segments are removed.
  ///
  /// The clause states the algorithm "shall be applied for HTTP, FTP, and file
  /// URLs"; a URL of any other scheme still goes through the steps that do not
  /// depend on the scheme, which leaves it unchanged apart from the fragment
  /// and the case of the scheme and host.
  static String canonicalUrl(String url, {String? base}) {
    var text = url.trim();

    // Step b: truncate before the first NUMBER SIGN.
    final hash = text.indexOf('#');
    if (hash >= 0) text = text.substring(0, hash);

    Uri uri;
    try {
      // Step a: resolve a relative URL against the base, when there is one.
      uri = base == null ? Uri.parse(text) : Uri.parse(base).resolve(text);
    } on FormatException {
      return text;
    }

    // Steps c and d: Uri already lowercases the scheme and the host.
    final scheme = uri.scheme.toLowerCase();
    var host = uri.host.toLowerCase();

    // Step e.
    if (scheme == 'file' && host == 'localhost') host = '';

    // Step f.
    var port = uri.hasPort ? uri.port : null;
    if (port != null && defaultPorts[scheme] == port) port = null;

    // Step g.
    final path = uri.path.isEmpty ? uri.path : uri.normalizePath().path;

    final buffer = StringBuffer();
    if (scheme.isNotEmpty) buffer.write('$scheme:');
    if (host.isNotEmpty || uri.hasAuthority || scheme == 'file') {
      buffer.write('//');
      if (uri.userInfo.isNotEmpty) buffer.write('${uri.userInfo}@');
      buffer.write(host);
      if (port != null) buffer.write(':$port');
    }
    buffer.write(path);
    if (uri.hasQuery) buffer.write('?${uri.query}');
    return buffer.toString();
  }

  /// The digital identifier of an image set: the MD5 digest of the source data
  /// of the original image (14.10.3.3).
  static Uint8List imageSetIdentifier(Uint8List sourceData) =>
      DigestBytes.compute('MD5', sourceData);

  /// The digital identifier of a page set (14.10.3.3).
  ///
  /// "The source data shall be passed to the MD5 algorithm first, followed by
  /// strings representing the digital identifiers of any auxiliary data files
  /// (such as images) referenced in the source data, in the order in which they
  /// are first referenced. If an auxiliary file is referenced more than once,
  /// its identifier shall be passed only the first time." The auxiliary
  /// identifiers are fed in as their raw bytes, and repeats are dropped while
  /// keeping the order of first reference.
  static Uint8List pageSetIdentifier(Uint8List sourceData,
      [List<Uint8List> auxiliaryIdentifiers = const []]) {
    final buffer = BytesBuilder();
    buffer.add(sourceData);
    final seen = <String>{};
    for (final identifier in auxiliaryIdentifiers) {
      final key = _hex(identifier);
      if (!seen.add(key)) continue;
      buffer.add(identifier);
    }
    return DigestBytes.compute('MD5', buffer.toBytes());
  }

  /// The text identifier of a page set: the MD5 digest of the text present in
  /// the source data alone (14.10.3.3).
  static Uint8List textIdentifier(Uint8List textData) =>
      DigestBytes.compute('MD5', textData);

  /// The escape of a digital identifier used inside a destination or field
  /// name (14.10.3.4, Table 351).
  ///
  /// The three characters that have a special meaning become two-byte escape
  /// sequences: NUL becomes `\0`, PERIOD becomes `\p`, and REVERSE SOLIDUS
  /// becomes `\\`.
  static Uint8List escapeIdentifier(Uint8List identifier) {
    final out = BytesBuilder();
    for (final byte in identifier) {
      switch (byte) {
        case 0x00:
          out.add(const [0x5c, 0x30]);
          break;
        case 0x2e:
          out.add(const [0x5c, 0x70]);
          break;
        case 0x5c:
          out.add(const [0x5c, 0x5c]);
          break;
        default:
          out.addByte(byte);
      }
    }
    return out.toBytes();
  }

  /// The additional encoding a form field name needs (14.10.3.4).
  ///
  /// "Each byte in the source string... shall be replaced by two bytes in the
  /// destination string. The first byte in each pair is 65... plus the
  /// high-order 4 bits of the source byte; the second byte is 65 plus the
  /// low-order 4 bits of the source byte."
  static Uint8List encodeForFieldName(Uint8List escaped) {
    final out = Uint8List(escaped.length * 2);
    for (var i = 0; i < escaped.length; i++) {
      out[i * 2] = 65 + ((escaped[i] >> 4) & 0x0f);
      out[i * 2 + 1] = 65 + (escaped[i] & 0x0f);
    }
    return out;
  }

  /// The unique name of a named destination derived from [original] and the
  /// page set's digital [identifier] (14.10.3.4).
  static String uniqueDestinationName(String original, Uint8List identifier) =>
      original + latin1.decode(escapeIdentifier(identifier));

  /// The unique name of an interactive form field derived from [original] and
  /// the page set's digital [identifier] (14.10.3.4).
  static String uniqueFieldName(String original, Uint8List identifier) =>
      original +
      latin1.decode(encodeForFieldName(escapeIdentifier(identifier)));

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
