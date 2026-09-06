import 'dart:typed_data';

import 'package:pdfcraft/src/io/codec/jbig2_segment_reader.dart';
import 'package:pdfcraft/src/io/exceptions/io_exception.dart';
import 'package:pdfcraft/src/io/exceptions/io_exception_message_constant.dart';
import 'package:pdfcraft/src/io/image/image_data.dart';
import 'package:pdfcraft/src/io/source/random_access_file_or_array.dart';
import 'package:pdfcraft/src/layout/properties/image_type.dart';

class CraftJbig2ImageData extends CraftImageData {
  int _page = 1;

  CraftJbig2ImageData.fromUrl(Uri url, int page)
      : super.fromUrl(url, CraftImageType.JBIG2) {
    _page = page;
  }

  CraftJbig2ImageData.fromBytes(Uint8List bytes, int page)
      : super.fromBytes(bytes, CraftImageType.JBIG2) {
    _page = page;
  }

  int pageAt() => _page;

  static int pageTotal(Uint8List bytes) {
    return getNumberOfPagesFromRaf(CraftRandomAccessFileOrArray(bytes));
  }

  static int getNumberOfPagesFromRaf(CraftRandomAccessFileOrArray raf) {
    try {
      CraftJbig2SegmentReader sr = CraftJbig2SegmentReader(raf);
      sr.read();
      return sr.numberOfPages();
    } catch (e) {
      throw IoException(CraftIoExceptionMessageConstant.jbig2ImageException, e);
    }
  }

  @override
  bool canImageBeInline() {
    // Logger logic skipped for now, just return false as per original
    return false;
  }
}
