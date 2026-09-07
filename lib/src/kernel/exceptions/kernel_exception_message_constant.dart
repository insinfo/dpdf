/// Diagnostic templates for DPDF. Public identifiers and format slots are stable.
class CraftKernelExceptionMessageConstant {
  CraftKernelExceptionMessageConstant._();

  static const String alreadyClosed = 'The resource has already been closed.';

  static const String argShouldNotBeNull =
      'Argument {0} requires a non-null value.';

  static const String cannotConvertPdfArrayToAnArrayOfBooleans =
      'PDF array contents cannot be represented as boolean values.';

  static const String cannotConvertPdfArrayToDoubleArray =
      'PDF array contents cannot be represented as double-precision values.';

  static const String cannotConvertPdfArrayToFloatArray =
      'PDF array contents cannot be represented as floating-point values.';

  static const String cannotConvertPdfArrayToIntArray =
      'PDF array contents cannot be represented as integer values.';

  static const String cannotConvertPdfArrayToLongArray =
      'PDF array contents cannot be represented as long integer values.';

  static const String cannotConvertPdfArrayToRectangle =
      'PDF array contents do not describe a valid rectangle.';

  static const String cannotCloseDocument = 'Closing the PDF document failed.';

  static const String cannotOpenDocument = 'Opening the PDF document failed.';

  static const String cannotCopyFlushedObject =
      'An object already written to the output cannot be copied.';

  static const String cannotCopyObjectContent =
      'Copying the PDF object\'s content failed.';

  static const String cannotFlushObject =
      'Writing the PDF object to the output failed.';

  static const String documentHasNotBeenReadYet =
      'The PDF has not been read; complete PdfDocument initialization before this operation.';

  static const String documentClosedItIsImpossibleToExecuteAction =
      'This operation requires an open document; the document is closed.';

  static const String cannotCreatePdfstreamByInputStreamWithoutPdfDocument =
      'Creating a PDF stream from an input stream requires a PdfDocument.';

  static const String cannotOperateWithFlushedPdfStream =
      'The PDF stream was already written and is no longer available for this operation.';

  static const String cannotSetDataToPdfStreamWhichWasCreatedByInputStream =
      'A PDF stream backed by an input stream cannot accept replacement byte data.';

  static const String cannotGetPdfStreamBytes =
      'The bytes of this PDF stream could not be obtained.';

  static const String cannotReadAStreamInOrderToAppendNewBytes =
      'Appending bytes failed because the existing stream data could not be read.';

  static const String streamShallEndWithEndstream =
      'The PDF stream is missing its required endstream terminator.';

  static const String unableToReadStreamBytes =
      'No stream was supplied from which to read bytes.';

  static const String cannotReadPdfObject =
      'The PDF object could not be parsed from the input.';

  static const String trailerNotFound =
      'The PDF trailer dictionary could not be located.';

  static const String unexpectedEndOfFile =
      'Input ended before the current PDF structure was complete.';

  static const String unexpectedToken =
      'Token {0} is not valid at this position.';

  static const String pdfStartxrefNotFound =
      'The PDF input has no startxref marker.';

  static const String pdfStartxrefIsNotFollowedByANumber =
      'An integer offset is required immediately after startxref.';

  static const String invalidXrefStream =
      'The cross-reference stream has an invalid structure.';

  static const String invalidXrefTable =
      'The cross-reference table has an invalid structure.';

  static const String xrefSubsectionNotFound =
      'The cross-reference subsection header could not be located.';

  static const String numberOfEntriesInThisXrefSubsectionNotFound =
      'The xref subsection header is missing its entry count.';

  static const String objectNumberOfTheFirstObjectInThisXrefSubsectionNotFound =
      'The xref subsection header is missing its first object number.';

  static const String invalidCrossReferenceEntryInThisXrefSubsection =
      'An entry in the cross-reference subsection is malformed.';

  static const String invalidIndirectReference =
      'Malformed object reference: {0} {1} R.';

  static const String invalidOffsetForThisObject =
      'Object {0} has an invalid byte offset.';

  static const String corruptedRootEntryInTrailer =
      'The trailer cannot resolve a valid catalog through /Root; the PDF cannot be opened.';

  static const String thisFilterIsNotSupported =
      'Stream filter {0} has no supported decoder.';

  static const String thisDecodeParameterTypeIsNotSupported =
      'Decode parameter type {0} is not implemented.';

  static const String filterIsNotANameOrArray =
      'The /Filter entry must be a PDF name or an array of names.';

  static const String illegalCharacterInAscii85Decode =
      'ASCII85 input contains a character outside the permitted alphabet.';

  static const String illegalCharacterInAsciiHexDecode =
      'ASCIIHex input contains a non-hexadecimal character.';

  static const String lzwDecoderException = 'LZW stream decompression failed.';

  static const String lzwFlavourNotSupported =
      'The stream uses an unsupported LZW coding variant.';

  static const String pngFilterUnknown =
      'The predictor specifies an unrecognized PNG filter.';

  static const String errorWhileReadingObjectStream =
      'Parsing an object stream failed.';

  static const String unableToReadObjectStream =
      'Object-stream contents could not be loaded.';

  static const String invalidObjectStreamNumber =
      'Object {0} could not be read from object stream {1} at index {2}.';

  static const String pdfObjectStreamReachMaxSize =
      'The object stream cannot accept more objects because it reached its size limit.';

  static const String requestedPageNumberIsOutOfBounds =
      'Page {0} lies outside the document\'s page range.';

  static const String cannotRetrieveMediaBoxAttribute =
      'The page and its ancestors have no /MediaBox; page dimensions cannot be determined.';

  static const String invalidPageStructure =
      'The page tree contains an invalid structure: {0}.';

  static const String invalidPageStructurePagesMustBePdfDictionary =
      'The page-tree /Pages entry must reference a PDF dictionary.';

  static const String badUserPassword =
      'The PDF password is missing or does not unlock the document.';

  static const String noCompatibleEncryptionFound =
      'No supported encryption handler matches this document.';

  static const String unknownEncryptionTypeR =
      'Unsupported encryption revision /R: {0}.';

  static const String unknownEncryptionTypeV =
      'Unsupported encryption algorithm /V: {0}.';

  static const String cfNotFoundEncryption =
      'The encryption dictionary is missing /CF.';

  static const String stdcfNotFoundEncryption =
      'The encryption crypt-filter dictionary is missing /StdCF.';

  static const String defaultCryptFilterNotFoundEncryption =
      'The encryption dictionary is missing /DefaultCryptFilter.';

  static const String standardHandlerBadDictionary =
      'The standard security handler received a malformed encryption dictionary.';

  static const String cannotCreateFontFromNullPdfDictionary =
      'Font creation requires a non-null PDF dictionary.';

  static const String dictionaryDoesNotHaveSupportedFontData =
      'The dictionary contains no font data supported by this implementation.';

  static const String fontEmbeddingIssue =
      'The font could not be embedded in the PDF.';

  static const String missingRequiredFieldInFontDictionary =
      'The font dictionary is missing mandatory entry {0}.';

  static const String colorSpaceNotFound =
      'The requested PDF color space could not be located.';

  static const String colorSpaceIsNotSupported =
      'Color space {0} is not implemented.';

  static const String unexpectedColorSpace =
      'Color space {0} is not valid for this operation.';

  static const String incorrectNumberOfComponents =
      'The component count does not match the required color space.';

  static const String cannotFindImageDataOrEi =
      'Inline image parsing found neither image data nor an EI terminator.';

  static const String endOfContentStreamReachedBeforeEndOfImageData =
      'The content stream ended while inline image data was still being read.';

  static const String operatorEiNotFoundAfterEndOfImageData =
      'Inline image data is not followed by the required EI operator.';

  static const String mustBeATaggedDocument =
      'This operation requires a tagged PDF document.';

  static const String documentDoesNotContainStructTreeRoot =
      'The document catalog has no /StructTreeRoot entry.';

  static const String ioException = 'An input/output operation failed.';

  static const String ioExceptionWhileCreatingFont =
      'Font creation failed during an input/output operation.';

  static const String unknownPdfException =
      'PDF processing failed without a more specific diagnosis.';

  static const String
      duringDecompressionSingleStreamOccupiedMoreMemoryThanAllowed =
      'Decompressing this stream exceeded the memory limit for one stream.';

  static const String
      duringDecompressionMultipleStreamsInSumOccupiedMoreMemoryThanAllowed =
      'Combined decompressed streams exceeded the total memory limit.';

  static const String appendModeRequiresADocumentWithoutErrors =
      'Incremental append requires an error-free source PDF, including errors that could otherwise be recovered.';

  static const String pdfVersionIsNotValid =
      'The supplied PDF version identifier is invalid.';

  static const String illegalLengthValue =
      'The supplied length is outside its valid range.';

  static const String invalidRangeArray =
      'The range array has an invalid structure or bounds.';

  static const String invalidLength =
      'The requested offset plus length exceeds the byte buffer size.';

  static const String toFlushThisWrapperUnderlyingObjectMustBeAddedToDocument =
      'Add the wrapped PDF object to a document before flushing the wrapper.';

  static const String objectMustBeIndirectToWorkWithThisWrapper =
      'This wrapper requires an object with an indirect reference.';
}
