# dpdf

A pure-Dart toolkit for creating, reading, editing, rendering, compressing,
signing, and validating PDF documents. It uses no FFI or external binaries and
supports the Dart VM (JIT/AOT), `dart2js`, and `dart2wasm`.

```dart
import 'package:dpdf/dpdf.dart';
```

## Highlights

- PDF object model, xref tables and streams, object streams, incremental updates,
  standard encryption, forms, fonts, and annotations
- High-level layout with paragraphs, lists, tables, images, and page breaks
- HTML-to-PDF and SVG-to-PDF conversion
- PDF page rendering to RGBA pixels or PNG
- Text extraction, redaction, page assembly, overlays, and form merging
- Structural compression and optional image recompression
- Digital signatures, timestamping, OCSP, CRL, JKS, and BKS support
- Integrity checks and explicit PDF/A and PDF/UA verification reports

## HTML and SVG

```dart
final bytes = await HtmlConverter.convertToBytes('''
  <h1>Quarterly report</h1>
  <p>Generated entirely in Dart.</p>
  <table><tr><th>Item</th><th>Value</th></tr>
         <tr><td>Licenses</td><td>12,400</td></tr></table>
''');

final svgPdf = await SvgConverter.convertToBytes('''
  <svg width="200" height="100" viewBox="0 0 200 100">
    <rect x="10" y="10" width="180" height="80"
          fill="#eef" stroke="#225" stroke-width="2"/>
  </svg>
''');
```

SVG supports `svg`, `g`, `path`, `rect`, `circle`, `ellipse`, `line`,
`polyline`, and `polygon`, including transforms, `viewBox`, basic fill/stroke
styling, opacity, and inline style inheritance.

## Render PDF pages

```dart
final document = await PdfDocument.open(PdfReader.fromBytes(input));
final result = await PdfPageRenderer.render(document.getPage(1));
final png = result.toPng();
```

The renderer handles paths, arbitrary clipping, supported PDF color spaces,
image and Form XObjects, masks, and embedded font outlines. `PdfRenderReport`
identifies skipped work rather than silently claiming a complete rendering.
Applications may provide a font fallback for PDFs that omit font programs.

## Compress documents

```dart
final result = await PdfCompressor.compress(input);
print(result.report);
```

Compression can create object and xref streams, recompress streams, deduplicate
objects, and remove unreachable objects. If rewriting would make the document
larger, the original bytes are returned unchanged. Continuous-tone images are
only changed when explicitly requested:

```dart
final result = await PdfCompressor.compress(
  input,
  options: const PdfCompressionOptions(
    images: PdfImageCompressionOptions.lossy(
      quality: 75,
      targetDpi: 150,
      maxDimension: 2400,
    ),
  ),
);
```

`targetDpi` follows each image's effective placement through page and Form
XObject transformations; a reused image keeps the resolution needed by its
largest occurrence. `maxDimension` can additionally impose an absolute pixel
cap. Bi-level images are re-encoded losslessly and the smaller JBIG2 or Flate
representation is kept.

## Inspect and validate

```dart
final integrity = await PdfIntegrityChecker.inspect(input);
for (final finding in integrity.findings) {
  print(finding);
}

final pdfa = await PdfAVerifier.verify(
  input,
  level: PdfAConformanceLevel.a2b,
);
print(pdfa.violations);
print(pdfa.unverifiedRules);
```

Integrity checks cover headers, EOF markers, `startxref`, byte-accurate xref
offsets, reachable pages, cycles, truncated streams, and filter failures.
Conformance reports are not certifications: `unverifiedRules` lists checks
outside the verifier's scope.

## Redact content

```dart
final redacted = await PdfAreaRedaction.apply(input, [
  PdfRedactionArea(1, left: 70, bottom: 675, right: 300, top: 693),
]);
```

Area redaction removes matching text, replaces covered pixels in uniquely
referenced opaque page images, and draws an opaque cover. Shared images,
transparency and images nested in Form XObjects are conservatively left intact
under the cover. `PdfTextRedaction` offers a stricter reconstruction path and
rejects documents it cannot safely rebuild.

## JPEG support

`JpegDecoder` supports baseline and progressive Huffman JPEG, grayscale, RGB,
Adobe CMYK/YCCK, common chroma subsampling, successive approximation, EOB runs,
and restart markers. Arithmetic, lossless, and hierarchical JPEG are not yet
supported. `JpegEncoder` writes baseline JPEG with configurable quality and
subsampling.

## Known limitations

- SVG colored tiling patterns and luminance/alpha masks are emitted as native
  PDF pattern and soft-mask resources. Gradient stop opacity uses an aligned
  shading soft mask; some marker viewport and advanced paint-server cases
  remain partial.
- PDF rendering may require a supplied fallback for fonts that are not embedded.
  CID-keyed CFF supports FDArray/FDSelect and charset CID-to-GID mapping; CFF2
  and PatternType 2 shading-pattern cases remain partial.
  Colored/uncolored tiling patterns and patterned strokes render. Alpha and
  luminosity soft masks render; transfer functions and some advanced
  transparency-group replacement cases remain partial.
- Area redaction of shared, transparent or Form-nested images still covers
  rather than rewriting their source pixels.
- HTML uses the 14 standard PDF fonts and does not discover system fonts.
- JBIG2 automatically chooses between generic regions and deduplicated symbol
  dictionaries with text regions; refinement and multi-page dictionaries remain
  partial.

Optional reading, recovery, merge, and signing modes are documented in
[test/compatibility/OPTIONAL_MODES.md](test/compatibility/OPTIONAL_MODES.md).

## Development

```bash
dart analyze
dart test
dart run tool/check_platforms.dart
```

The platform check covers VM/JIT, VM/AOT, `dart2js`, and `dart2wasm`; Wasm
requires Node.js with WasmGC support. To regenerate the embedded Adobe glyph and
standard-font metric resources, run `dart run tool/generate_font_resources.dart`.

## License

MIT. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for notices covering
embedded third-party data.
