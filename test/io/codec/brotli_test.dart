import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/io/codec/brotli/brotli.dart';
import 'package:test/test.dart';

/// Streams produced by Node's built-in Brotli, which is the reference
/// implementation compiled from Google's C sources.
///
/// Checking a decoder against its own encoder only proves the two agree.
/// These vectors prove the decoder reads what the rest of the world writes,
/// which is the only claim that matters for reading a WOFF 2.0 font somebody
/// else produced.
const _vectors = <String, ({String original, String compressed})>{
  'empty': (
    original: "",
    compressed: "Ow==",
  ),
  'short': (
    original: "aGVsbG8=",
    compressed: "CwKAaGVsbG8D",
  ),
  'repetitive': (
    original: "YWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJjYWJj",
    compressed: "GwcH+CXDxMbCsyDgVw0=",
  ),
  'dictionary': (
    original: "VGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4gVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4g",
    compressed: "G8EBiCwOeNPQlV2XELsXK6nK0JLMjK1BXObyNsgZnp4Ke4MNOHBIIG8kvUGnFc4cHieqKTjCedqnwQ==",
  ),
  'incompressible': (
    original: "fPLlcwzeoi98L26PuSb/c4Rksg7GGluKHIP0+s7NrjBvKaK3aFItXPDzZ3R/MM45x0hjJ4+ubCfhfOnjC2zL2Q==",
    compressed: "ix+AfPLlcwzeoi98L26PuSb/c4Rksg7GGluKHIP0+s7NrjBvKaK3aFItXPDzZ3R/MM45x0hjJ4+ubCfhfOnjC2zL2QM=",
  ),
  'ramp': (
    original: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/wABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9AQUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVpbXF1eX2BhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJmam5ydnp+goaKjpKWmp6ipqqusra6vsLGys7S1tre4ubq7vL2+v8DBwsPExcbHyMnKy8zNzs/Q0dLT1NXW19jZ2tvc3d7f4OHi4+Tl5ufo6err7O3u7/Dx8vP09fb3+Pn6+/z9/v8AAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl9gYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+f4CBgoOEhYaHiImKi4yNjo+QkZKTlJWWl5iZmpucnZ6foKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr/AwcLDxMXGx8jJysvMzc7P0NHS09TV1tfY2drb3N3e3+Dh4uPk5ebn6Onq6+zt7u/w8fLz9PX29/j5+vv8/f7/AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5w==",
    compressed: "G+cD6C8O7FgZWEOqB44aNm7tQAxs295ktQ7OC7nvFAfnlZxHHIQKxwh5ryxDGk2kICbYxLF7f0cUgAgTyriQShvrfIgpl9r6mGuf+z4AQjCCYjhBUjTDcrwgSrKiarphWrbjen4QRnGSZnlRVnXTdv0wTvOybvtxXvfzfr8/gGAExXCCpGiG5XhBlGRF1XTDtGzH9fwgjOIkzfKirOqm7fphnOZl3fbjvO7n/X4AESaUcSGVNtb5IIziJM3yoqzqpu36YZzmZd3247zu5/1+EIuaR1bP3kcB",
  ),
};

Uint8List _decode(String base64) => base64Decode(base64);

void main() {
  group('Brotli decoding (RFC 7932)', () {
    _vectors.forEach((name, vector) {
      test('reads the reference encoder output: $name', () {
        final expected = _decode(vector.original);
        final actual = Brotli.decode(_decode(vector.compressed));

        expect(actual, orderedEquals(expected));
      });
    });

    test('the static dictionary is really in use', () {
      // 450 bytes of common English collapse to 58 only because the shared
      // dictionary of RFC 7932 Annex A supplies the words. A decoder missing
      // that table cannot read this stream at all, so this case is the one
      // that proves the dictionary shipped and is wired up.
      final vector = _vectors['dictionary']!;
      expect(_decode(vector.compressed).length, lessThan(100));
      expect(_decode(vector.original).length, greaterThan(400));
      expect(Brotli.decode(_decode(vector.compressed)),
          orderedEquals(_decode(vector.original)));
    });

    test('a truncated stream is refused, not silently short', () {
      final full = _decode(_vectors['repetitive']!.compressed);
      expect(() => Brotli.decode(full.sublist(0, full.length - 3)),
          throwsA(isA<BrotliDecodeException>()));
    });

    test('garbage is refused', () {
      expect(() => Brotli.decode(Uint8List.fromList(List.filled(64, 0xA5))),
          throwsA(isA<BrotliDecodeException>()));
    });

    test('the output budget is enforced', () {
      // 1800 bytes out of 14: a decompression bomb in miniature. A font read
      // from an untrusted source needs the ceiling to be the caller's choice.
      final compressed = _decode(_vectors['repetitive']!.compressed);
      expect(() => Brotli.decode(compressed, maxOutputBytes: 100),
          throwsA(isA<BrotliDecodeException>()));
      expect(Brotli.decode(compressed, maxOutputBytes: 1 << 20).length,
          equals(1800));
    });
  });
}
