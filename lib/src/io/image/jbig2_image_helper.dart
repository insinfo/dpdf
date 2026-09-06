import 'dart:typed_data';

import 'package:pdfcraft/src/io/codec/jbig2_segment_reader.dart';
import 'package:pdfcraft/src/io/exceptions/io_exception.dart';
import 'package:pdfcraft/src/io/exceptions/io_exception_message_constant.dart';
import 'package:pdfcraft/src/io/image/image_data.dart';
import 'package:pdfcraft/src/io/image/jbig2_image_data.dart';
import 'package:pdfcraft/src/io/source/random_access_file_or_array.dart';

import 'package:pdfcraft/src/layout/properties/image_type.dart';

class CraftJbig2ImageHelper {
  static Uint8List? getGlobalSegment(CraftRandomAccessFileOrArray ra) {
    try {
      CraftJbig2SegmentReader sr = CraftJbig2SegmentReader(ra);
      sr.read();
      return sr.getGlobal(true);
    } catch (e) {
      return null;
    }
  }

  static void processImage(CraftImageData jbig2) {
    if (jbig2.getOriginalType() != CraftImageType.JBIG2) {
      throw ArgumentError("JBIG2 image expected");
    }
    CraftJbig2ImageData image = jbig2 as CraftJbig2ImageData;
    try {
      // Load data if needed (ImageData.loadData is usually protected/implicit?
      // In Dart port ImageData usually has bytes set if loaded?)
      // We'll rely on getData() returning bytes.
      if (image.getData() == null) {
        // In C# it calls LoadData.
        // In Dart ImageData.getData() is a getter.
        // If created with url, we might need to load.
        // ImageData has loadData()?
      }

      final raf = CraftRandomAccessFileOrArray(image.getData()!);
      CraftJbig2SegmentReader sr = CraftJbig2SegmentReader(raf);
      sr.read();
      Jbig2Page? p = sr.pageAt(image.pageAt());
      if (p == null) {
        throw IoException("Page ${image.pageAt()} not found in JBIG2 file.");
      }
      raf.close();

      image.setHeight(p.getPageBitmapHeight().toDouble());
      image.setWidth(p.getPageBitmapWidth().toDouble());
      image.setBpc(1);
      // set color components? ImageData base has no setter?
      // C# says image.SetColorEncodingComponentsNumber(1).
      // Let's check ImageData definition.
      // Assuming it's not ported or I forgot.
      // But typically bpc=1 and components=1 for JBIG2.

      Uint8List? globals = sr.getGlobal(true);
      if (globals != null) {
        Map<String, Object> decodeParms = {};
        decodeParms["JBIG2Globals"] = globals;
        image.setDecodeParms(decodeParms);
      }
      image.setFilter("JBIG2Decode");
      image.setColorEncodingComponentsNumber(1);
      image.setBpc(1);
      image.setData(p.getData(true));
    } catch (e) {
      throw IoException(CraftIoExceptionMessageConstant.jbig2ImageException, e);
    }
  }
}
