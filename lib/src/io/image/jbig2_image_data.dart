import 'dart:typed_data';

import 'package:dpdf/src/io/codec/jbig2_segment_reader.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class Jbig2ImageData extends ImageData {
  int _page = 1;

  Jbig2ImageData.fromUrl(Uri url, int page)
      : super.fromUrl(url, ImageType.JBIG2) {
    _page = page;
  }

  Jbig2ImageData.fromBytes(Uint8List bytes, int page)
      : super.fromBytes(bytes, ImageType.JBIG2) {
    _page = page;
  }

  int getPage() => _page;

  static int getNumberOfPages(Uint8List bytes) {
    return getNumberOfPagesFromRaf(RandomAccessFileOrArray(bytes));
  }

  static int getNumberOfPagesFromRaf(RandomAccessFileOrArray raf) {
    try {
      Jbig2SegmentReader sr = Jbig2SegmentReader(raf);
      sr.read();
      return sr.numberOfPages();
    } catch (e) {
      throw IoException(IoExceptionMessageConstant.jbig2ImageException, e);
    }
  }

  @override
  bool canImageBeInline() {
    // ILogger logic skipped for now, just return false as per original
    return false;
  }
}
