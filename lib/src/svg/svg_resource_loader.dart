import 'dart:typed_data';

/// Carrega um recurso externo referenciado por um SVG.
///
/// No navegador a implementação normalmente usa `fetch`; em aplicações
/// nativas pode ler arquivo, HTTP ou um cache. O conversor nunca acessa rede
/// implicitamente.
typedef SvgResourceLoader = Future<Uint8List?> Function(Uri uri);
