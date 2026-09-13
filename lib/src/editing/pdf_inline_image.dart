part of 'pdf_text_extraction.dart';

/// One `BI ... ID <bytes> EI` object located inside a content stream.
///
/// [dataStart] and [dataEnd] bound the raw samples; [end] is the offset just
/// past the closing `EI`, which is where scanning of ordinary operators must
/// resume.
class _InlineImageScan {
  final Map<String, Object> entries;
  final int dataStart, dataEnd, end;

  const _InlineImageScan(this.entries, this.dataStart, this.dataEnd, this.end);
}

/// Locates the end of an inline image (ISO 32000-1, 8.9.7 and Table 93).
///
/// An inline image declares no `/Length`, so a reader has to work out where
/// the samples stop. Two rules do that, and both are needed:
///
/// * With no filter the byte count follows from `/W`, `/H`, `/BPC` and `/CS`
///   (Table 93 abbreviations, Table 94 colour-space abbreviations), so the
///   payload is skipped by length and `EI` is then *verified*, never searched
///   for. Data that happens to contain `EI`, even surrounded by whitespace,
///   cannot mislead this path.
/// * With a filter the length is unknown, so candidate `EI` tokens are
///   scanned for — each has to be preceded by whitespace and followed by a
///   delimiter or end of stream — and every candidate is then validated
///   against the declared filter. A candidate whose payload does not decode,
///   or does not decode to the declared sample count, is rejected and the
///   scan continues. That is what keeps an `EI` sitting inside compressed
///   data from truncating the image.
extension _InlineImages on _ContentTokens {
  /// Reads the key/value pairs, the samples and the closing `EI`, leaving
  /// [position] just past `EI`. Called with [position] just past `BI`.
  _InlineImageScan readInlineImage() {
    final entries = <String, Object>{};
    while (true) {
      final token = next();
      if (token == null) {
        throw FormatException('Inline image is missing its ID operator.');
      }
      if (token is _Operator) {
        if (token.value == 'ID') break;
        if (token.value == 'BI') {
          throw FormatException('Inline images cannot be nested.');
        }
        throw FormatException(
            'Inline image dictionary has the operator ${token.value}.');
      }
      if (token is! _Name) {
        throw FormatException('Inline image keys must be names.');
      }
      final value = next();
      if (value == null || value is _Operator) {
        throw FormatException('Inline image key /${token.value} has no value.');
      }
      if (entries.containsKey(token.value)) {
        throw FormatException('Duplicate inline image key /${token.value}.');
      }
      entries[token.value] = value;
    }

    final filters = _inlineFilters(entries);
    // 8.9.7: ID is followed by a single white-space byte, except when the
    // data is ASCII-armoured, where leading whitespace is not part of it.
    if (filters.isNotEmpty &&
        (filters.first == 'ASCIIHexDecode' ||
            filters.first == 'ASCII85Decode')) {
      while (position < bytes.length && space(bytes[position])) {
        position++;
      }
    } else if (position < bytes.length && space(bytes[position])) {
      position++;
    } else {
      throw FormatException('ID must be followed by one white-space byte.');
    }

    final start = position;
    final declared = _inlineSampleLength(entries);
    if (filters.isEmpty) {
      if (declared == null) {
        throw UnsupportedError(
            'An unfiltered inline image needs /W, /H, /BPC and a device /CS '
            'to bound its data.');
      }
      final dataEnd = start + declared;
      if (dataEnd > bytes.length) {
        throw FormatException('Inline image data is truncated.');
      }
      final after = _inlineTerminator(dataEnd);
      if (after < 0) {
        throw FormatException(
            'Inline image data does not end at the EI operator; its length '
            'disagrees with /W, /H, /BPC and /CS.');
      }
      position = after;
      return _InlineImageScan(entries, start, dataEnd, after);
    }

    for (var i = start; i + 1 < bytes.length; i++) {
      if (bytes[i] != 0x45 || bytes[i + 1] != 0x49) continue; // 'E', 'I'
      if (i == start || !space(bytes[i - 1])) continue;
      final after = i + 2;
      if (after < bytes.length && !delimiter(bytes[after])) continue;
      var dataEnd = i;
      while (dataEnd > start && space(bytes[dataEnd - 1])) {
        dataEnd--;
      }
      if (!_inlineDataIsComplete(
          filters, Uint8List.sublistView(bytes, start, dataEnd), declared)) {
        continue;
      }
      position = after;
      return _InlineImageScan(entries, start, dataEnd, after);
    }
    throw FormatException('Inline image has no EI operator.');
  }

  /// Returns the offset past `EI` when the bytes at [from], after optional
  /// whitespace, are `EI` followed by a delimiter; otherwise -1.
  int _inlineTerminator(int from) {
    var at = from;
    while (at < bytes.length && space(bytes[at])) {
      at++;
    }
    if (at + 1 >= bytes.length) return -1;
    if (bytes[at] != 0x45 || bytes[at + 1] != 0x49) return -1;
    final after = at + 2;
    if (after < bytes.length && !delimiter(bytes[after])) return -1;
    return after;
  }
}

/// Table 94 filter abbreviations expanded to their full names.
const Map<String, String> _inlineFilterNames = {
  'AHx': 'ASCIIHexDecode',
  'A85': 'ASCII85Decode',
  'LZW': 'LZWDecode',
  'Fl': 'FlateDecode',
  'RL': 'RunLengthDecode',
  'CCF': 'CCITTFaxDecode',
  'DCT': 'DCTDecode',
};

/// Table 94 colour-space abbreviations and their component counts. A named
/// resource colour space is absent here on purpose: its component count is not
/// known from the content stream alone.
const Map<String, int> _inlineColourComponents = {
  'G': 1,
  'DeviceGray': 1,
  'RGB': 3,
  'DeviceRGB': 3,
  'CMYK': 4,
  'DeviceCMYK': 4,
  'I': 1,
  'Indexed': 1,
};

List<String> _inlineFilters(Map<String, Object> entries) {
  final value = entries['F'] ?? entries['Filter'];
  if (value == null) return const [];
  final names = <String>[];
  if (value is _Name) {
    names.add(value.value);
  } else if (value is List<Object>) {
    for (final item in value) {
      if (item is! _Name) {
        throw FormatException('Inline image /F must hold filter names.');
      }
      names.add(item.value);
    }
  } else {
    throw FormatException('Inline image /F must be a name or an array.');
  }
  return [for (final name in names) _inlineFilterNames[name] ?? name];
}

/// Unfiltered sample count in bytes, or null when the entries do not pin it
/// down (a named colour space, a missing dimension, a bad value).
int? _inlineSampleLength(Map<String, Object> entries) {
  final width = entries['W'] ?? entries['Width'];
  final height = entries['H'] ?? entries['Height'];
  if (width is! num || height is! num) return null;
  if (width != width.roundToDouble() || height != height.roundToDouble()) {
    return null;
  }
  final w = width.toInt(), h = height.toInt();
  if (w <= 0 || h <= 0 || w > 1 << 24 || h > 1 << 24) return null;

  final mask = entries['IM'] ?? entries['ImageMask'];
  if (mask != null && mask is! bool) return null;
  var bits = 8, components = 1;
  if (mask == true) {
    // 8.9.6.2: a stencil mask is one bit per sample and has no colour space.
    bits = 1;
  } else {
    final depth = entries['BPC'] ?? entries['BitsPerComponent'];
    if (depth is! num) return null;
    bits = depth.toInt();
    if (!const [1, 2, 4, 8, 16].contains(bits)) return null;
    final space = entries['CS'] ?? entries['ColorSpace'];
    if (space is _Name) {
      final count = _inlineColourComponents[space.value];
      if (count == null) return null;
      components = count;
    } else if (space is List<Object> &&
        space.isNotEmpty &&
        space.first is _Name &&
        const {'I', 'Indexed'}.contains((space.first as _Name).value)) {
      components = 1;
    } else {
      return null;
    }
  }
  final row = (w * components * bits + 7) ~/ 8;
  return row * h;
}

/// True when [data] is a plausible whole payload for [filters].
///
/// Only the outermost filter — the one a reader would apply first — can be
/// checked against the raw bytes. Filters this cannot cheaply verify accept
/// the candidate, which is the behaviour of every reader; the verifiable ones
/// are what make an `EI` embedded in the data harmless.
bool _inlineDataIsComplete(
    List<String> filters, Uint8List data, int? declared) {
  final expected = filters.length == 1 ? declared : null;
  switch (filters.first) {
    case 'ASCIIHexDecode':
      var digits = 0;
      var closed = false;
      for (final byte in data) {
        if (byte == 0x3E) {
          closed = true;
          break;
        }
        if (_isInlineSpace(byte)) continue;
        if (!_isHexDigit(byte)) return false;
        digits++;
      }
      if (!closed) return false;
      return expected == null || (digits + 1) ~/ 2 == expected;
    case 'ASCII85Decode':
      var end = data.length;
      while (end > 0 && _isInlineSpace(data[end - 1])) {
        end--;
      }
      return end >= 2 && data[end - 2] == 0x7E && data[end - 1] == 0x3E;
    case 'FlateDecode':
      try {
        final decoded = zlib.decode(data);
        return expected == null || decoded.length == expected;
      } catch (_) {
        return false;
      }
    case 'RunLengthDecode':
      var at = 0, produced = 0;
      while (at < data.length) {
        final length = data[at++];
        if (length == 128) {
          return at == data.length &&
              (expected == null || produced == expected);
        }
        if (length < 128) {
          at += length + 1;
          produced += length + 1;
        } else {
          at += 1;
          produced += 257 - length;
        }
        if (at > data.length) return false;
      }
      // A payload without the 128 end-of-data byte is only whole if the
      // declared sample count is already met.
      return expected != null && produced == expected;
    case 'DCTDecode':
      var end = data.length;
      while (end > 0 && _isInlineSpace(data[end - 1])) {
        end--;
      }
      return end >= 4 &&
          data[0] == 0xFF &&
          data[1] == 0xD8 &&
          data[end - 2] == 0xFF &&
          data[end - 1] == 0xD9;
    default:
      // LZWDecode and CCITTFaxDecode carry no cheap integrity check.
      return true;
  }
}

bool _isInlineSpace(int c) =>
    c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);
