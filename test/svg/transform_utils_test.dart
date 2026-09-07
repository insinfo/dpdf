import 'package:dpdf/src/svg/exceptions/svg_processing_exception.dart';
import 'package:dpdf/src/svg/utils/transform_utils.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a sequence of valid SVG transform functions', () {
    final transform =
        CraftTransformUtils.parseTransform('translate(10, 20) scale(2)');

    final point = transform.transformPoint(1, 1);
    expect(point[0].isFinite, isTrue);
    expect(point[1].isFinite, isTrue);
  });

  test('rejects whitespace-only and trailing malformed transforms', () {
    expect(() => CraftTransformUtils.parseTransform('  \t '),
        throwsA(isA<CraftSvgProcessingException>()));
    expect(() => CraftTransformUtils.parseTransform('translate(1) garbage'),
        throwsA(isA<CraftSvgProcessingException>()));
    expect(() => CraftTransformUtils.parseTransform('translate(1'),
        throwsA(isA<CraftSvgProcessingException>()));
  });
}
