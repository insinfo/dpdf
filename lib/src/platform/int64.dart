/// Exact signed words with target-specific typed-data access.
library;

export 'int64_portable.dart'
    if (dart.library.io) 'int64_native.dart'
    if (dart.library.js) 'int64_js.dart'
    if (dart.library.js_interop) 'int64_native.dart';
