import 'dart:typed_data';

import 'package:j2k/j2k.dart' as j2k;

import '../io/image/jpeg_decoder.dart';
import '../kernel/pdf/colorspace/pdf_color_space.dart';
import '../kernel/pdf/colorspace/pdf_special_cs.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_stream.dart';

/// An image XObject resolved to pixels a rasterizer can draw.
class PdfDecodedImage {
  final int width;
  final int height;

  /// Straight-alpha RGBA, four bytes per pixel, row major. Null for a stencil.
  final Uint8List? rgba;

  /// For an `/ImageMask`: 255 where the image paints the current fill colour
  /// and 0 where it leaves the page alone.
  ///
  /// A stencil carries no colour of its own, which is why it is kept separate
  /// rather than expanded into [rgba] with a colour the decoder cannot know.
  final Uint8List? stencil;

  const PdfDecodedImage({
    required this.width,
    required this.height,
    this.rgba,
    this.stencil,
  });

  bool get isStencil => stencil != null;

  @override
  String toString() =>
      'PdfDecodedImage(${width}x$height, ${isStencil ? 'stencil' : 'rgba'})';
}

/// Turns an image XObject into pixels.
///
/// This is the layer between the filters, which give bytes, and a rasterizer,
/// which wants RGBA. It unpacks samples of any depth, applies `/Decode`,
/// resolves the colour space for every pixel, and folds `/SMask` and a stencil
/// `/Mask` into the alpha channel.
abstract final class PdfImageDecoder {
  /// Decodes [image]. Returns null when the image uses something this decoder
  /// does not read, rather than throwing, so one image cannot fail a page.
  static Future<PdfDecodedImage?> decode(CraftPdfStream image) async {
    try {
      return await _decode(image);
    } on Object {
      return null;
    }
  }

  static Future<PdfDecodedImage?> _decode(CraftPdfStream image) async {
    final width = await image.integerEntry(CraftPdfName.width);
    final height = await image.integerEntry(CraftPdfName.height);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    if (width * height > _maxPixels) return null;

    final isMask = await image.flagEntry(CraftPdfName('ImageMask')) ?? false;
    if (isMask) return _decodeStencil(image, width, height);

    final filters = await _filterNames(image);

    // A JPEG or JPEG 2000 stream carries its own colour interpretation, so it
    // bypasses the sample unpacking below.
    if (filters.contains('DCTDecode') || filters.contains('DCT')) {
      final jpeg = await _decodeJpeg(image, width, height);
      if (jpeg != null) return await _withAlpha(image, jpeg);
    } else if (filters.contains('JPXDecode')) {
      final jpx = await _decodeJpx(image, width, height);
      if (jpx != null) return await _withAlpha(image, jpx);
    }

    final bits = await image.integerEntry(CraftPdfName('BitsPerComponent'));
    if (bits == null || !const [1, 2, 4, 8, 16].contains(bits)) return null;

    final space = await CraftPdfColorSpace.makeColorSpace(
        await image.get(CraftPdfName('ColorSpace'), true));
    if (space == null) return null;
    final channels = space.getNumberOfComponents();
    if (channels < 1 || channels > 4) return null;

    final samples = await image.getBytes();
    if (samples == null) return null;

    final decode = await _decodeArray(image, space, channels, bits);
    final rgba = _expand(
      samples: samples,
      width: width,
      height: height,
      bits: bits,
      channels: channels,
      space: space,
      decode: decode,
    );
    if (rgba == null) return null;

    return await _withAlpha(
        image, PdfDecodedImage(width: width, height: height, rgba: rgba));
  }

  /// A page-sized image at 600 dpi is about 35 million pixels; beyond this a
  /// caller is almost certainly reading a corrupt dictionary.
  static const int _maxPixels = 80 * 1000 * 1000;

  // --- stencil masks --------------------------------------------------------

  static Future<PdfDecodedImage?> _decodeStencil(
      CraftPdfStream image, int width, int height) async {
    final samples = await image.getBytes();
    if (samples == null) return null;

    // The default for a stencil is [0 1]: a 0 bit paints. /Decode [1 0]
    // inverts that.
    final decode = await image.arrayEntry(CraftPdfName('Decode'));
    var paintsOnZero = true;
    if (decode != null && decode.size() >= 1) {
      final first = await decode.get(0);
      if (first is CraftPdfNumber && first.doubleValue() == 1) {
        paintsOnZero = false;
      }
    }

    final stride = (width + 7) >> 3;
    if (samples.length < stride * height) return null;

    final stencil = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * stride;
      final out = y * width;
      for (var x = 0; x < width; x++) {
        final bit = (samples[row + (x >> 3)] >> (7 - (x & 7))) & 1;
        stencil[out + x] = (bit == 0) == paintsOnZero ? 255 : 0;
      }
    }
    return PdfDecodedImage(width: width, height: height, stencil: stencil);
  }

  // --- already-decoded codecs ----------------------------------------------

  static Future<PdfDecodedImage?> _decodeJpeg(
      CraftPdfStream image, int width, int height) async {
    final raw = await image.getRawBytes();
    if (raw == null) return null;
    final jpeg = JpegDecoder.decode(raw);
    final rgba = Uint8List(jpeg.width * jpeg.height * 4);

    switch (jpeg.format) {
      case JpegPixelFormat.grayscale:
        for (var i = 0, at = 0; i < jpeg.pixels.length; i++, at += 4) {
          final v = jpeg.pixels[i];
          rgba[at] = v;
          rgba[at + 1] = v;
          rgba[at + 2] = v;
          rgba[at + 3] = 255;
        }
      case JpegPixelFormat.rgb:
        for (var i = 0, at = 0; at < rgba.length; i += 3, at += 4) {
          rgba[at] = jpeg.pixels[i];
          rgba[at + 1] = jpeg.pixels[i + 1];
          rgba[at + 2] = jpeg.pixels[i + 2];
          rgba[at + 3] = 255;
        }
      case JpegPixelFormat.cmyk:
        // Adobe writes CMYK JPEG inverted, which is what the APP14 marker
        // records; a /Decode array in the PDF can invert it a second time.
        final inverted = jpeg.adobeInverted;
        for (var i = 0, at = 0; at < rgba.length; i += 4, at += 4) {
          var c = jpeg.pixels[i] / 255.0;
          var m = jpeg.pixels[i + 1] / 255.0;
          var y = jpeg.pixels[i + 2] / 255.0;
          var k = jpeg.pixels[i + 3] / 255.0;
          if (inverted) {
            c = 1 - c;
            m = 1 - m;
            y = 1 - y;
            k = 1 - k;
          }
          rgba[at] = (255 * (1 - c) * (1 - k)).round().clamp(0, 255);
          rgba[at + 1] = (255 * (1 - m) * (1 - k)).round().clamp(0, 255);
          rgba[at + 2] = (255 * (1 - y) * (1 - k)).round().clamp(0, 255);
          rgba[at + 3] = 255;
        }
    }
    return PdfDecodedImage(width: jpeg.width, height: jpeg.height, rgba: rgba);
  }

  static Future<PdfDecodedImage?> _decodeJpx(
      CraftPdfStream image, int width, int height) async {
    final raw = await image.getRawBytes();
    if (raw == null) return null;
    final decoded = j2k.decodeJpeg2000(raw);
    final count = decoded.width * decoded.height;
    final channels = decoded.components;
    final rgba = Uint8List(count * 4);

    for (var i = 0, at = 0; i < count; i++, at += 4) {
      final base = i * channels;
      switch (channels) {
        case 1:
          final v = decoded.pixels[base];
          rgba[at] = v;
          rgba[at + 1] = v;
          rgba[at + 2] = v;
          rgba[at + 3] = 255;
        case 2:
          final v = decoded.pixels[base];
          rgba[at] = v;
          rgba[at + 1] = v;
          rgba[at + 2] = v;
          rgba[at + 3] = decoded.pixels[base + 1];
        case 3:
          rgba[at] = decoded.pixels[base];
          rgba[at + 1] = decoded.pixels[base + 1];
          rgba[at + 2] = decoded.pixels[base + 2];
          rgba[at + 3] = 255;
        case 4:
          rgba[at] = decoded.pixels[base];
          rgba[at + 1] = decoded.pixels[base + 1];
          rgba[at + 2] = decoded.pixels[base + 2];
          rgba[at + 3] = decoded.pixels[base + 3];
        default:
          return null;
      }
    }
    return PdfDecodedImage(
        width: decoded.width, height: decoded.height, rgba: rgba);
  }

  // --- sample unpacking -----------------------------------------------------

  /// The `/Decode` array, defaulted per the colour space when absent.
  static Future<Float64List> _decodeArray(
    CraftPdfStream image,
    CraftPdfColorSpace space,
    int channels,
    int bits,
  ) async {
    final result = Float64List(channels * 2);
    final indexed = space is PdfSpecialCsIndexed;
    for (var i = 0; i < channels; i++) {
      if (indexed) {
        // An Indexed image's samples are palette indices, not colour values.
        result[i * 2] = 0;
        result[i * 2 + 1] = ((1 << bits) - 1).toDouble();
        continue;
      }
      final range = space.getComponentRange(i);
      result[i * 2] = range[0];
      result[i * 2 + 1] = range[1];
    }

    final declared = await image.arrayEntry(CraftPdfName('Decode'));
    if (declared != null && declared.size() >= channels * 2) {
      for (var i = 0; i < channels * 2; i++) {
        final value = await declared.get(i);
        if (value is CraftPdfNumber && value.doubleValue().isFinite) {
          result[i] = value.doubleValue();
        }
      }
    }
    return result;
  }

  static Uint8List? _expand({
    required Uint8List samples,
    required int width,
    required int height,
    required int bits,
    required int channels,
    required CraftPdfColorSpace space,
    required Float64List decode,
  }) {
    final stride = (width * channels * bits + 7) >> 3;
    if (samples.length < stride * height) return null;

    final maximum = ((1 << bits) - 1).toDouble();
    final rgba = Uint8List(width * height * 4);

    // One channel at 8 bits or fewer has at most 256 distinct colours, so the
    // whole conversion collapses to a lookup. That covers Indexed and grey,
    // which between them are most of the images in a real document.
    Uint8List? palette;
    if (channels == 1) {
      final entries = 1 << bits;
      palette = Uint8List(entries * 3);
      for (var value = 0; value < entries; value++) {
        final component = decode[0] + value * (decode[1] - decode[0]) / maximum;
        final rgb = space.toRgb([component]);
        palette[value * 3] = (rgb[0] * 255).round().clamp(0, 255);
        palette[value * 3 + 1] = (rgb[1] * 255).round().clamp(0, 255);
        palette[value * 3 + 2] = (rgb[2] * 255).round().clamp(0, 255);
      }
    }

    final components = List<double>.filled(channels, 0);
    final reader = _BitReader(samples, bits);

    for (var y = 0; y < height; y++) {
      reader.seekToBit(y * stride * 8);
      var at = y * width * 4;
      for (var x = 0; x < width; x++, at += 4) {
        if (palette != null) {
          final index = reader.read() * 3;
          rgba[at] = palette[index];
          rgba[at + 1] = palette[index + 1];
          rgba[at + 2] = palette[index + 2];
          rgba[at + 3] = 255;
          continue;
        }
        for (var c = 0; c < channels; c++) {
          final raw = reader.read();
          components[c] = decode[c * 2] +
              raw * (decode[c * 2 + 1] - decode[c * 2]) / maximum;
        }
        final rgb = space.toRgb(components);
        rgba[at] = (rgb[0] * 255).round().clamp(0, 255);
        rgba[at + 1] = (rgb[1] * 255).round().clamp(0, 255);
        rgba[at + 2] = (rgb[2] * 255).round().clamp(0, 255);
        rgba[at + 3] = 255;
      }
    }
    return rgba;
  }

  // --- transparency ---------------------------------------------------------

  /// Folds an `/SMask` or a stencil `/Mask` into the alpha channel.
  static Future<PdfDecodedImage> _withAlpha(
      CraftPdfStream image, PdfDecodedImage decoded) async {
    final rgba = decoded.rgba;
    if (rgba == null) return decoded;

    final soft = await image.streamEntry(CraftPdfName('SMask'));
    if (soft != null) {
      final alpha = await _softMaskAlpha(soft);
      if (alpha != null) {
        _applyAlpha(rgba, decoded.width, decoded.height, alpha.samples,
            alpha.width, alpha.height);
      }
      return decoded;
    }

    final mask = await image.get(CraftPdfName('Mask'), true);
    if (mask is CraftPdfStream) {
      final stencil = await _decodeStencil(
        mask,
        await mask.integerEntry(CraftPdfName.width) ?? 0,
        await mask.integerEntry(CraftPdfName.height) ?? 0,
      );
      final samples = stencil?.stencil;
      if (samples != null) {
        // A /Mask paints where the stencil says *not* to, which is the
        // opposite of an /ImageMask used as a drawing operator.
        final inverted = Uint8List(samples.length);
        for (var i = 0; i < samples.length; i++) {
          inverted[i] = 255 - samples[i];
        }
        _applyAlpha(rgba, decoded.width, decoded.height, inverted,
            stencil!.width, stencil.height);
      }
    }
    return decoded;
  }

  static Future<({Uint8List samples, int width, int height})?> _softMaskAlpha(
      CraftPdfStream mask) async {
    final width = await mask.integerEntry(CraftPdfName.width);
    final height = await mask.integerEntry(CraftPdfName.height);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final decoded = await decode(mask);
    if (decoded?.rgba == null) return null;

    // A soft mask is DeviceGray, so any channel of the decoded RGBA is the
    // coverage value.
    final rgba = decoded!.rgba!;
    final alpha = Uint8List(decoded.width * decoded.height);
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = rgba[i * 4];
    }
    return (samples: alpha, width: decoded.width, height: decoded.height);
  }

  /// Writes [alpha] into the alpha channel of [rgba], scaling when the mask
  /// has its own resolution, which the format allows.
  static void _applyAlpha(Uint8List rgba, int width, int height,
      Uint8List alpha, int alphaWidth, int alphaHeight) {
    if (alphaWidth <= 0 || alphaHeight <= 0) return;
    for (var y = 0; y < height; y++) {
      final sy = alphaHeight == height ? y : y * alphaHeight ~/ height;
      final row = sy * alphaWidth;
      var at = y * width * 4 + 3;
      for (var x = 0; x < width; x++, at += 4) {
        final sx = alphaWidth == width ? x : x * alphaWidth ~/ width;
        rgba[at] = alpha[row + sx];
      }
    }
  }

  // --- helpers --------------------------------------------------------------

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
}

/// Reads fixed-width fields from a packed byte buffer, most significant bit
/// first, which is how PDF stores image samples.
class _BitReader {
  final Uint8List data;
  final int bits;
  int _bit = 0;

  _BitReader(this.data, this.bits);

  void seekToBit(int bit) => _bit = bit;

  int read() {
    // The byte-aligned widths are the common ones and are worth not paying
    // the general loop for.
    if (bits == 8) {
      final index = _bit >> 3;
      _bit += 8;
      return index < data.length ? data[index] : 0;
    }
    if (bits == 16) {
      final index = _bit >> 3;
      _bit += 16;
      if (index + 1 >= data.length) return 0;
      return (data[index] << 8) | data[index + 1];
    }

    var value = 0;
    for (var i = 0; i < bits; i++) {
      final index = _bit >> 3;
      final bit =
          index < data.length ? (data[index] >> (7 - (_bit & 7))) & 1 : 0;
      value = (value << 1) | bit;
      _bit++;
    }
    return value;
  }
}

/// Reads an inline image, whose dictionary uses the abbreviated keys of
/// ISO 32000-1 Table 93 rather than the full XObject ones.
///
/// The abbreviations exist because an inline image's dictionary is repeated in
/// the content stream for every occurrence, so the format traded readability
/// for bytes.
CraftPdfStream inlineImageToStream(
    CraftPdfDictionary dictionary, Uint8List data) {
  const expansions = {
    'BPC': 'BitsPerComponent',
    'CS': 'ColorSpace',
    'D': 'Decode',
    'DP': 'DecodeParms',
    'F': 'Filter',
    'H': 'Height',
    'IM': 'ImageMask',
    'I': 'Interpolate',
    'W': 'Width',
    'L': 'Length',
  };
  const colourSpaces = {
    'G': 'DeviceGray',
    'RGB': 'DeviceRGB',
    'CMYK': 'DeviceCMYK',
    'I': 'Indexed',
  };
  const filters = {
    'AHx': 'ASCIIHexDecode',
    'A85': 'ASCII85Decode',
    'LZW': 'LZWDecode',
    'Fl': 'FlateDecode',
    'RL': 'RunLengthDecode',
    'CCF': 'CCITTFaxDecode',
    'DCT': 'DCTDecode',
  };

  CraftPdfObject expand(String key, CraftPdfObject value) {
    if (value is CraftPdfName) {
      if (key == 'CS' || key == 'ColorSpace') {
        return CraftPdfName(colourSpaces[value.getValue()] ?? value.getValue());
      }
      if (key == 'F' || key == 'Filter') {
        return CraftPdfName(filters[value.getValue()] ?? value.getValue());
      }
    }
    if (value is CraftPdfArray && (key == 'F' || key == 'Filter')) {
      final out = CraftPdfArray();
      for (final item in value.subList(0, value.size())) {
        out.add(item is CraftPdfName
            ? CraftPdfName(filters[item.getValue()] ?? item.getValue())
            : item);
      }
      return out;
    }
    return value;
  }

  final stream = CraftPdfStream.withBytes(data, 0);
  for (final entry in dictionary.getMap()?.entries ??
      const <MapEntry<CraftPdfName, CraftPdfObject>>[]) {
    final key = entry.key.getValue();
    stream.put(CraftPdfName(expansions[key] ?? key), expand(key, entry.value));
  }
  stream.put(CraftPdfName.subtype, CraftPdfName('Image'));
  return stream;
}
