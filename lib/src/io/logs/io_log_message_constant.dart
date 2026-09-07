/// Diagnostic templates for DPDF. Public identifiers and format slots are stable.
class CraftIoLogMessageConstant {
  CraftIoLogMessageConstant._();

  static const String actionWasSetToLinkAnnotationWithDestination =
      'Setting this link action removes the destination already assigned to the annotation.';

  static const String alreadyFlushedIndirectObjectMadeFree =
      'The indirect reference was not released because its object has already been written.';

  static const String attemptProcessNan =
      'A PDF numeric value was NaN; writing zero in its place.';

  static const String attemptToGeneratePdfPagesTreeWithoutAnyPages =
      'The page tree is empty; inserting a page before writing it.';

  static const String canvasAlreadyFullElementWillBeSkipped =
      'No canvas space remains; skipping this element.';

  static const String clipElement =
      'Configured height constraints cut off part of the element content.';

  static const String colorNotParsed =
      'Color value "{0}" is invalid; using black.';

  static const String couldNotFindGlyphWithCode =
      'The font has no glyph for code {0}.';

  static const String directonlyObjectCannotBeIndirect =
      'An object restricted to direct storage cannot receive an indirect reference.';

  static const String documentIdsAreCorrupted =
      'One or both document identifiers, original and modified, are malformed.';

  static const String exceptionWhileCreatingDefaultFont =
      'Default font creation failed for Helvetica with WinAnsi encoding.';

  static const String failedToDetermineCidFontSubtype =
      'Unrecognized CIDFont subtype; expected CIDFontType0 or CIDFontType2.';

  static const String failedToParseEncodingStream =
      'The font encoding stream could not be interpreted.';

  static const String fontDictionaryWithNoFontDescriptor =
      'The font dictionary is missing its required /FontDescriptor.';

  static const String fontDictionaryWithNoWidths =
      'The font dictionary is missing its required /Widths array.';

  static const String fontSubsetIssue =
      'Creating the font subset failed; embedding the complete font instead.';

  static const String imageHasAmbiguousScale =
      'Choose automatic image scaling or an explicit scale; both were requested.';

  static const String imageHasJbig2DecodeFilter =
      'JBIG2Decode requires an image XObject; inline image storage was replaced.';

  static const String imageHasJpxDecodeFilter =
      'JPXDecode requires an image XObject; inline image storage was replaced.';

  static const String imageHasMask =
      'An image with a mask cannot use inline storage.';

  static const String imageSizeCannotBeMore4kb =
      'The inline image exceeds 4 KB; storing it as an image XObject.';

  static const String invalidIndirectReference =
      'Malformed object reference: {0} {1} R.';

  static const String lastRowIsNotComplete =
      'The final table row has unfilled cells; bottom-border collapsing may produce unexpected results.';

  static const String nameAlreadyExistsInTheNameTree =
      'Replacing the existing name-tree value for "{0}".';

  static const String occupiedAreaHasNotBeenInitialized =
      'Layout has no initialized occupied area: {0}.';

  static const String pdfReaderClosingFailed =
      'An error prevented the PDF reader from closing.';

  static const String pdfWriterClosingFailed =
      'An error prevented the PDF writer from closing.';

  static const String startMarkerMissingInPfbFile =
      'The PFB data has no required opening marker.';

  static const String tagStructureInitFailed =
      'Ignoring the tag tree because initialization failed; its structure may be damaged.';

  static const String type3FontCannotBeAdded =
      'FontSet does not accept Type 3 fonts; supply a custom FontProvider to handle them.';

  static const String unknownCmap =
      'No recognized mapping exists for CMap {0}.';

  static const String unknownColorFormatMustBeRgbOrRrggbb =
      'Hexadecimal colors require three rgb digits or six rrggbb digits.';

  static const String unknownErrorWhileProcessingCmap =
      'CMap processing stopped with an unidentified error.';

  static const String xrefErrorWhileReadingTableWillBeRebuilt =
      'Cross-reference parsing failed; reconstructing the xref table from document objects.';

  static const String xrefErrorWhileReadingTableWillBeRebuiltWithCause =
      'Reconstructing the xref table after a read failure: {0}.';
}
