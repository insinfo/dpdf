import 'dart:typed_data';

import 'package:dpdf/src/io/codec/jbig2_segment_reader.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/jbig2_image_data.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';

import 'package:dpdf/src/layout/properties/image_type.dart';

class Jbig2ImageHelper {
  static Uint8List? getGlobalSegment(RandomAccessFileOrArray ra) {
    try {
      Jbig2SegmentReader sr = Jbig2SegmentReader(ra);
      sr.read();
      return sr.getGlobal(true);
    } catch (e) {
      return null;
    }
  }

  static void processImage(ImageData jbig2) {
    if (jbig2.getOriginalType() != ImageType.JBIG2) {
      throw ArgumentError("JBIG2 image expected");
    }
    Jbig2ImageData image = jbig2 as Jbig2ImageData;
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

      final raf = RandomAccessFileOrArray(image.getData()!);
      Jbig2SegmentReader sr = Jbig2SegmentReader(raf);
      sr.read();
      Jbig2Page? p = sr.getPage(image.getPage());
      if (p == null) {
        throw IoException("Page ${image.getPage()} not found in JBIG2 file.");
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
      throw IoException(IoExceptionMessageConstant.jbig2ImageException, e);
    }
  }
}
