import 'dart:typed_data';

/// Supplies optional CJK registry, font-property and CMap files by name.
///
/// Applications own these resources and their licensing. A provider lets a
/// browser or embedded application supply them without relying on a file path.
abstract class CjkResourceProvider {
  /// Returns a fresh byte list for [name], or null when the resource is absent.
  Uint8List? readSync(String name);

  /// Asynchronous counterpart for providers backed by a remote store.
  Future<Uint8List?> read(String name) async => readSync(name);
}

/// Immutable in-memory CJK resource provider.
///
/// Resource names are restricted to plain file names. This prevents a CMap's
/// `usecmap` directive from selecting an unintended host path.
class CjkMemoryResourceProvider implements CjkResourceProvider {
  final Map<String, Uint8List> _resources;

  CjkMemoryResourceProvider(Map<String, List<int>> resources)
      : _resources = Map.unmodifiable({
          for (final entry in resources.entries)
            _validatedName(entry.key): Uint8List.fromList(entry.value),
        });

  static String _validatedName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', 'must be a plain resource name');
    }
    return name;
  }

  @override
  Uint8List? readSync(String name) {
    final bytes = _resources[_validatedName(name)];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> read(String name) async => readSync(name);
}
