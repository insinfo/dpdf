import 'dart:io';
import 'dart:typed_data';

import 'certificate_util.dart';
import 'i_crl_client.dart';
import 'i_x509_certificate.dart';
import 'package:dpdf/src/commons/_log_manager.dart';

/// An implementation of [ICrlClient] that fetches the CRL bytes from a URL.
class CrlClientOnline implements ICrlClient {
  static final _logger = LogManager.getLoggerByName('CrlClientOnline');
  final List<Uri> _urls = [];
  int _connectionTimeout = 10000; // 10 seconds default

  /// Creates a CrlClientOnline instance.
  ///
  /// If [urls] or [chain] is provided, they are added to the list of URLs.
  CrlClientOnline({
    List<String>? urls,
    List<Uri>? uris,
    List<IX509Certificate>? chain,
  }) {
    if (urls != null) {
      for (final url in urls) {
        addUrlString(url);
      }
    }
    if (uris != null) {
      for (final uri in uris) {
        addUrl(uri);
      }
    }
    if (chain != null) {
      for (final cert in chain) {
        _logger.logInfo("Checking certificate: ${cert.getSubjectDN()}");
        final certUrls = CertificateUtil.getCRLURLs(cert);
        for (final url in certUrls) {
          addUrlString(url);
        }
      }
    }
  }

  /// Sets the connection timeout in milliseconds.
  void setConnectionTimeout(int timeoutMs) {
    _connectionTimeout = timeoutMs;
  }

  /// Adds a URL to the client.
  void addUrl(Uri url) {
    if (!_urls.contains(url)) {
      _urls.add(url);
      _logger.logInfo("Added CRL url: $url");
    }
  }

  /// Adds a URL string to the client.
  void addUrlString(String url) {
    try {
      addUrl(Uri.parse(url));
    } catch (e) {
      _logger.logInfo("Skipped CRL url (malformed): $url");
    }
  }

  @override
  Future<List<Uint8List>?> getEncoded(
      IX509Certificate? checkCert, String? url) async {
    if (checkCert == null) return null;

    final urlsToCheck = <Uri>[..._urls];

    // If no URLs provided in constructor, try to get from cert
    if (urlsToCheck.isEmpty) {
      if (url != null) {
        urlsToCheck.add(Uri.parse(url));
      } else {
        final certUrls = CertificateUtil.getCRLURLs(checkCert);
        for (final u in certUrls) {
          try {
            final uri = Uri.parse(u);
            urlsToCheck.add(uri);
            _logger.logInfo("Found CRL url: $u");
          } catch (e) {
            _logger.logInfo("Skipped CRL url: $e");
          }
        }
      }
    }

    if (urlsToCheck.isEmpty) return null;

    final result = <Uint8List>[];

    for (final uri in urlsToCheck) {
      try {
        final crlBytes = await _fetchCrl(uri);
        if (crlBytes != null) {
          result.add(crlBytes);
        }
      } catch (e) {
        _logger.logInfo("Invalid distribution point: $e");
      }
    }

    return result;
  }

  Future<Uint8List?> _fetchCrl(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = Duration(milliseconds: _connectionTimeout);
    try {
      _logger.logInfo("Checking CRL: $uri");
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final builder = BytesBuilder();
        await response.forEach(builder.add);
        final bytes = builder.toBytes();
        _logger.logInfo("Added CRL found at: $uri");
        return bytes;
      }
    } finally {
      client.close();
    }
    return null;
  }
}
