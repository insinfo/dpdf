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
- Text extraction reads the documents that real producers write: `gs` whose
  `/ExtGState` carries no `/Font` is ignored rather than refused, `DP`, `BX`
  and `EX` are stepped over, encodings named without a ToUnicode are honoured,
  and a ToUnicode is read at the code width the font imposes rather than at the
  width its `codespacerange` claims. Where a document draws a glyph it never
  identifies anywhere, extraction now yields U+FFFD instead of failing the
  page — an observable change of contract. Area redaction accepts the same
  `gs`, refusing only when the graphics state could change the current font.
- Fonts resolve by object rather than by resource name. A producer may reuse
  one short name for different fonts in different Form XObjects, and the old
  cache drew every one of them with whichever font it met first.
- Images drawn smaller than their source integrate the area they cover instead
  of point-sampling it; `/Interpolate` governs magnification, and minification
  without filtering drops one-pixel detail outright.
- The fourteen standard PDF fonts are drawn from bundled URW Core 35 faces when
  a document references them without embedding a program, so such a page is no
  longer blank; substitutions are named in the render report. Standard-font
  advance widths resolve by glyph name, so accented text under WinAnsiEncoding
  or MacRomanEncoding keeps its spacing instead of collapsing into one point.
- Clipping of filled vector artwork against a redaction area: curves are split
  at the parameters where they cross the edge and the hole is reclosed along
  the edge itself, preserving the winding rule for both `f` and `f*`. A
  *stroked* path that crosses an edge is still refused with an explicit
  message, because the pen paints half the width to either side of the
  geometry.
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
- Awaited the futures that the new `discarded_futures` and `unawaited_futures`
  lints exposed. A form-field flag setter returned before the flag was written,
  `PdfArray.remove` returned before the element was gone — so removing a field
  from an AcroForm left the widget in the page's `/Annots` and the field in its
  parent's `/Kids` — the signature appearance layer was attached after the
  field had already been added to the form, `TransparentColor` could emit its
  `/ExtGState` after the operators it governs, `setRenderingIntent` wrote the
  `ri` operator before the name it consumes, and the filter benchmark timed the
  creation of futures rather than the decoding.

### Breaking changes

- `Document.add`, `Canvas.add`, `showTextAligned` and `showTextAlignedParagraph`
  are synchronous and return the root element instead of a `Future`. They queue
  the element; the layout runs in `close`, which was already mandatory to await.
  Forgetting to await `add` used to drop the content with no error, no warning
  and no exception.

  ```dart
  // Before
  await document.add(Paragraph('First page.'));
  await document.add(AreaBreak(AreaBreakType.NEXT_PAGE));
  await document.close();

  // After
  document.add(Paragraph('First page.'));
  document.add(AreaBreak(AreaBreakType.NEXT_PAGE));
  await document.close();
  ```

  Three observable consequences. A layout error now reaches the caller from
  `close`, not from `add`; the queue is discarded when that happens, so the
  error is reported once. An element must not be mutated after it is added,
  because it is laid out as it stands at `close`. And `PdfDocument.close`
  refuses to run while a `Document` or `Canvas` built on it still holds queued
  content, replacing the silently empty file with an explicit error; the new
  `PendingLayoutContent` contract is what that check reads.

- Form-field flag setters return `Future<void>` instead of `void`, matching
  `setReadOnly` and the other setters on `PdfFormField` that already did:
  `setRadio`, `setToggleOff`, `setPushButton`, `setRadiosInUnison`, `setCombo`,
  `setEdit`, `setSort`, `setMultiSelect`, `setSpellCheck`,
  `setCommitOnSelChange`, `setTopIndex`, `setFileSelect`, `setScroll`,
  `setComb`, `setRichText`, `setBackgroundLayer` and
  `setSignatureAppearanceLayer`. They write the flag asynchronously, and the
  `void` signature hid that the write had not happened yet when they returned.
  `PdfCanvas.setRenderingIntent` and `TransparentColor.applyFillTransparency` /
  `applyStrokeTransparency` became asynchronous for the same reason.
- Removed the legacy `Craft` prefix from 481 API identifiers before the first
  publication. For example, `CraftPdfDocument`, `CraftPdfName`, and
  `CraftSvgConverter` became `PdfDocument`, `PdfName`, and `SvgConverter`.
- Renamed `CraftList` to `PdfList` instead of `List` to avoid shadowing Dart's
  core collection type.
