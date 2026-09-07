import 'package:dpdf/src/layout/layout/min_max_width_layout_result.dart';

class TextLayoutResult extends MinMaxWidthLayoutResult {
  bool wordHasBeenSplit = false;
  bool splitForcedByNewline = false;
  bool containsPossibleBreak = false;
  bool startsWithSplitCharacterWhiteSpace = false;
  bool endsWithSplitCharacter = false;
  double leftMinWidth = 0;
  double rightMinWidth = 0;

  TextLayoutResult(super.status, super.occupiedArea, super.splitRenderer,
      super.overflowRenderer,
      [super.causeOfNothing]);

  bool isWordHasBeenSplit() {
    return wordHasBeenSplit;
  }

  TextLayoutResult setWordHasBeenSplit(bool wordHasBeenSplit) {
    this.wordHasBeenSplit = wordHasBeenSplit;
    return this;
  }

  bool isSplitForcedByNewline() {
    return splitForcedByNewline;
  }

  TextLayoutResult setSplitForcedByNewline(bool splitForcedByNewline) {
    this.splitForcedByNewline = splitForcedByNewline;
    return this;
  }

  bool isContainsPossibleBreak() {
    return containsPossibleBreak;
  }

  TextLayoutResult setContainsPossibleBreak(bool containsPossibleBreak) {
    this.containsPossibleBreak = containsPossibleBreak;
    return this;
  }

  TextLayoutResult setStartsWithSplitCharacterWhiteSpace(
      bool startsWithSplitCharacterWhiteSpace) {
    this.startsWithSplitCharacterWhiteSpace =
        startsWithSplitCharacterWhiteSpace;
    return this;
  }

  bool isStartsWithSplitCharacterWhiteSpace() {
    return startsWithSplitCharacterWhiteSpace;
  }

  TextLayoutResult setEndsWithSplitCharacter(bool endsWithSplitCharacter) {
    this.endsWithSplitCharacter = endsWithSplitCharacter;
    return this;
  }

  bool isEndsWithSplitCharacter() {
    return endsWithSplitCharacter;
  }

  TextLayoutResult setLeftMinWidth(double leftMinWidth) {
    this.leftMinWidth = leftMinWidth;
    return this;
  }

  double getLeftMinWidth() {
    return leftMinWidth;
  }

  TextLayoutResult setRightMinWidth(double rightMinWidth) {
    this.rightMinWidth = rightMinWidth;
    return this;
  }

  double getRightMinWidth() {
    return rightMinWidth;
  }
}
