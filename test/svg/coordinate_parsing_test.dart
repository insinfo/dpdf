import 'package:dpdf/src/svg/utils/svg_coordinate_utils.dart';
import 'package:dpdf/src/svg/utils/svg_text_util.dart';
import 'package:test/test.dart';

void main() {
  test('object box accepts numbers, units and padded percentages', () {
    for (final pair
        in {' 25% ': .25, '-.5': -.5, '2px': 2.0, '3rem': 3.0}.entries) {
      expect(SvgCoordinateUtils.getCoordinateForObjectBoundingBox(pair.key, 9),
          pair.value);
    }
    expect(SvgCoordinateUtils.getCoordinateForObjectBoundingBox('bad', 9), 9);
  });
  test('horizontal trimming preserves newline and nonbreaking space', () {
    expect(SvgTextUtil.trimLeadingWhitespace(' \t\n x'), '\n x');
    expect(SvgTextUtil.trimTrailingWhitespace('x\r \t'), 'x\r');
    expect(SvgTextUtil.trimLeadingWhitespace('\u00a0x'), '\u00a0x');
    expect(SvgTextUtil.trimTrailingWhitespace(null), '');
  });
}
