import 'dart:math' as math;
import 'dart:typed_data';

import 'package:j2k/j2k.dart' as j2k;
import 'package:jbig2/jbig2.dart';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_boolean.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../io/image/image_resampler.dart';
import '../io/image/jpeg_decoder.dart';
import '../io/image/jpeg_encoder.dart';
import '../platform/compression.dart';
import 'pdf_image_usage_analyzer.dart';

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
  final int? maxDimension;

  /// Resolução máxima efetiva das imagens no tamanho em que são pintadas.
  ///
  /// Diferentemente de [maxDimension], considera a matriz de transformação de
  /// cada `Do` na página e em Form XObjects. Uma imagem reutilizada conserva a
  /// resolução exigida por sua maior ocorrência. Null desativa este limite.
  final double? targetDpi;

  /// Skip images with fewer pixels than this. Re-encoding a small image rarely
  /// pays for the segment headers a codec adds.
  final int minimumPixels;

  const PdfImageCompressionOptions({
    this.bilevel = PdfBilevelCodec.auto,
    this.colour = PdfColourCodec.keep,
    this.jpegQuality = 75,
    this.maxDimension,
    this.targetDpi,
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
    this.targetDpi,
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
    List<PdfObject> objects,
    PdfImageCompressionOptions options, {
    Map<PdfStream, PdfImageUsage> usages = const {},
  }) async {
    if (options.bilevel == PdfBilevelCodec.keep &&
        options.colour == PdfColourCodec.keep) {
      return PdfImageCompressionReport.empty;
    }

    var recompressed = 0;
    var skipped = 0;
    var saved = 0;

    final shared = await _trySharedJbig2(objects, options);
    final sharedImages = shared?.images ?? const <PdfStream>{};
    if (shared != null) {
      recompressed += shared.images.length;
      saved += shared.bytesSaved;
    }

    for (final object in objects) {
      if (object is! PdfStream) continue;
      if ((await object.nameEntry(PdfName.subtype))?.getValue() != 'Image') {
        continue;
      }
      if (sharedImages.contains(object)) continue;

      final outcome = await _recompress(object, options, usages[object]);
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

  static Future<_SharedJbig2Result?> _trySharedJbig2(
      List<PdfObject> objects, PdfImageCompressionOptions options) async {
    if (options.bilevel != PdfBilevelCodec.auto &&
        options.bilevel != PdfBilevelCodec.jbig2) {
      return null;
    }
    final candidates = <_BilevelImage>[];
    for (final object in objects) {
      if (object is! PdfStream ||
          (await object.nameEntry(PdfName.subtype))?.getValue() != 'Image') {
        continue;
      }
      final width = await object.integerEntry(PdfName.width);
      final height = await object.integerEntry(PdfName.height);
      final mask = await object.flagEntry(PdfName('ImageMask')) ?? false;
      final bits = await object.integerEntry(PdfName('BitsPerComponent'));
      if (width == null ||
          height == null ||
          width <= 0 ||
          height <= 0 ||
          (!mask && bits != 1) ||
          width * height < options.minimumPixels ||
          object.containsKey(PdfName('SMask')) ||
          object.containsKey(PdfName('Decode'))) {
        continue;
      }
      try {
        final raw = await object.getRawBytes();
        final samples = await object.getBytes();
        final stride = (width + 7) >> 3;
        if (raw == null ||
            samples == null ||
            samples.length < stride * height) {
          continue;
        }
        final black = Uint8List(stride * height);
        for (var i = 0; i < black.length; i++) {
          black[i] = ~samples[i] & 0xff;
        }
        candidates.add(_BilevelImage(
            object,
            raw,
            samples,
            Jbig2Image.fromPacked(
                width: width, height: height, rowStride: stride, data: black)));
      } on Object {
        continue;
      }
    }
    if (candidates.length < 2) return null;

    final encoded = encodeJbig2EmbeddedPages(
        [for (final candidate in candidates) candidate.image],
        options:
            const Jbig2EncodeOptions(mode: Jbig2EncodeMode.symbolDictionary));
    if (!encoded.usesGlobalDictionary) return null;

    var alternative = 0;
    for (final candidate in candidates) {
      var best = candidate.raw.length;
      try {
        final individual = encodeJbig2Embedded(candidate.image,
            options: const Jbig2EncodeOptions());
        if (individual.length < best) best = individual.length;
      } on Object {
        // Keep the original size as the comparison baseline.
      }
      if (options.bilevel == PdfBilevelCodec.auto) {
        final deflated = Uint8List.fromList(
            ZLibEncoder(level: 9).convert(candidate.samples));
        if (deflated.length < best) best = deflated.length;
      }
      alternative += best;
    }
    if (encoded.totalLength >= alternative) return null;

    final document = candidates.first.stream.indirectHandle()?.getDocument();
    if (document == null) return null;
    final globals = PdfStream.withBytes(encoded.globals, 0);
    globals.attachToDocument(document);
    for (var i = 0; i < candidates.length; i++) {
      final stream = candidates[i].stream;
      stream
        ..setData(encoded.pages[i])
        ..put(PdfName.filter, PdfName('JBIG2Decode'))
        ..put(
            PdfName('DecodeParms'),
            PdfDictionary()
              ..put(PdfName('JBIG2Globals'), globals.indirectHandle()!))
        ..markChanged();
    }
    final original =
        candidates.fold<int>(0, (total, item) => total + item.raw.length);
    return _SharedJbig2Result(
        {for (final candidate in candidates) candidate.stream},
        original - encoded.totalLength);
  }

  /// Returns the bytes saved, 0 when the image was examined and left alone,
  /// or null when it is not an image this pass handles.
  static Future<int?> _recompress(
    PdfStream image,
    PdfImageCompressionOptions options,
    PdfImageUsage? usage,
  ) async {
    final width = await image.integerEntry(PdfName.width);
    final height = await image.integerEntry(PdfName.height);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    final isMask = await image.flagEntry(PdfName('ImageMask')) ?? false;
    final bits = await image.integerEntry(PdfName('BitsPerComponent'));
    if (!isMask && bits != 1) {
      if (bits == 8 && options.colour != PdfColourCodec.keep) {
        return _recompressContinuousTone(image, options, width, height, usage);
      }
      return null;
    }
    if (width * height < options.minimumPixels) return 0;

    // A soft-masked or explicitly re-mapped image keeps its own conventions;
    // re-encoding it would need those carried across, so leave it alone.
    if (image.containsKey(PdfName('SMask')) ||
        image.containsKey(PdfName('Decode'))) {
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
    PdfName? filter;

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
        filter = PdfName('JBIG2Decode');
      } on Object {
        candidate = null;
      }
    }
    if (wantFlate) {
      final deflated =
          Uint8List.fromList(ZLibEncoder(level: 9).convert(samples));
      if (candidate == null || deflated.length < candidate.length) {
        candidate = deflated;
        filter = PdfName('FlateDecode');
      }
    }

    if (candidate == null || filter == null) return 0;
    if (candidate.length >= current.length) return 0;

    image.setData(candidate);
    image.put(PdfName.filter, filter);
    image.remove(PdfName('DecodeParms'));
    image.markChanged();
    return current.length - candidate.length;
  }

  /// Re-encodes an 8-bit grayscale or RGB image as JPEG, optionally shrinking
  /// it first.
  ///
  /// Returns the bytes saved, 0 when the image was examined and left alone, or
  /// null when it is not one this path handles.
  static Future<int?> _recompressContinuousTone(
    PdfStream image,
    PdfImageCompressionOptions options,
    int width,
    int height,
    PdfImageUsage? usage,
  ) async {
    // An explicit /Decode array, a palette or a separation space all give the
    // samples a meaning JPEG cannot carry across.
    if (image.containsKey(PdfName('Decode'))) return 0;

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

    var scale = 1.0;
    final dpi = options.targetDpi;
    if (dpi != null && usage != null) {
      final neededWidth = usage.widthPoints * dpi / 72;
      final neededHeight = usage.heightPoints * dpi / 72;
      scale = math.min(scale,
          math.max(neededWidth / targetWidth, neededHeight / targetHeight));
    }
    final cap = options.maxDimension;
    if (cap != null) {
      scale = math.min(scale, cap / math.max(targetWidth, targetHeight));
    }
    if (scale < 1) {
      final fitted = (
        width: (targetWidth * scale).ceil().clamp(1, targetWidth),
        height: (targetHeight * scale).ceil().clamp(1, targetHeight),
      );
      if (fitted.width != targetWidth || fitted.height != targetHeight) {
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
      ..put(PdfName.filter, PdfName('DCTDecode'))
      ..put(PdfName.width, PdfNumber.fromInt(targetWidth))
      ..put(PdfName.height, PdfNumber.fromInt(targetHeight))
      ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
      ..put(PdfName('ColorSpace'),
          PdfName(samples.channels == 1 ? 'DeviceGray' : 'DeviceRGB'))
      ..remove(PdfName('DecodeParms'))
      ..markChanged();
    return current.length - candidate.length;
  }

  /// Channels implied by the image's colour space, or null when it is one this
  /// path does not re-encode.
  static Future<int?> _colourChannels(PdfStream image) async {
    final space = await image.get(PdfName('ColorSpace'), true);
    if (space == null) return null;
    if (space.objectKind() == PdfObjectType.name) {
      return switch ((space as PdfName).getValue()) {
        'DeviceGray' || 'G' || 'CalGray' => 1,
        'DeviceRGB' || 'RGB' || 'CalRGB' => 3,
        _ => null,
      };
    }
    if (space.objectKind() == PdfObjectType.array) {
      final array = space as PdfArray;
      final family = (await array.nameEntry(0))?.getValue();
      if (family == 'ICCBased') {
        final profile = await array.streamEntry(1);
        final n = await profile?.integerEntry(PdfName('N'));
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
    PdfStream image,
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

  static Future<Set<String>> _filterNames(PdfStream stream) async {
    final filter = await stream.get(PdfName.filter);
    if (filter == null) return const {};
    if (filter.objectKind() == PdfObjectType.name) {
      return {(filter as PdfName).getValue()};
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as PdfArray;
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
  static Future<bool> usesJbig2(PdfStream stream) async {
    final filter = await stream.get(PdfName.filter);
    if (filter == null) return false;
    if (filter.objectKind() == PdfObjectType.name) {
      return (filter as PdfName).getValue() == 'JBIG2Decode';
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as PdfArray;
      for (var i = 0; i < array.size(); i++) {
        if ((await array.nameEntry(i))?.getValue() == 'JBIG2Decode') {
          return true;
        }
      }
    }
    return false;
  }
}

class _BilevelImage {
  final PdfStream stream;
  final Uint8List raw;
  final Uint8List samples;
  final Jbig2Image image;

  const _BilevelImage(this.stream, this.raw, this.samples, this.image);
}

class _SharedJbig2Result {
  final Set<PdfStream> images;
  final int bytesSaved;

  const _SharedJbig2Result(this.images, this.bytesSaved);
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
PdfStream buildBilevelImage({
  required int width,
  required int height,
  required Uint8List packedRows,
  PdfName? filter,
  bool imageMask = false,
}) {
  final stream = PdfStream.withBytes(packedRows, 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Image'))
    ..put(PdfName.width, PdfNumber.fromInt(width))
    ..put(PdfName.height, PdfNumber.fromInt(height))
    ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(1));
  if (imageMask) {
    stream.put(PdfName('ImageMask'), PdfBoolean(true));
  } else {
    stream.put(PdfName('ColorSpace'), PdfName('DeviceGray'));
  }
  if (filter != null) stream.put(PdfName.filter, filter);
  return stream;
}
