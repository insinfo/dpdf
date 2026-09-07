import 'package:dpdf/src/svg/utils/svg_coordinate_utils.dart';
import 'package:dpdf/src/svg/utils/svg_text_util.dart';
import 'package:test/test.dart';

void main() {
  test('object box accepts numbers, units and padded percentages', () {
    for (final pair
        in {' 25% ': .25, '-.5': -.5, '2px': 2.0, '3rem': 3.0}.entries) {
      expect(
          CraftSvgCoordinateUtils.getCoordinateForObjectBoundingBox(
              pair.key, 9),
          pair.value);
    }
    expect(
        CraftSvgCoordinateUtils.getCoordinateForObjectBoundingBox('bad', 9), 9);
  });
  test('horizontal trimming preserves newline and nonbreaking space', () {
    expect(CraftSvgTextUtil.trimLeadingWhitespace(' \t\n x'), '\n x');
    expect(CraftSvgTextUtil.trimTrailingWhitespace('x\r \t'), 'x\r');
    expect(CraftSvgTextUtil.trimLeadingWhitespace('\u00a0x'), '\u00a0x');
    expect(CraftSvgTextUtil.trimTrailingWhitespace(null), '');
  });
}
