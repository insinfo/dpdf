import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_boolean.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../platform/compression.dart';

/// Which codec bi-level images are re-encoded with.
///
/// Neither codec wins everywhere. JBIG2 models the page as pixels in context,
/// so it wins on real scans, where no two rows are identical. Deflate finds
/// long literal repeats, so it wins on synthetic or heavily quantised images
/// whose rows repeat exactly. Measured on an 800x1000 page: deflate 287 bytes
/// against JBIG2's 886 when the rows are perfectly periodic, and 20304 against
/// JBIG2's 16519 once scanner noise is present.
///
/// That is why [auto] is the default: guessing the codec from the image's
/// dictionary cannot beat encoding it both ways and keeping the smaller one.
enum PdfBilevelCodec {
  /// Leave the image exactly as it is.
  keep,

  /// Try every codec and keep whichever came out smallest.
  auto,

  /// JBIG2 only, whatever it costs. Choose this when the consumer requires
  /// JBIG2 specifically.
  jbig2,

  /// Deflate only. Understood by every reader back to PDF 1.2, where JBIG2
  /// needs PDF 1.4.
  flate,
}

/// What the image pass is allowed to do.
///
/// Only bi-level images are handled, and only losslessly: the samples that
/// come out are the samples that went in, just encoded better. Resampling to a
/// target resolution, and re-encoding continuous-tone images, are lossy
/// decisions and are not made here.
class PdfImageCompressionOptions {
  /// Codec for 1-bit images.
  final PdfBilevelCodec bilevel;

  /// Skip images with fewer pixels than this. Re-encoding a small image rarely
  /// pays for the segment headers a codec adds.
  final int minimumPixels;

  const PdfImageCompressionOptions({
    this.bilevel = PdfBilevelCodec.auto,
    this.minimumPixels = 4096,
  });

  /// Do nothing to images.
  static const PdfImageCompressionOptions none =
      PdfImageCompressionOptions(bilevel: PdfBilevelCodec.keep);
}

/// What the image pass did.
class PdfImageCompressionReport {
  /// Images that were re-encoded.
  final int imagesRecompressed;

  /// Images that were looked at and left alone, because the new encoding was
  /// not smaller or the image was not one this pass handles.
  final int imagesSkipped;

  /// Bytes saved across the re-encoded image streams.
  final int bytesSaved;

  const PdfImageCompressionReport({
    required this.imagesRecompressed,
    required this.imagesSkipped,
    required this.bytesSaved,
  });

  static const PdfImageCompressionReport empty = PdfImageCompressionReport(
    imagesRecompressed: 0,
    imagesSkipped: 0,
    bytesSaved: 0,
  );

  Map<String, Object?> toJson() => {
        'imagesRecompressed': imagesRecompressed,
        'imagesSkipped': imagesSkipped,
        'bytesSaved': bytesSaved,
      };

  @override
  String toString() => 'PdfImageCompressionReport('
      '$imagesRecompressed recompressed, $imagesSkipped skipped, '
      '$bytesSaved bytes saved)';
}

/// Re-encodes the image XObjects in a document with a better codec.
///
/// The pass is lossless: it decodes an image's samples through the filters it
/// already carries, encodes them again, and keeps the result only when it is
/// smaller. An image it cannot decode, or cannot improve, is left untouched.
abstract final class PdfImageCompressor {
  /// Re-encodes every image among [objects] that the options cover.
  static Future<PdfImageCompressionReport> run(
    List<CraftPdfObject> objects,
    PdfImageCompressionOptions options,
  ) async {
    if (options.bilevel == PdfBilevelCodec.keep) {
      return PdfImageCompressionReport.empty;
    }

    var recompressed = 0;
    var skipped = 0;
    var saved = 0;

    for (final object in objects) {
      if (object is! CraftPdfStream) continue;
      if ((await object.nameEntry(CraftPdfName.subtype))?.getValue() !=
          'Image') {
        continue;
      }

      final outcome = await _recompress(object, options);
      switch (outcome) {
        case null:
          break;
        case final int gained when gained > 0:
          recompressed++;
          saved += gained;
        default:
          skipped++;
      }
    }

    return PdfImageCompressionReport(
      imagesRecompressed: recompressed,
      imagesSkipped: skipped,
      bytesSaved: saved,
    );
  }

  /// Returns the bytes saved, 0 when the image was examined and left alone,
  /// or null when it is not an image this pass handles.
  static Future<int?> _recompress(
    CraftPdfStream image,
    PdfImageCompressionOptions options,
  ) async {
    final width = await image.integerEntry(CraftPdfName.width);
    final height = await image.integerEntry(CraftPdfName.height);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    final isMask = await image.flagEntry(CraftPdfName('ImageMask')) ?? false;
    final bits = await image.integerEntry(CraftPdfName('BitsPerComponent'));
    if (!isMask && bits != 1) return null;
    if (width * height < options.minimumPixels) return 0;

    // A soft-masked or explicitly re-mapped image keeps its own conventions;
    // re-encoding it would need those carried across, so leave it alone.
    if (image.containsKey(CraftPdfName('SMask')) ||
        image.containsKey(CraftPdfName('Decode'))) {
      return 0;
    }

    Uint8List? current;
    Uint8List? samples;
    try {
      current = await image.getRawBytes();
      samples = await image.getBytes();
    } on Object {
      return 0;
    }
    if (current == null || samples == null) return 0;

    final stride = (width + 7) >> 3;
    if (samples.length < stride * height) return 0;

    final wantJbig2 = options.bilevel == PdfBilevelCodec.jbig2 ||
        options.bilevel == PdfBilevelCodec.auto;
    final wantFlate = options.bilevel == PdfBilevelCodec.flate ||
        options.bilevel == PdfBilevelCodec.auto;

    Uint8List? candidate;
    CraftPdfName? filter;

    if (wantJbig2) {
      try {
        candidate = encodeJbig2Packed(
          samples,
          width: width,
          height: height,
          rowStride: stride,
          // PDF stores a 1 bit as white; JBIG2 stores it as black.
          oneIsBlack: false,
        );
        filter = CraftPdfName('JBIG2Decode');
      } on Object {
        candidate = null;
      }
    }
    if (wantFlate) {
      final deflated =
          Uint8List.fromList(ZLibEncoder(level: 9).convert(samples));
      if (candidate == null || deflated.length < candidate.length) {
        candidate = deflated;
        filter = CraftPdfName('FlateDecode');
      }
    }

    if (candidate == null || filter == null) return 0;
    if (candidate.length >= current.length) return 0;

    image.setData(candidate);
    image.put(CraftPdfName.filter, filter);
    image.remove(CraftPdfName('DecodeParms'));
    image.markChanged();
    return current.length - candidate.length;
  }

  /// True when [stream] is an image whose filter is a JBIG2 codestream.
  static Future<bool> usesJbig2(CraftPdfStream stream) async {
    final filter = await stream.get(CraftPdfName.filter);
    if (filter == null) return false;
    if (filter.objectKind() == PdfObjectType.name) {
      return (filter as CraftPdfName).getValue() == 'JBIG2Decode';
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as CraftPdfArray;
      for (var i = 0; i < array.size(); i++) {
        if ((await array.nameEntry(i))?.getValue() == 'JBIG2Decode') {
          return true;
        }
      }
    }
    return false;
  }
}

/// Convenience for building a 1-bit image dictionary around packed rows.
///
/// Useful when embedding a scanned page: the dimensions and colour space are
/// the parts a caller usually gets wrong.
CraftPdfStream buildBilevelImage({
  required int width,
  required int height,
  required Uint8List packedRows,
  CraftPdfName? filter,
  bool imageMask = false,
}) {
  final stream = CraftPdfStream.withBytes(packedRows, 0)
    ..put(CraftPdfName.type, CraftPdfName('XObject'))
    ..put(CraftPdfName.subtype, CraftPdfName('Image'))
    ..put(CraftPdfName.width, CraftPdfNumber.fromInt(width))
    ..put(CraftPdfName.height, CraftPdfNumber.fromInt(height))
    ..put(CraftPdfName('BitsPerComponent'), CraftPdfNumber.fromInt(1));
  if (imageMask) {
    stream.put(CraftPdfName('ImageMask'), CraftPdfBoolean(true));
  } else {
    stream.put(CraftPdfName('ColorSpace'), CraftPdfName('DeviceGray'));
  }
  if (filter != null) stream.put(CraftPdfName.filter, filter);
  return stream;
}
