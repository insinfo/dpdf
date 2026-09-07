# Changelog

## 1.0.0

Initial release. dpdf is implemented in pure Dart, uses no FFI or external
binaries, and targets the Dart VM, `dart2js`, and `dart2wasm`.

### Added

- PDF kernel with parsing, serialization, xref streams, object streams,
  incremental updates, encryption, fonts, forms, and annotations.
- High-level document layout and HTML-to-PDF conversion using embedded metrics
  for the 14 standard PDF fonts.
- SVG-to-PDF conversion for basic shapes and paths, transforms, `viewBox`,
  fill/stroke styling, opacity, and inline inheritance.
- PDF-to-PNG rendering through the web-safe `dgfx` rasterizer, including paths,
  arbitrary clipping, color spaces, images, masks, Form XObjects, and embedded
  TrueType/CFF glyph outlines. Rendering reports expose skipped work.
- A reusable `PdfContentParser`, including inline-image boundaries, and a
  `PdfImageDecoder` with 1-16-bit samples, `/Decode`, palettes, and masks.
- PDF function types 0, 2, 3, and 4 and RGB conversion for Device, calibrated,
  ICCBased, Lab, Indexed, Separation, and DeviceN color spaces.
- Pure-Dart PNG encoding, baseline/progressive JPEG decoding, baseline JPEG
  encoding, image resizing, and optional lossy image recompression.
- Structural PDF compression, deduplication, unreachable-object removal, and
  lossless bi-level image recompression using the smaller JBIG2 or Flate result.
- Integrity inspection and explicit PDF/A-1 through PDF/A-4 and PDF/UA-1
  verification reports.
- Text extraction, text and area redaction, page overlays and assembly, form
  merging, digital signatures, timestamps, OCSP, CRL, and JKS/BKS support.
- Code 39, Code 128, EAN/UPC, and QR Code generation.

### Fixed

- Prevented xref-stream rewrites from copying a stale `/Index` entry from the
  source trailer and corrupting externally produced or signed documents.
- Rejected append mode combined with full compression with a clear error.
- Corrected asynchronous dash-array serialization that could corrupt a content
  stream, and applied filter chains before JPEG decoding.
- Added MacRomanEncoding, embedded CMap support, standard-font AFM metrics, and
  an application font-fallback hook.
- Added complete progressive Huffman JPEG scans and made over-subscribed Huffman
  tables throw `JpegDecodeException` instead of a range error.
- Corrected PNG chunk CRCs and replaced `/JBIG2Decode` byte passthrough with real
  decoding.
- Removed a duplicate Pattern color-space stub and corrected ICC component
  counts.

### Breaking changes

- Removed the legacy `Craft` prefix from 481 API identifiers before the first
  publication. For example, `CraftPdfDocument`, `CraftPdfName`, and
  `CraftSvgConverter` became `PdfDocument`, `PdfName`, and `SvgConverter`.
- Renamed `CraftList` to `PdfList` instead of `List` to avoid shadowing Dart's
  core collection type.
