import 'dart:typed_data';

import 'package:j2k/j2k.dart' as j2k;
import 'package:jbig2/jbig2.dart';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_boolean.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../io/image/image_resampler.dart';
import '../io/image/jpeg_decoder.dart';
import '../io/image/jpeg_encoder.dart';
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

/// Which codec continuous-tone images are re-encoded with.
enum PdfColourCodec {
  /// Leave the image exactly as it is. The default, because every other
  /// choice here discards information.
  keep,

  /// Baseline JPEG. Lossy, and the reason a scanned colour page shrinks by an
  /// order of magnitude.
  jpeg,
}

/// What the image pass is allowed to do.
///
/// The bi-level path is lossless by construction: the samples that come out
/// are the samples that went in, just encoded better. The continuous-tone
/// path and [maxDimension] discard information, so both are off by default
/// and have to be asked for.
class PdfImageCompressionOptions {
  /// Codec for 1-bit images.
  final PdfBilevelCodec bilevel;

  /// Codec for 8-bit grayscale and RGB images.
  ///
  /// Defaults to [PdfColourCodec.keep]: re-encoding as JPEG throws away
  /// detail, so it has to be asked for.
  final PdfColourCodec colour;

  /// JPEG quality, 1 to 100, used when [colour] is [PdfColourCodec.jpeg].
  final int jpegQuality;

  /// Downsample an image whose larger side exceeds this, keeping its aspect
  /// ratio. Null leaves every image at its stored resolution.
  ///
  /// This is a cap in **pixels**, not a target DPI: deciding a DPI needs the
  /// transformation the page's content stream applies to the image, which
  /// this pass does not read.
  final int? maxDimension;

  /// Skip images with fewer pixels than this. Re-encoding a small image rarely
  /// pays for the segment headers a codec adds.
  final int minimumPixels;

  const PdfImageCompressionOptions({
    this.bilevel = PdfBilevelCodec.auto,
    this.colour = PdfColourCodec.keep,
    this.jpegQuality = 75,
    this.maxDimension,
    this.minimumPixels = 4096,
  });

  /// Re-encode continuous-tone images as JPEG at [quality], and cap their
  /// larger side at [maxDimension] when one is given.
  ///
  /// Lossy. Use it when the document is for reading rather than archiving.
  const PdfImageCompressionOptions.lossy({
    this.bilevel = PdfBilevelCodec.auto,
    int quality = 75,
    this.maxDimension,
    this.minimumPixels = 4096,
  })  : colour = PdfColourCodec.jpeg,
        jpegQuality = quality;

  /// Do nothing to images.
  static const PdfImageCompressionOptions none = PdfImageCompressionOptions(
    bilevel: PdfBilevelCodec.keep,
    colour: PdfColourCodec.keep,
  );
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
/// It decodes an image's samples through the filters it already carries,
/// encodes them again, and keeps the result only when it is smaller. An image
/// it cannot decode, or cannot improve, is left untouched.
///
/// Bi-level images are re-encoded losslessly. Continuous-tone images are only
/// touched when the options ask for it, because doing so means JPEG, which
/// throws detail away, and possibly resampling, which throws away more.
abstract final class PdfImageCompressor {
  /// Re-encodes every image among [objects] that the options cover.
  static Future<PdfImageCompressionReport> run(
    List<CraftPdfObject> objects,
    PdfImageCompressionOptions options,
  ) async {
    if (options.bilevel == PdfBilevelCodec.keep &&
        options.colour == PdfColourCodec.keep) {
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
    if (!isMask && bits != 1) {
      if (bits == 8 && options.colour != PdfColourCodec.keep) {
        return _recompressContinuousTone(image, options, width, height);
      }
      return null;
    }
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

  /// Re-encodes an 8-bit grayscale or RGB image as JPEG, optionally shrinking
  /// it first.
  ///
  /// Returns the bytes saved, 0 when the image was examined and left alone, or
  /// null when it is not one this path handles.
  static Future<int?> _recompressContinuousTone(
    CraftPdfStream image,
    PdfImageCompressionOptions options,
    int width,
    int height,
  ) async {
    // An explicit /Decode array, a palette or a separation space all give the
    // samples a meaning JPEG cannot carry across.
    if (image.containsKey(CraftPdfName('Decode'))) return 0;

    final channels = await _colourChannels(image);
    if (channels == null) return null;
    if (width * height < options.minimumPixels) return 0;

    Uint8List? current;
    _Samples? samples;
    try {
      current = await image.getRawBytes();
      samples = await _samplesOf(image, width, height, channels);
    } on Object {
      return 0;
    }
    if (current == null || samples == null) return 0;

    var pixels = samples.pixels;
    var targetWidth = samples.width;
    var targetHeight = samples.height;

    final cap = options.maxDimension;
    if (cap != null) {
      final fitted = ImageResampler.fit(
          width: targetWidth, height: targetHeight, maxDimension: cap);
      if (fitted != null) {
        pixels = ImageResampler.resize(
          pixels,
          width: targetWidth,
          height: targetHeight,
          targetWidth: fitted.width,
          targetHeight: fitted.height,
          channels: samples.channels,
        );
        targetWidth = fitted.width;
        targetHeight = fitted.height;
      }
    }

    final Uint8List candidate;
    try {
      candidate = JpegEncoder.encode(
        pixels,
        width: targetWidth,
        height: targetHeight,
        format: samples.channels == 1
            ? JpegPixelFormat.grayscale
            : JpegPixelFormat.rgb,
        quality: options.jpegQuality,
      );
    } on Object {
      return 0;
    }

    // Losing detail has to buy something, so a re-encode that is not smaller
    // is discarded whether or not the image was also resized.
    if (candidate.length >= current.length) return 0;

    image
      ..setData(candidate)
      ..put(CraftPdfName.filter, CraftPdfName('DCTDecode'))
      ..put(CraftPdfName.width, CraftPdfNumber.fromInt(targetWidth))
      ..put(CraftPdfName.height, CraftPdfNumber.fromInt(targetHeight))
      ..put(CraftPdfName('BitsPerComponent'), CraftPdfNumber.fromInt(8))
      ..put(CraftPdfName('ColorSpace'),
          CraftPdfName(samples.channels == 1 ? 'DeviceGray' : 'DeviceRGB'))
      ..remove(CraftPdfName('DecodeParms'))
      ..markChanged();
    return current.length - candidate.length;
  }

  /// Channels implied by the image's colour space, or null when it is one this
  /// path does not re-encode.
  static Future<int?> _colourChannels(CraftPdfStream image) async {
    final space = await image.get(CraftPdfName('ColorSpace'), true);
    if (space == null) return null;
    if (space.objectKind() == PdfObjectType.name) {
      return switch ((space as CraftPdfName).getValue()) {
        'DeviceGray' || 'G' || 'CalGray' => 1,
        'DeviceRGB' || 'RGB' || 'CalRGB' => 3,
        _ => null,
      };
    }
    if (space.objectKind() == PdfObjectType.array) {
      final array = space as CraftPdfArray;
      final family = (await array.nameEntry(0))?.getValue();
      if (family == 'ICCBased') {
        final profile = await array.streamEntry(1);
        final n = await profile?.integerEntry(CraftPdfName('N'));
        // Only the two ICC spaces a baseline JPEG can stand in for.
        return n == 1 || n == 3 ? n : null;
      }
      // Indexed, Separation, DeviceN and Lab all give the samples a meaning
      // that would be lost.
      return null;
    }
    return null;
  }

  /// Decodes the image's samples to interleaved 8-bit values.
  static Future<_Samples?> _samplesOf(
    CraftPdfStream image,
    int width,
    int height,
    int channels,
  ) async {
    final filter = await _filterNames(image);

    if (filter.contains('DCTDecode') || filter.contains('DCT')) {
      final raw = await image.getRawBytes();
      if (raw == null) return null;
      final decoded = JpegDecoder.decode(raw);
      if (decoded.format == JpegPixelFormat.cmyk) return null;
      return _Samples(
          decoded.pixels, decoded.width, decoded.height, decoded.bytesPerPixel);
    }

    if (filter.contains('JPXDecode')) {
      final raw = await image.getRawBytes();
      if (raw == null) return null;
      final decoded = j2k.decodeJpeg2000(raw);
      // Only the two layouts a baseline JPEG can carry.
      if (decoded.components != 1 && decoded.components != 3) return null;
      return _Samples(
          decoded.pixels, decoded.width, decoded.height, decoded.components);
    }

    // Everything else decodes to plain samples through the filters the stream
    // already declares.
    final plain = await image.getBytes();
    if (plain == null || plain.length < width * height * channels) return null;
    return _Samples(plain, width, height, channels);
  }

  static Future<Set<String>> _filterNames(CraftPdfStream stream) async {
    final filter = await stream.get(CraftPdfName.filter);
    if (filter == null) return const {};
    if (filter.objectKind() == PdfObjectType.name) {
      return {(filter as CraftPdfName).getValue()};
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as CraftPdfArray;
      final names = <String>{};
      for (var i = 0; i < array.size(); i++) {
        final name = await array.nameEntry(i);
        if (name != null) names.add(name.getValue());
      }
      return names;
    }
    return const {};
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

/// Interleaved 8-bit samples with the geometry they were decoded at.
class _Samples {
  final Uint8List pixels;
  final int width;
  final int height;
  final int channels;
  const _Samples(this.pixels, this.width, this.height, this.channels);
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
