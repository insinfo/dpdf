// Decodifica com `package:j2k` — o codec que o dpdf usa para `/JPXDecode` — os
// arquivos que o jj2000 (Java, implementação de referência do JPEG 2000)
// produziu, e confere contra as imagens originais.
//
// Para os arquivos sem perdas a exigência é igualdade exata: qualquer pixel
// diferente é bug de um dos dois lados. Para os com perda mede-se o PSNR, que
// precisa ficar acima do que a taxa escolhida justifica.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:j2k/j2k.dart' as j2k;

void main(List<String> args) {
  final root = args.isEmpty ? r'D:\pdf_fixtures' : args[0];
  final sources = <String, _Raster>{
    'gray': _readNetpbm(File('$root/src_img/gray.pgm')),
    'colour': _readNetpbm(File('$root/src_img/colour.ppm')),
  };

  final cases = <_Case>[
    _Case('gray_lossless.j2k', 'gray', lossless: true),
    _Case('gray_r1.j2k', 'gray', minPsnr: 30),
    _Case('colour_lossless.j2k', 'colour', lossless: true),
    _Case('colour_r0.5.j2k', 'colour', minPsnr: 24),
    _Case('colour.jp2', 'colour', minPsnr: 24),
  ];

  var failures = 0;
  for (final testCase in cases) {
    final file = File('$root/jpeg2000/${testCase.file}');
    if (!file.existsSync()) {
      print('AUSENTE   ${testCase.file}');
      failures++;
      continue;
    }

    final j2k.Jpeg2000Image decoded;
    try {
      decoded = j2k.decodeJpeg2000(file.readAsBytesSync());
    } catch (e) {
      print('FALHOU    ${testCase.file.padRight(22)} ${e.runtimeType}: $e');
      failures++;
      continue;
    }

    final source = sources[testCase.source]!;
    if (decoded.width != source.width || decoded.height != source.height) {
      print('DIMENSAO  ${testCase.file.padRight(22)} '
          'j2k ${decoded.width}x${decoded.height} vs '
          'origem ${source.width}x${source.height}');
      failures++;
      continue;
    }
    if (decoded.components != source.components) {
      print('CANAIS    ${testCase.file.padRight(22)} '
          'j2k ${decoded.components} vs origem ${source.components}');
      failures++;
      continue;
    }

    final stats = _difference(decoded, source);
    if (testCase.lossless) {
      if (stats.differing == 0) {
        print('EXATO     ${testCase.file.padRight(22)} '
            '${decoded.width}x${decoded.height}x${decoded.components}');
      } else {
        print('DIFERE    ${testCase.file.padRight(22)} '
            '${stats.differing} amostras, máx ${stats.maxDelta} '
            '(sem perdas tem de ser exato)');
        failures++;
      }
    } else {
      final ok = stats.psnr >= testCase.minPsnr!;
      print('${ok ? 'PSNR OK  ' : 'PSNR BAIXO'} '
          '${testCase.file.padRight(22)} '
          '${stats.psnr.toStringAsFixed(2)} dB '
          '(mínimo ${testCase.minPsnr})');
      if (!ok) failures++;
    }
  }

  print('');
  print(failures == 0
      ? 'todos os fixtures do jj2000 foram lidos corretamente'
      : '$failures caso(s) com problema');
  if (failures > 0) exitCode = 1;
}

class _Case {
  final String file;
  final String source;
  final bool lossless;
  final double? minPsnr;
  const _Case(this.file, this.source, {this.lossless = false, this.minPsnr});
}

class _Raster {
  final int width;
  final int height;
  final int components;
  final Uint8List samples;
  const _Raster(this.width, this.height, this.components, this.samples);
}

_Raster _readNetpbm(File file) {
  final bytes = file.readAsBytesSync();
  var offset = 0;
  String token() {
    while (offset < bytes.length && _isSpace(bytes[offset])) {
      offset++;
    }
    final start = offset;
    while (offset < bytes.length && !_isSpace(bytes[offset])) {
      offset++;
    }
    return String.fromCharCodes(bytes.sublist(start, offset));
  }

  final magic = token();
  final components = magic == 'P5' ? 1 : 3;
  final width = int.parse(token());
  final height = int.parse(token());
  token(); // maxval
  offset++; // o byte de espaço único depois dele
  return _Raster(width, height, components, bytes.sublist(offset));
}

bool _isSpace(int b) => b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09;

class _Stats {
  final int differing;
  final int maxDelta;
  final double psnr;
  const _Stats(this.differing, this.maxDelta, this.psnr);
}

_Stats _difference(j2k.Jpeg2000Image decoded, _Raster source) {
  var differing = 0;
  var maxDelta = 0;
  var squared = 0.0;
  var count = 0;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      for (var c = 0; c < source.components; c++) {
        final expected =
            source.samples[(y * source.width + x) * source.components + c];
        final actual =
            decoded.pixels[(y * decoded.width + x) * decoded.components + c];
        final delta = (expected - actual).abs();
        if (delta != 0) {
          differing++;
          if (delta > maxDelta) maxDelta = delta;
        }
        squared += delta * delta;
        count++;
      }
    }
  }

  final mse = squared / count;
  final psnr =
      mse == 0 ? double.infinity : 10 * math.log(255 * 255 / mse) / math.ln10;
  return _Stats(differing, maxDelta, psnr);
}
