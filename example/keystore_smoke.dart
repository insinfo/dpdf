import 'dart:convert';
import 'package:dpdf/dpdf.dart';

/// Synthetic AES key protected by an independent test encoder.
/// These bytes are public test material, never credentials for real services.
void main() {
  _verifyJks();
  final bks = BksKeyStore.decode(
      base64Decode(
          'AAAAAgAAAAgBCAIHAwYEBQAAAAcEAAZzZWFsZWQAAAAAAAAAAAAAAAAAAAAwAAAACAEIAgcDBgQFAAAABwxQ7+7Z8f8WOMQc9OIwlihAFFbo5VwMsJYrMVLo/qhnAGd7fhZBHiQVrAV106H7GEKz7hJi'),
      password: 'senha');
  final key = bks.records.single.recoverKey('entry-password');
  if (key.algorithm != 'AES' || key.bytes.length != 16) {
    throw StateError('BKS key recovery failed');
  }
  for (var i = 0; i < 16; i++) {
    if (key.bytes[i] != i) throw StateError('BKS key bytes differ');
  }
  final rewritten = BksKeyStore.decode(bks.encode(password: 'new-password'),
      password: 'new-password');
  if (rewritten.records.single.alias != 'sealed') {
    throw StateError('BKS rewrite failed');
  }
}

// Public synthetic certificate generated for this compatibility check.
void _verifyJks() {
  final store = JksKeyStore.read(
      base64Decode(
          '/u3+7QAAAAIAAAABAAAAAgAHZml4dHVyZQAAAAAAAAAAAAVYLjUwOQAAAuUwggLhMIIByaADAgECAggwIFwy4dBzPD'
          'ANBgkqhkiG9w0BAQwFADAfMR0wGwYDVQQDExRQREZDcmFmdCBKS1MgRml4dHVyZTAeFw0yNjA5MDYyMzMwMjZaFw0y'
          'NzA5MDYyMzMwMjZaMB8xHTAbBgNVBAMTFFBERkNyYWZ0IEpLUyBGaXh0dXJlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ'
          '8AMIIBCgKCAQEAt5Wf6/4t/5lezfMojBd8V7nlHZ2yiukDcWcZG3TLuhyNweVAvSoUDla5zc76IUJCzOwepEjSw6PJ'
          '7ARViinYYJ85y4jpoK0gLT/J+AdPEhsyqrOQL5f934lvWHMSDU+wVkiTNPt59dWJU5+R+ys5rtx/8TZsZVmKZ9XfLs'
          'E6+gieHCwoE/4QauOncOoU+NlaIVtqc93lg2hm4domtOeFXNQdV9+K1WMEZEXAp80aiJh/eRlgNZ4DmfzqLVZI+yjp'
          'Z4AeSJ2rBfIskGSXA/xD9RtfAVXpav+UfhLgc/YEKggPtIxv0mmuM7GJMAV4CZxB6gKpEQwhve+W0Z9DKfOExQIDAQ'
          'ABoyEwHzAdBgNVHQ4EFgQU0uHVBsomP26VWBcCo1Jrf6TfR08wDQYJKoZIhvcNAQEMBQADggEBAKCWeKSdZciwC020'
          '2NEJAxANKwF3v9g8rgAvp0UiWsWmVw9tk7hNllK9kFQl4zVv8W2p1MDfN6NoYvHGZcVXw/omOZt3v6ppiX7NLNyd13'
          'y1tNJMbV0roE9OomYVFbo4WzgLeVMu0OEvM3AwXcfUhW7oolSb5H5o+0hOr0WSVEhN5XIyHhyglzeD3yanwklVaNtS'
          '0LAqki8hl/ZSBJdurfyWfk9kF5rqR8Dd7f8ukz14WUJMyeTqew1KDW10+7UM0xuXxxpZkPXqpQ1bnHvI8U1bqRCUjp'
          'wHn+RXLcTK6ClWUgIyw8rP4S2JExXKnAyl5i+C+nmAJal/tpNVgCZsK9rtmcrQGHHJtQH2Hh1mpnKPeueusw=='),
      password: 'smoke');
  final entry = store.entries['fixture'] as JksTrustedCertificate;
  if (store.version != 2 ||
      entry.certificate.type != 'X.509' ||
      entry.certificate.bytes.length != 741 ||
      entry.timestampMilliseconds != BigInt.zero) {
    throw StateError('JKS certificate decoding failed');
  }
}
