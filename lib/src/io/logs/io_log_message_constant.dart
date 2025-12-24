/// Log message constants for IO module.
class IoLogMessageConstant {
  IoLogMessageConstant._();

  static const String actionWasSetToLinkAnnotationWithDestination =
      'Action was set for a link annotation containing destination. The old destination will be cleared.';

  static const String alreadyFlushedIndirectObjectMadeFree =
      'An attempt is made to free already flushed indirect object reference. Indirect reference wasn\'t freed.';

  static const String attemptProcessNan =
      'Attempt to process NaN in PdfNumber or when writing to PDF. Zero value will be used as a fallback.';

  static const String attemptToGeneratePdfPagesTreeWithoutAnyPages =
      'Attempt to generate PDF pages tree without any pages, so a new page will be added.';

  static const String canvasAlreadyFullElementWillBeSkipped =
      'Canvas is already full. Element will be skipped.';

  static const String clipElement =
      'Element content was clipped because some height properties are set.';

  static const String colorNotParsed =
      'Color "{0}" was not parsed. It has invalid value. Defaulting to black color.';

  static const String couldNotFindGlyphWithCode =
      'Could not find glyph with the following code: {0}';

  static const String directonlyObjectCannotBeIndirect =
      'DirectOnly object cannot be indirect';

  static const String documentIdsAreCorrupted =
      'The document original and/or modified id is corrupted';

  static const String exceptionWhileCreatingDefaultFont =
      'Exception while creating default font (Helvetica, WinAnsi)';

  static const String failedToDetermineCidFontSubtype =
      'Failed to determine CIDFont subtype. The type of CIDFont shall be CIDFontType0 or CIDFontType2.';

  static const String failedToParseEncodingStream =
      'Failed to parse encoding stream.';

  static const String fontDictionaryWithNoFontDescriptor =
      'Font dictionary does not contain required /FontDescriptor entry.';

  static const String fontDictionaryWithNoWidths =
      'Font dictionary does not contain required /Widths entry.';

  static const String fontSubsetIssue =
      'Font subset issue. Full font will be embedded.';

  static const String imageHasAmbiguousScale =
      'The image cannot be auto scaled and scaled by a certain parameter simultaneously';

  static const String imageHasJbig2DecodeFilter =
      'Image cannot be inline if it has JBIG2Decode filter. It will be added as an ImageXObject';

  static const String imageHasJpxDecodeFilter =
      'Image cannot be inline if it has JPXDecode filter. It will be added as an ImageXObject';

  static const String imageHasMask = 'Image cannot be inline if it has a Mask';

  static const String imageSizeCannotBeMore4kb =
      'Inline image size cannot be more than 4KB. It will be added as an ImageXObject';

  static const String invalidIndirectReference =
      'Invalid indirect reference {0} {1} R';

  static const String lastRowIsNotComplete =
      'Last row is not completed. Table bottom border may collapse as you do not expect it';

  static const String nameAlreadyExistsInTheNameTree =
      'Name "{0}" already exists in the name tree; old value will be replaced by the new one.';

  static const String occupiedAreaHasNotBeenInitialized =
      'Occupied area has not been initialized. {0}';

  static const String pdfReaderClosingFailed =
      'PdfReader closing failed due to the error occurred!';

  static const String pdfWriterClosingFailed =
      'PdfWriter closing failed due to the error occurred!';

  static const String startMarkerMissingInPfbFile =
      'Start marker is missing in the pfb file';

  static const String tagStructureInitFailed =
      'Tag structure initialization failed, tag structure is ignored, it might be corrupted.';

  static const String type3FontCannotBeAdded =
      'Type 3 font cannot be added to FontSet. Custom FontProvider class may be created for this purpose.';

  static const String unknownCmap = 'Unknown CMap {0}';

  static const String unknownColorFormatMustBeRgbOrRrggbb =
      'Unknown color format: must be rgb or rrggbb.';

  static const String unknownErrorWhileProcessingCmap =
      'Unknown error while processing CMap.';

  static const String xrefErrorWhileReadingTableWillBeRebuilt =
      'Error occurred while reading cross reference table. Cross reference table will be rebuilt.';

  static const String xrefErrorWhileReadingTableWillBeRebuiltWithCause =
      'Error occurred while reading cross reference table. Cross reference table will be rebuilt. Reason: {0}';
}
