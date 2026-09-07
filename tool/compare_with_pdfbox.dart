// Renderiza com o dpdf os PDFs que o PDFBox construiu e comparou-os com a
// rasterização do próprio PDFBox.
//
// Os PDFs não foram produzidos por esta biblioteca e a referência não foi
// desenhada por ela: são duas implementações independentes olhando para os
// mesmos bytes. Serve para verificar `/JBIG2Decode` e `/JPXDecode` de ponta a
// ponta, do filtro até o pixel.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';

Future<void> main(List<String> args) async {
  final root = args.isEmpty ? r'D:\pdf_fixtures' : args[0];
  final pdfDir = Directory('$root/pdf');
  final referenceDir = Directory('$root/out/java_png');

  final pdfs = pdfDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var good = 0;
  var bad = 0;

  for (final pdf in pdfs) {
    final name = pdf.uri.pathSegments.last;
    final base = name.substring(0, name.length - 4);
    final reference = File('${referenceDir.path}/$base.png');

    PdfRenderedPage rendered;
    try {
      final document = await CraftPdfDocument.open(
          CraftPdfReader.fromBytes(pdf.readAsBytesSync()));
      try {
        rendered = await PdfPageRenderer.render((await document.pageAt(1))!,
            options: const PdfRenderOptions(dpi: 72));
      } finally {
        await document.close();
      }
    } catch (e) {
      print('DPDF-FALHOU  ${base.padRight(26)} ${e.runtimeType}: $e');
      bad++;
      continue;
    }

    if (!reference.existsSync()) {
      print('SEM-REF      ${base.padRight(26)} '
          'dpdf produziu ${rendered.width}x${rendered.height}');
      continue;
    }

    final expected = _readPng(reference.readAsBytesSync());
    if (expected == null) {
      print('PNG-ILEGIVEL ${base.padRight(26)}');
      bad++;
      continue;
    }

    if (expected.width != rendered.width ||
        expected.height != rendered.height) {
      print('DIMENSAO     ${base.padRight(26)} '
          'dpdf ${rendered.width}x${rendered.height} vs '
          'pdfbox ${expected.width}x${expected.height}');
      bad++;
      continue;
    }

    final stats = _compare(rendered, expected);
    final ok = stats.psnr >= 30 && stats.differingFraction < 0.02;
    print('${ok ? 'OK          ' : 'DIVERGE     '} ${base.padRight(26)} '
        'psnr ${stats.psnr.isInfinite ? "exato" : "${stats.psnr.toStringAsFixed(1)} dB"}, '
        '${(stats.differingFraction * 100).toStringAsFixed(3)}% diferentes, '
        'máx delta ${stats.maxDelta}');
    if (ok) {
      good++;
    } else {
      bad++;
    }
    if (rendered.report.glyphsSkipped > 0 ||
        rendered.report.imagesSkipped > 0 ||
        rendered.report.unsupportedOperators.isNotEmpty) {
      print('             relatório: ${rendered.report}');
    }
  }

  print('');
  print('=' * 72);
  print('concordam com o PDFBox : $good');
  print('divergem ou falham     : $bad');
  if (bad > 0) exitCode = 1;
}

class _Stats {
  final double psnr;
  final double differingFraction;
  final int maxDelta;
  const _Stats(this.psnr, this.differingFraction, this.maxDelta);
}

_Stats _compare(PdfRenderedPage page, _Png reference) {
  var squared = 0.0;
  var differing = 0;
  var maxDelta = 0;
  final total = page.width * page.height;

  for (var i = 0; i < total; i++) {
    final mine = page.pixels[i];
    final theirs = reference.argb[i];
    for (var shift = 0; shift <= 16; shift += 8) {
      final a = (mine >> shift) & 0xFF;
      final b = (theirs >> shift) & 0xFF;
      final delta = (a - b).abs();
      squared += delta * delta;
      if (delta > maxDelta) maxDelta = delta;
    }
    // Um pixel conta como diferente se qualquer canal saiu do arredondamento.
    if (((mine ^ theirs) & 0x00FFFFFF) != 0) {
      final dr = (((mine >> 16) & 0xFF) - ((theirs >> 16) & 0xFF)).abs();
      final dg = (((mine >> 8) & 0xFF) - ((theirs >> 8) & 0xFF)).abs();
      final db = ((mine & 0xFF) - (theirs & 0xFF)).abs();
      if (dr > 2 || dg > 2 || db > 2) differing++;
    }
  }

  final mse = squared / (total * 3);
  final psnr =
      mse == 0 ? double.infinity : 10 * math.log(255 * 255 / mse) / math.ln10;
  return _Stats(psnr, differing / total, maxDelta);
}

class _Png {
  final int width;
  final int height;
  final Uint32List argb;
  const _Png(this.width, this.height, this.argb);
}

/// Lê um PNG de 8 bits sem entrelaçamento — o que o ImageIO grava.
_Png? _readPng(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }

  var offset = 8;
  int width = 0, height = 0, depth = 0, colourType = 0, interlace = 0;
  final idat = BytesBuilder(copy: false);

  while (offset + 8 <= bytes.length) {
    final length = _u32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final data = bytes.sublist(offset + 8, offset + 8 + length);
    offset += 12 + length;

    if (type == 'IHDR') {
      width = _u32(data, 0);
      height = _u32(data, 4);
      depth = data[8];
      colourType = data[9];
      interlace = data[12];
    } else if (type == 'IDAT') {
      idat.add(data);
    } else if (type == 'IEND') {
      break;
    }
  }

  if (depth != 8 || interlace != 0) return null;
  final channels = switch (colourType) {
    0 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => 0,
  };
  if (channels == 0) return null;

  final raw = Uint8List.fromList(zlib.decode(idat.takeBytes()));
  final stride = width * channels;
  final out = Uint32List(width * height);
  final previous = Uint8List(stride);
  final current = Uint8List(stride);

  var source = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[source++];
    current.setRange(0, stride, raw, source);
    source += stride;
    _unfilter(filter, current, previous, channels);

    for (var x = 0; x < width; x++) {
      final base = x * channels;
      final int r, g, b, a;
      switch (colourType) {
        case 0:
          r = g = b = current[base];
          a = 255;
        case 4:
          r = g = b = current[base];
          a = current[base + 1];
        case 2:
          r = current[base];
          g = current[base + 1];
          b = current[base + 2];
          a = 255;
        default:
          r = current[base];
          g = current[base + 1];
          b = current[base + 2];
          a = current[base + 3];
      }
      out[y * width + x] = (a << 24) | (r << 16) | (g << 8) | b;
    }
    previous.setRange(0, stride, current);
  }
  return _Png(width, height, out);
}

void _unfilter(int filter, Uint8List line, Uint8List previous, int bpp) {
  switch (filter) {
    case 0:
      return;
    case 1:
      for (var i = bpp; i < line.length; i++) {
        line[i] = (line[i] + line[i - bpp]) & 0xFF;
      }
    case 2:
      for (var i = 0; i < line.length; i++) {
        line[i] = (line[i] + previous[i]) & 0xFF;
      }
    case 3:
      for (var i = 0; i < line.length; i++) {
        final left = i >= bpp ? line[i - bpp] : 0;
        line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF;
      }
    case 4:
      for (var i = 0; i < line.length; i++) {
        final a = i >= bpp ? line[i - bpp] : 0;
        final b = previous[i];
        final c = i >= bpp ? previous[i - bpp] : 0;
        final p = a + b - c;
        final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
        final predictor = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
        line[i] = (line[i] + predictor) & 0xFF;
      }
    default:
      throw FormatException('filtro PNG desconhecido: $filter');
  }
}

int _u32(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
