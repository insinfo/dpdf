/// Class that bundles all kernel exception message templates as constants.
class KernelExceptionMessageConstant {
  KernelExceptionMessageConstant._();

  // Basic errors
  static const String alreadyClosed = 'Already closed';
  static const String argShouldNotBeNull = '{0} should not be null.';

  // PDF Array conversions
  static const String cannotConvertPdfArrayToAnArrayOfBooleans =
      'Cannot convert PdfArray to an array of booleans';
  static const String cannotConvertPdfArrayToDoubleArray =
      'Cannot convert PdfArray to an array of doubles.';
  static const String cannotConvertPdfArrayToFloatArray =
      'Cannot convert PdfArray to an array of floats.';
  static const String cannotConvertPdfArrayToIntArray =
      'Cannot convert PdfArray to an array of integers.';
  static const String cannotConvertPdfArrayToLongArray =
      'Cannot convert PdfArray to an array of longs.';
  static const String cannotConvertPdfArrayToRectangle =
      'Cannot convert PdfArray to Rectangle.';

  // Document operations
  static const String cannotCloseDocument = 'Cannot close document.';
  static const String cannotOpenDocument = 'Cannot open document.';
  static const String cannotCopyFlushedObject = 'Cannot copy flushed object.';
  static const String cannotCopyObjectContent = 'Cannot copy object content.';
  static const String cannotFlushObject = 'Cannot flush object.';
  static const String documentHasNotBeenReadYet =
      'The PDF document has not been read yet. Document reading occurs in PdfDocument class constructor';
  static const String documentClosedItIsImpossibleToExecuteAction =
      'Document was closed. It is impossible to execute action.';

  // Stream operations
  static const String cannotCreatePdfstreamByInputStreamWithoutPdfDocument =
      'Cannot create pdfstream by InputStream without PdfDocument.';
  static const String cannotOperateWithFlushedPdfStream =
      'Cannot operate with the flushed PdfStream.';
  static const String cannotSetDataToPdfStreamWhichWasCreatedByInputStream =
      'Cannot set data to PdfStream which was created by InputStream.';
  static const String cannotGetPdfStreamBytes = 'Cannot get PdfStream bytes.';
  static const String cannotReadAStreamInOrderToAppendNewBytes =
      'Cannot read a stream in order to append new bytes.';
  static const String streamShallEndWithEndstream =
      'Stream shall end with endstream keyword.';
  static const String unableToReadStreamBytes =
      'Unable to read stream bytes because stream is null.';

  // PDF reading errors
  static const String cannotReadPdfObject = 'Cannot read PdfObject.';
  static const String trailerNotFound = 'Trailer not found.';
  static const String unexpectedEndOfFile = 'Unexpected end of file.';
  static const String unexpectedToken = 'unexpected {0} was encountered.';
  static const String pdfStartxrefNotFound = 'PDF startxref not found.';
  static const String pdfStartxrefIsNotFollowedByANumber =
      'PDF startxref is not followed by a number.';
  static const String invalidXrefStream = 'Invalid xref stream.';
  static const String invalidXrefTable = 'Invalid xref table.';
  static const String xrefSubsectionNotFound = 'xref subsection not found.';
  static const String numberOfEntriesInThisXrefSubsectionNotFound =
      'Number of entries in this xref subsection not found.';
  static const String objectNumberOfTheFirstObjectInThisXrefSubsectionNotFound =
      'Object number of the first object in this xref subsection not found.';
  static const String invalidCrossReferenceEntryInThisXrefSubsection =
      'Invalid cross reference entry in this xref subsection.';
  static const String invalidIndirectReference =
      'Invalid indirect reference {0} {1} R.';
  static const String invalidOffsetForThisObject =
      'Invalid offset for object {0}.';
  static const String corruptedRootEntryInTrailer =
      'The trailer is corrupted: the catalog is corrupted or cannot be referenced from the file\'s trailer. The PDF cannot be opened.';

  // Filter errors
  static const String thisFilterIsNotSupported = 'Filter {0} is not supported.';
  static const String thisDecodeParameterTypeIsNotSupported =
      'Decode parameter type {0} is not supported.';
  static const String filterIsNotANameOrArray =
      'filter is not a name or array.';
  static const String illegalCharacterInAscii85Decode =
      'Illegal character in ASCII85Decode.';
  static const String illegalCharacterInAsciiHexDecode =
      'illegal character in ASCIIHexDecode.';
  static const String lzwDecoderException = 'LZW decoder exception.';
  static const String lzwFlavourNotSupported = 'LZW flavour not supported.';
  static const String pngFilterUnknown = 'PNG filter unknown.';

  // Object stream errors
  static const String errorWhileReadingObjectStream =
      'Error while reading Object Stream.';
  static const String unableToReadObjectStream =
      'Unable to read object stream.';
  static const String invalidObjectStreamNumber =
      'Unable to read object {0} with object stream number {1} and index {2} from object stream.';
  static const String pdfObjectStreamReachMaxSize =
      'PdfObjectStream reached max size.';

  // Page errors
  static const String requestedPageNumberIsOutOfBounds =
      'Requested page number {0} is out of bounds.';
  static const String cannotRetrieveMediaBoxAttribute =
      'Invalid PDF. There is no media box attribute for page or its parents.';
  static const String invalidPageStructure = 'Invalid page structure {0}.';
  static const String invalidPageStructurePagesMustBePdfDictionary =
      'Invalid page structure. /Pages must be PdfDictionary.';

  // Encryption errors
  static const String badUserPassword =
      'Bad user password. Password is not provided or wrong password provided.';
  static const String noCompatibleEncryptionFound =
      'No compatible encryption found.';
  static const String unknownEncryptionTypeR =
      'Unknown encryption type R == {0}.';
  static const String unknownEncryptionTypeV =
      'Unknown encryption type V == {0}.';
  static const String cfNotFoundEncryption = '/CF not found (encryption)';
  static const String stdcfNotFoundEncryption = '/StdCF not found (encryption)';
  static const String defaultCryptFilterNotFoundEncryption =
      '/DefaultCryptFilter not found (encryption).';

  // Font errors
  static const String cannotCreateFontFromNullPdfDictionary =
      'Cannot create font from null pdf dictionary.';
  static const String dictionaryDoesNotHaveSupportedFontData =
      'Dictionary doesn\'t have supported font data.';
  static const String fontEmbeddingIssue = 'Font embedding issue.';
  static const String missingRequiredFieldInFontDictionary =
      'Missing required field {0} in font dictionary.';

  // Color space errors
  static const String colorSpaceNotFound = 'ColorSpace not found.';
  static const String colorSpaceIsNotSupported =
      'The color space {0} is not supported.';
  static const String unexpectedColorSpace = 'Unexpected ColorSpace: {0}.';
  static const String incorrectNumberOfComponents =
      'Incorrect number of components.';

  // Image errors
  static const String cannotFindImageDataOrEi = 'Cannot find image data or EI.';
  static const String endOfContentStreamReachedBeforeEndOfImageData =
      'End of content stream reached before end of image data.';
  static const String operatorEiNotFoundAfterEndOfImageData =
      'Operator EI not found after the end of image data.';

  // Tagged PDF errors
  static const String mustBeATaggedDocument = 'Must be a tagged document.';
  static const String documentDoesNotContainStructTreeRoot =
      'Document doesn\'t contain StructTreeRoot.';

  // I/O errors
  static const String ioException = 'I/O exception.';
  static const String ioExceptionWhileCreatingFont =
      'I/O exception while creating Font';
  static const String unknownPdfException = 'Unknown PdfException.';

  // Memory errors
  static const String
      duringDecompressionSingleStreamOccupiedMoreMemoryThanAllowed =
      'During decompression a single stream occupied more memory than allowed.';
  static const String
      duringDecompressionMultipleStreamsInSumOccupiedMoreMemoryThanAllowed =
      'During decompression multiple streams in sum occupied more memory than allowed.';

  // Misc errors
  static const String appendModeRequiresADocumentWithoutErrors =
      'Append mode requires a document without errors, even if recovery is possible.';
  static const String pdfVersionIsNotValid = 'PDF version is not valid.';
  static const String illegalLengthValue = 'Illegal length value.';
  static const String invalidRangeArray = 'Invalid range array.';
  static const String invalidLength =
      'The offset + length must be lower than or equal to the length of the byte array.';

  // Wrapper errors
  static const String toFlushThisWrapperUnderlyingObjectMustBeAddedToDocument =
      'To flush this wrapper, underlying object must be added to document.';
  static const String objectMustBeIndirectToWorkWithThisWrapper =
      'Object must be indirect to work with this wrapper.';
}
