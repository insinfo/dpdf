# Examples

| File | What it shows |
| --- | --- |
| [`dpdf_example.dart`](dpdf_example.dart) | The main tour: HTML to PDF, integrity inspection, PDF/A conformance and area redaction. |
| [`html_showcase.dart`](html_showcase.dart) | Elaborate HTML with CSS, a table, a JPEG, inline vector SVG and the Lato face downloaded from Google Fonts. |
| [`text_editing.dart`](text_editing.dart) | Text editing and replacement within the strict subset, without reflow. |
| [`keystore_smoke.dart`](keystore_smoke.dart) | Reading JKS and BKS key stores from bytes. |
| [`platform_smoke.dart`](platform_smoke.dart) | Creation, extraction, merging, RSA/CMS signing and codecs, used to validate the VM, `dart2js` and `dart2wasm`. |

Run any of them from the root of the package:

```bash
dart run example/dpdf_example.dart
dart run example/html_showcase.dart build/html_showcase.pdf
```

The main example takes an optional directory and writes the PDFs it produces
into it:

```bash
dart run example/dpdf_example.dart build/examples
```

## The most common case

```dart
import 'package:dpdf/dpdf.dart';

final pdf = await HtmlConverter.convertToBytes('<h1>Hello</h1>');

final integrity = await PdfIntegrityChecker.inspect(pdf);
print(integrity.isDamaged);          // false

final conformance = await PdfAVerifier.verify(
  pdf,
  level: PdfAConformanceLevel.a2b,
);
print(conformance.violations);       // what is missing for PDF/A-2b
```

## Laying out a document

`Document.add` is synchronous: it queues the element, and `close` does the
layout.

```dart
final output = BytesBuilder(copy: false);
final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
final document = Document(pdf);

document.add(Paragraph('First page.'));
document.add(AreaBreak(AreaBreakType.NEXT_PAGE));
document.add(Paragraph('Second page.'));

await document.close();
await pdf.close();
```
