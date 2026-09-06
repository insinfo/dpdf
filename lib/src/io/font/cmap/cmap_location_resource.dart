import '../../source/pdf_tokenizer.dart';
import '../../source/random_access_file_or_array.dart';
import 'i_cmap_location.dart';
import 'dart:io';

class CMapLocationResource implements ICMapLocation {
  static const String _defaultCMapPath = "lib/src/io/font/resources/cmap/";
  final String _basePath;

  CMapLocationResource([this._basePath = _defaultCMapPath]);

  @override
  Future<PdfTokenizer> getLocation(String location) async {
    final file = File(_basePath + location);
    if (await file.exists()) {
      return PdfTokenizer(RandomAccessFileOrArray(await file.readAsBytes()));
    }
    throw FileSystemException("CMap resource not found", location);
  }

  @override
  PdfTokenizer getLocationSync(String location) {
    final file = File(_basePath + location);
    if (file.existsSync()) {
      return PdfTokenizer(RandomAccessFileOrArray(file.readAsBytesSync()));
    }
    throw FileSystemException("CMap resource not found", location);
  }

  String getLocationPath() => _basePath;
}
