import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';

const _googleFont =
    'https://raw.githubusercontent.com/google/fonts/main/ofl/lato/Lato-Regular.ttf';

Future<void> main(List<String> arguments) async {
  final output =
      File(arguments.isEmpty ? 'html_showcase.pdf' : arguments.first);
  final jpeg = _sampleJpeg();
  var remoteFontLoaded = false;
  final html = '''
<!doctype html>
<html lang="en">
<head>
  <style>
    @font-face {
      font-family: "Lato Showcase";
      src: url("$_googleFont") format("truetype");
    }
    body { font-family: "Lato Showcase", sans-serif; color: #172033; }
    h1 { color: #123a70; margin-bottom: 4px; }
    .lead { color: #526078; margin-top: 0; }
    .hero { display: flex; gap: 18px; padding: 14px; background-color: #eef5ff;
            border: 1px solid #b7cff4; margin-bottom: 14px; }
    .card { padding: 10px; border: 1px solid #d8deea; background-color: #ffffff; }
    table { width: 100%; margin-top: 12px; border: 1px solid #bcc7d8; }
    th { color: #ffffff; background-color: #245ea8; padding: 7px; }
    td { padding: 7px; border: 1px solid #d8deea; }
    .total { font-weight: bold; color: #0a6b42; }
    footer { margin-top: 18px; color: #526078; text-align: center; }
  </style>
</head>
<body>
  <h1>Visual operations report</h1>
  <p class="lead">HTML, CSS, vector SVG, a JPEG photograph and the Lato face
     from the Google Fonts project, all in one document.</p>

  <section class="hero">
    <div class="card">
      <h2>SVG gauge</h2>
      <svg width="240" height="100" viewBox="0 0 240 100">
        <defs>
          <linearGradient id="meter" x1="0" x2="1">
            <stop offset="0" stop-color="#16a085"/>
            <stop offset="1" stop-color="#245ea8"/>
          </linearGradient>
        </defs>
        <rect x="2" y="2" width="236" height="96" rx="12"
              fill="#ffffff" stroke="#b7cff4" stroke-width="2"/>
        <rect x="18" y="47" width="190" height="20" rx="10"
              fill="url(#meter)"/>
        <circle cx="198" cy="57" r="15" fill="#ffffff"
                stroke="#245ea8" stroke-width="3"/>
        <text x="18" y="31" font-size="18" fill="#172033">Target: 92%</text>
      </svg>
    </div>
    <div class="card">
      <h2>JPEG image</h2>
      <img src="data:image/jpeg;base64,${base64Encode(jpeg)}"
           width="180" height="108" alt="Gradient sample"/>
    </div>
  </section>

  <h2>Financial summary</h2>
  <table>
    <thead><tr><th>Product</th><th>Quantity</th><th>Revenue</th></tr></thead>
    <tbody>
      <tr><td>Professional licenses</td><td>128</td><td>38,400.00</td></tr>
      <tr><td>Premium support</td><td>46</td><td>13,800.00</td></tr>
      <tr><td>Training</td><td>12</td><td>9,600.00</td></tr>
      <tr class="total"><td>Total</td><td>186</td><td>61,800.00</td></tr>
    </tbody>
  </table>
  <footer>Generated with dpdf: searchable text and vector SVG.</footer>
</body>
</html>
''';

  final pdf = await HtmlConverter.convertToBytes(
    html,
    properties: HtmlConverterProperties(
      baseUri: Uri.parse(_googleFont),
      fontResourceLoader: (uri) async {
        try {
          final bytes = await _download(uri);
          remoteFontLoaded = bytes != null;
          return bytes;
        } on Object catch (error) {
          stderr.writeln('Remote font unavailable; falling back: $error');
          return null;
        }
      },
    ),
  );
  await output.parent.create(recursive: true);
  await output.writeAsBytes(pdf);

  final document = await PdfDocument.open(PdfReader.fromBytes(pdf));
  try {
    final text = await PdfTextExtraction.fromPage((await document.pageAt(1))!);
    final images = await PdfImageInventory.inspect(document);
    print('written .............: ${output.path}');
    print('PDF bytes ...........: ${pdf.length}');
    print(
        'Google font .........: ${remoteFontLoaded ? 'embedded' : 'fallback'}');
    print('searchable text .....: ${text.contains('Visual operations')}');
    print('raster images .......: ${images.images.length}');
    print('inline SVG ..........: vector');
  } finally {
    await document.close();
  }
}

Uint8List _sampleJpeg() {
  const width = 180;
  const height = 108;
  final pixels = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final at = (y * width + x) * 3;
      pixels[at] = 25 + x * 180 ~/ width;
      pixels[at + 1] = 70 + y * 150 ~/ height;
      pixels[at + 2] = 180 + (x + y) % 70;
    }
  }
  return JpegEncoder.encode(pixels, width: width, height: height, quality: 86);
}

Future<Uint8List?> _download(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'dpdf-html-showcase/1.0');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    const limit = 12 * 1024 * 1024;
    final output = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (output.length + chunk.length > limit) {
        throw StateError('The remote font exceeds $limit bytes.');
      }
      output.add(chunk);
    }
    return output.takeBytes();
  } finally {
    client.close(force: true);
  }
}
