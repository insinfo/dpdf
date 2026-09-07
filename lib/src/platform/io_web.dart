import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

class FileSystemException implements Exception {
  final String message;
  final String? path;
  const FileSystemException([this.message = '', this.path]);
  @override
  String toString() => path == null ? message : '$message: $path';
}

/// Explicit browser memory storage. Paths are keys, never host filesystem paths.
class BrowserFileStore {
  static final Map<String, Uint8List> _files = {};

  static void register(String path, List<int> bytes) {
    _files[path] = Uint8List.fromList(bytes);
  }

  static Uint8List? bytes(String path) {
    final data = _files[path];
    return data == null ? null : Uint8List.fromList(data);
  }

  static void remove(String path) => _files.remove(path);
  static void clear() => _files.clear();
}

/// Browser counterpart used by path APIs after assets are registered explicitly.
class File {
  final String path;
  File(this.path);
  File.fromUri(Uri uri)
      : path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();

  bool existsSync() => BrowserFileStore._files.containsKey(path);
  Future<bool> exists() async => existsSync();
  Uint8List readAsBytesSync() =>
      BrowserFileStore.bytes(path) ??
      (throw StateError('Register browser asset bytes before reading: $path'));
  Future<Uint8List> readAsBytes() async => readAsBytesSync();
  void writeAsBytesSync(List<int> bytes, {bool flush = false}) =>
      BrowserFileStore.register(path, bytes);
  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    writeAsBytesSync(bytes);
    return this;
  }

  IOSink openWrite({Encoding encoding = utf8}) => _MemorySink(path, encoding);
}

/// The subset of the SDK sink contract consumed by the PDF writer and signer.
abstract class IOSink implements StreamSink<List<int>>, StringSink {
  Encoding get encoding;
  set encoding(Encoding value);
  Future flush();
}

class _MemorySink implements IOSink {
  final String path;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Completer<void> _completion = Completer<void>();
  bool _closed = false;
  @override
  Encoding encoding;
  _MemorySink(this.path, this.encoding);
  @override
  void add(List<int> data) {
    if (_closed) throw StateError('Cannot write to a closed memory output.');
    _bytes.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_completion.isCompleted) _completion.completeError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() async =>
      BrowserFileStore.register(path, _bytes.toBytes());
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await flush();
    if (!_completion.isCompleted) _completion.complete();
  }

  @override
  Future<void> get done => _completion.future;
  @override
  void write(Object? object) => add(encoding.encode('$object'));
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      write(objects.join(separator));
  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }
}

class HttpStatus {
  static const int ok = 200;
}

class ContentType {
  final String primaryType;
  final String subType;
  ContentType(this.primaryType, this.subType);
  @override
  String toString() => '$primaryType/$subType';
}

class _Headers {
  ContentType? contentType;
  final Map<String, String> _values = {};

  void set(String name, Object value) {
    _values[name] = value.toString();
  }
}

/// Fetch transport shared by dart2js and dart2wasm. Browser CORS rules apply.
class HttpClient {
  Duration? connectionTimeout;
  bool _closed = false;
  Future<_Request> getUrl(Uri uri) async => _request('GET', uri);
  Future<_Request> postUrl(Uri uri) async => _request('POST', uri);
  _Request _request(String method, Uri uri) {
    if (_closed) throw StateError('HTTP client is closed.');
    return _Request(method, uri, connectionTimeout);
  }

  void close({bool force = false}) {
    _closed = true;
  }
}

class _Request {
  final String method;
  final Uri uri;
  final Duration? timeout;
  final headers = _Headers();
  final _body = BytesBuilder(copy: false);
  _Request(this.method, this.uri, this.timeout);
  void add(List<int> data) => _body.add(data);
  Future<HttpClientResponse> close() async {
    final options = <String, Object?>{'method': method};
    final requestHeaders = Map<String, String>.from(headers._values);
    if (headers.contentType != null) {
      requestHeaders['Content-Type'] = headers.contentType.toString();
    }
    if (requestHeaders.isNotEmpty) {
      options['headers'] = requestHeaders;
    }
    if (method != 'GET') options['body'] = _body.toBytes().toJS;
    Future<HttpClientResponse> fetchBytes() async {
      final response =
          await _fetch(uri.toString().toJS, options.jsify()!).toDart;
      final buffer = await response.arrayBuffer().toDart;
      return HttpClientResponse(response.status, buffer.toDart.asUint8List());
    }

    final operation = fetchBytes();
    return timeout == null ? operation : operation.timeout(timeout!);
  }
}

class HttpClientResponse extends Stream<List<int>> {
  final int statusCode;
  final Uint8List _bytes;
  HttpClientResponse(this.statusCode, this._bytes);
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(JSString url, JSAny options);
extension type _FetchResponse(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
