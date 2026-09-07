import 'package:dpdf/src/layout/layout/min_max_width_layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

class CraftTextLayoutResult extends CraftMinMaxWidthLayoutResult {
  bool wordHasBeenSplit = false;
  bool splitForcedByNewline = false;
  bool containsPossibleBreak = false;
  bool startsWithSplitCharacterWhiteSpace = false;
  bool endsWithSplitCharacter = false;
  double leftMinWidth = 0;
  double rightMinWidth = 0;

  CraftTextLayoutResult(int status, CraftLayoutArea? occupiedArea,
      CraftRenderer? splitRenderer, CraftRenderer? overflowRenderer,
      [CraftRenderer? causeOfNothing])
      : super(status, occupiedArea, splitRenderer, overflowRenderer,
            causeOfNothing);

  bool isWordHasBeenSplit() {
    return wordHasBeenSplit;
  }

  CraftTextLayoutResult setWordHasBeenSplit(bool wordHasBeenSplit) {
    this.wordHasBeenSplit = wordHasBeenSplit;
    return this;
  }

  bool isSplitForcedByNewline() {
    return splitForcedByNewline;
  }

  CraftTextLayoutResult setSplitForcedByNewline(bool splitForcedByNewline) {
    this.splitForcedByNewline = splitForcedByNewline;
    return this;
  }

  bool isContainsPossibleBreak() {
    return containsPossibleBreak;
  }

  CraftTextLayoutResult setContainsPossibleBreak(bool containsPossibleBreak) {
    this.containsPossibleBreak = containsPossibleBreak;
    return this;
  }

  CraftTextLayoutResult setStartsWithSplitCharacterWhiteSpace(
      bool startsWithSplitCharacterWhiteSpace) {
    this.startsWithSplitCharacterWhiteSpace =
        startsWithSplitCharacterWhiteSpace;
    return this;
  }

  bool isStartsWithSplitCharacterWhiteSpace() {
    return startsWithSplitCharacterWhiteSpace;
  }

  CraftTextLayoutResult setEndsWithSplitCharacter(bool endsWithSplitCharacter) {
    this.endsWithSplitCharacter = endsWithSplitCharacter;
    return this;
  }

  bool isEndsWithSplitCharacter() {
    return endsWithSplitCharacter;
  }

  CraftTextLayoutResult setLeftMinWidth(double leftMinWidth) {
    this.leftMinWidth = leftMinWidth;
    return this;
  }

  double getLeftMinWidth() {
    return leftMinWidth;
  }

  CraftTextLayoutResult setRightMinWidth(double rightMinWidth) {
    this.rightMinWidth = rightMinWidth;
    return this;
  }

  double getRightMinWidth() {
    return rightMinWidth;
  }
}
