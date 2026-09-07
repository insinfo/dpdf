import 'dart:math' as math;
import 'dart:typed_data';

import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../render/content_parser.dart';

/// Maior tamanho físico em que uma imagem é pintada no documento.
typedef PdfImageUsage = ({double widthPoints, double heightPoints});

/// Interpreta somente o subconjunto gráfico necessário para medir `Do`.
abstract final class PdfImageUsageAnalyzer {
  static Future<Map<PdfStream, PdfImageUsage>> analyze(
      PdfDocument document) async {
    final usages = <PdfStream, PdfImageUsage>{};
    for (var number = 1; number <= document.pageTotal(); number++) {
      final page = await document.pageAt(number);
      if (page == null) continue;
      final dictionary = page.pdfRepresentation();
      final resources = await _inheritedResources(dictionary);
      final userUnit =
          (await dictionary.numberEntry(PdfName('UserUnit')))?.doubleValue() ??
              1;
      final complete = await _scan(await page.contentPayload(), resources,
          _Matrix(userUnit, 0, 0, userUnit, 0, 0), usages, <PdfStream>{}, 0);
      if (!complete) return const {};
    }
    return usages;
  }

  static Future<bool> _scan(
    Uint8List bytes,
    PdfDictionary? resources,
    _Matrix initial,
    Map<PdfStream, PdfImageUsage> usages,
    Set<PdfStream> activeForms,
    int depth,
  ) async {
    if (resources == null) return true;
    if (depth > 32) return false;
    var matrix = initial;
    final stack = <_Matrix>[];
    try {
      for (final operation in PdfContentParser.parse(bytes)) {
        switch (operation.operator) {
          case 'q':
            stack.add(matrix);
          case 'Q':
            if (stack.isNotEmpty) matrix = stack.removeLast();
          case 'cm':
            final values = operation.numbers(6);
            if (values != null) matrix = _Matrix.from(values).multiply(matrix);
          case 'Do':
            final name = operation.name(0);
            if (name == null) continue;
            final xobjects = await resources.dictionaryEntry(PdfName.xObject);
            final object = await xobjects?.streamEntry(PdfName(name));
            if (object == null) continue;
            final subtype =
                (await object.nameEntry(PdfName.subtype))?.getValue();
            if (subtype == 'Image') {
              final usage = (
                widthPoints:
                    math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b),
                heightPoints:
                    math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d),
              );
              final previous = usages[object];
              usages[object] = previous == null
                  ? usage
                  : (
                      widthPoints:
                          math.max(previous.widthPoints, usage.widthPoints),
                      heightPoints:
                          math.max(previous.heightPoints, usage.heightPoints),
                    );
            } else if (subtype == 'Form' && activeForms.add(object)) {
              try {
                var formMatrix = matrix;
                final array = await object.arrayEntry(PdfName('Matrix'));
                if (array != null && array.size() == 6) {
                  final values = <double>[];
                  for (var i = 0; i < 6; i++) {
                    final value = await array.get(i);
                    values.add(value is PdfNumber
                        ? value.doubleValue()
                        : (i == 0 || i == 3 ? 1 : 0));
                  }
                  formMatrix = _Matrix.from(values).multiply(matrix);
                }
                final formResources =
                    await object.dictionaryEntry(PdfName.resources) ??
                        resources;
                final content = await object.getBytes();
                if (content != null) {
                  if (!await _scan(content, formResources, formMatrix, usages,
                      activeForms, depth + 1)) {
                    return false;
                  }
                }
              } finally {
                activeForms.remove(object);
              }
            }
        }
      }
      return true;
    } on PdfContentException {
      // Não use medições parciais: uma ocorrência maior pode estar justamente
      // depois do trecho ilegível. O chamador desativa targetDpi no documento.
      return false;
    }
  }

  static Future<PdfDictionary?> _inheritedResources(
      PdfDictionary dictionary) async {
    PdfDictionary? current = dictionary;
    final visited = <PdfDictionary>{};
    while (current != null && visited.add(current)) {
      final resources = await current.dictionaryEntry(PdfName.resources);
      if (resources != null) return resources;
      current = await current.dictionaryEntry(PdfName('Parent'));
    }
    return null;
  }
}

class _Matrix {
  final double a, b, c, d, e, f;
  const _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);
  factory _Matrix.from(List<double> v) =>
      _Matrix(v[0], v[1], v[2], v[3], v[4], v[5]);

  _Matrix multiply(_Matrix other) => _Matrix(
        a * other.a + b * other.c,
        a * other.b + b * other.d,
        c * other.a + d * other.c,
        c * other.b + d * other.d,
        e * other.a + f * other.c + other.e,
        e * other.b + f * other.d + other.f,
      );
}
