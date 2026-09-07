/// Compression selected at compile time; browser builds have no native imports.
library;

export 'compression_portable.dart' if (dart.library.io) 'compression_vm.dart';
