/// Class containing constants to be used in exceptions in the IO module.
class IoExceptionMessageConstant {
  IoExceptionMessageConstant._();

  static const String allFillBitsPrecedingEolCodeMustBe0 =
      'All fill bits preceding eol code must be 0.';

  static const String alreadyClosed = 'Already closed';

  static const String badEndiannessTag0x4949Or0x4d4d =
      'Bad endianness tag: 0x4949 or 0x4d4d.';

  static const String badMagicNumberShouldBe42 =
      'Bad magic number. Should be 42.';

  static const String bitsPerComponentMustBe1248 =
      'Bits per component must be 1, 2, 4 or 8.';

  static const String bitsPerSampleIsNotSupported =
      'Bits per sample {0} is not supported.';

  static const String
      bitSamplesAreNotSupportedForHorizontalDifferencingPredictor =
      '{0} bit samples are not supported for horizontal differencing predictor.';

  static const String bmpImageException = 'Bmp image exception.';

  static const String brotliDecodingFailed = 'Woff2 brotli decoding exception';

  static const String bufferReadFailed = 'Reading woff2 exception';

  static const String bytesCanBeAssignedToByteArrayOutputStreamOnly =
      'Bytes can be assigned to ByteArrayOutputStream only.';

  static const String bytesCanBeResetInByteArrayOutputStreamOnly =
      'Bytes can be reset in ByteArrayOutputStream only.';

  static const String cannotFindFrame =
      'Cannot find frame number {0} (zero-based)';

  static const String cannotGetTiffImageColor = 'Cannot get TIFF image color.';

  static const String cannotHandleBoxSizesHigherThan2pow32 =
      'Cannot handle box sizes higher than 2^32.';

  static const String cannotInflateTiffImage = 'Cannot inflate TIFF image.';

  static const String cannotOpenOutputDirectory =
      'Cannot open output directory for <filename>';

  static const String cannotReadTiffImage = 'Cannot read TIFF image.';

  static const String cannotWriteByte = 'Cannot write byte.';

  static const String cannotWriteBytes = 'Cannot write bytes.';

  static const String cannotWriteFloatNumber = 'Cannot write float number.';

  static const String cannotWriteIntNumber = 'Cannot write int number.';

  static const String ccittCompressionTypeMustBeCcittg4Ccittg31dOrCcittg32d =
      'CCITT compression type must be CCITTG4, CCITTG3_1D or CCITTG3_2D.';

  static const String characterCodeException = 'Character code exception.';

  static const String cmapTableMergingIsNotSupported =
      "cmap table merging isn't supported.";

  static const String cmapWasNotFound = 'The CMap {0} was not found.';

  static const String compareCommandIsNotSpecified =
      'ImageMagick comparison command is not specified.';

  static const String compareCommandSpecifiedIncorrectly =
      'ImageMagick comparison command specified incorrectly.';

  static const String componentsMustBe134 = 'Components must be 1, 3 or 4.';

  static const String compressionIsNotSupported =
      'Compression {0} is not supported.';

  static const String
      compressionJpegIsOnlySupportedWithASingleStripThisImageHasStrips =
      'Compression jpeg is only supported with a single strip. This image has {0} strips.';

  static const String corruptedJfifMarker = '{0} corrupted jfif marker.';

  static const String directoryNumberIsTooLarge =
      'Directory number is too large.';

  static const String eolCodeWordEncounteredInBlackRun =
      'EOL code word encountered in Black run.';

  static const String eolCodeWordEncounteredInWhiteRun =
      'EOL code word encountered in White run.';

  static const String errorAtFilePointer = 'Error at file pointer {0}.';

  static const String errorReadingString = 'Error reading string.';

  static const String errorWithJpMarker = 'Error with JP marker.';

  static const String expectedFtypMarker = 'Expected FTYP marker.';

  static const String expectedIhdrMarker = 'Expected IHDR marker.';

  static const String expectedJp2hMarker = 'Expected JP2H marker.';

  static const String expectedJpMarker = 'Expected JP marker.';

  static const String expectedTrailingZeroBitsForByteAlignedLines =
      'Expected trailing zero bits for byte-aligned lines';

  static const String extraSamplesAreNotSupported =
      'Extra samples are not supported.';

  static const String fdfStartxrefNotFound = 'FDF startxref not found.';

  static const String firstScanlineMustBe1dEncoded =
      'First scanline must be 1D encoded.';

  static const String fontFileNotFound = 'Font file {0} not found.';

  static const String ghostscriptFailed = 'GhostScript failed for <filename>';

  static const String gifImageException = 'GIF image exception.';

  static const String gifSignatureNotFound = 'GIF signature not found.';

  static const String gsEnvironmentVariableIsNotSpecified =
      'Ghostscript command is not specified or specified incorrectly.';

  static const String gtNotExpected = "\'>\' not expected.";

  static const String
      iccProfileContainsComponentsWhileTheImageDataContainsComponents =
      'ICC profile contains {0} components, while the image data contains {1} components.';

  static const String illegalValueForPredictorInTiffFile =
      'Illegal value for predictor in TIFF file.';

  static const String imageFormatCannotBeRecognized =
      'Image format cannot be recognized.';

  static const String imageIsNotAMaskYouMustCallImageDataMakeMask =
      'Image is not a mask. You must call ImageData#makeMask().';

  static const String imageMagickOutputIsNull =
      'ImageMagick process output is null.';

  static const String imageMagickProcessExecutionFailed =
      'ImageMagick process execution finished with errors: ';

  static const String imageMaskCannotContainAnotherImageMask =
      'Image mask cannot contain another image mask.';

  static const String incompatibleGlyphDataDuringFontMerging =
      'Incompatibility of glyph data/metrics between merged fonts';

  static const String incompletePalette = 'Incomplete palette.';

  static const String incorrectSignature = 'Incorrect woff2 signature';

  static const String invalidBmpFileCompression =
      'Invalid BMP file compression.';

  static const String invalidCodeEncountered = 'Invalid code encountered.';

  static const String
      invalidCodeEncounteredWhileDecoding2dGroup3CompressedData =
      'Invalid code encountered while decoding 2D group 3 compressed data.';

  static const String
      invalidCodeEncounteredWhileDecoding2dGroup4CompressedData =
      'Invalid code encountered while decoding 2D group 4 compressed data.';

  static const String invalidIccProfile = 'Invalid ICC profile.';

  static const String invalidJpeg2000File = 'Invalid JPEG2000 file.';

  static const String invalidMagicValueForBmpFileMustBeBm =
      "Invalid magic value for bmp file. Must be 'BM'";

  static const String invalidTtcFile = '{0} is not a valid TTC file.';

  static const String invalidWoff2FontFile = 'Invalid WOFF2 font file.';

  static const String invalidWoffFile = 'Invalid WOFF font file.';

  static const String ioException = 'I/O exception.';

  static const String isNotAnAfmOrPfmFontFile =
      '{0} is not an afm or pfm font file.';

  static const String isNotAValidJpegFile = '{0} is not a valid jpeg file.';

  static const String jbig2ImageException = 'JBIG2 image exception.';

  static const String jpeg2000ImageException = 'JPEG2000 image exception.';

  static const String jpegImageException = 'JPEG image exception.';

  static const String locaSizeOverflow =
      'woff2 loca table content size overflow exception';

  static const String missingTagsForOjpegCompression =
      'Missing tag(s) for OJPEG compression';

  static const String mustHave8BitsPerComponent =
      '{0} must have 8 bits per component.';

  static const String notAtTrueTypeFile = '{0} is not a true type file';

  static const String notFoundAsFileOrResource =
      '{0} not found as file or resource.';

  static const String paddingOverflow = 'woff2 padding overflow exception';

  static const String pageNumberMustBeGtEq1 = 'Page number must be >= 1.';

  static const String pdfHeaderNotFound = 'PDF header not found.';

  static const String pdfStartxrefNotFound = 'PDF startxref not found.';

  static const String pdfEofNotFound = 'PDF "%%EOF" marker is not found.';

  static const String photometricIsNotSupported =
      'Photometric {0} is not supported.';

  static const String planarImagesAreNotSupported =
      'Planar images are not supported.';

  static const String pngImageException = 'PNG image exception.';

  static const String prematureEofWhileReadingJpeg =
      'Premature EOF while reading JPEG.';

  static const String readBase128Failed =
      'Reading woff2 base 128 number exception';

  static const String readCollectionHeaderFailed =
      'Reading collection woff2 header exception';

  static const String readHeaderFailed = 'Reading woff2 header exception';

  static const String readTableDirectoryFailed =
      'Reading woff2 tables directory exception';

  static const String reconstructGlyfTableFailed =
      'Reconstructing woff2 glyf table exception';

  static const String reconstructGlyphFailed =
      'Reconstructing woff2 glyph exception';

  static const String reconstructHmtxTableFailed =
      'Reconstructing woff2 hmtx table exception';

  static const String reconstructPointFailed =
      "Reconstructing woff2 glyph's point exception";

  static const String reconstructTableDirectoryFailed =
      'Reconstructing woff2 table directory exception';

  static const String scanlineMustBeginWithEolCodeWord =
      'Scanline must begin with EOL code word.';

  static const String tableDoesNotExist = 'Table {0} does not exist.';

  static const String tableDoesNotExistsIn = 'Table {0} does not exist in {1}';

  static const String thisImageCanNotBeAnImageMask =
      'This image can not be an image mask.';

  static const String tiff50StyleLzwCodesAreNotSupported =
      'TIFF 5.0-style LZW codes are not supported.';

  static const String tiffFillOrderTagMustBeEither1Or2 =
      'TIFF_FILL_ORDER tag must be either 1 or 2.';

  static const String tiffImageException = 'TIFF image exception.';

  static const String tilesAreNotSupported = 'Tiles are not supported.';

  static const String transparencyLengthMustBeEqualTo2WithCcittImages =
      'Transparency length must be equal to 2 with CCITT images';

  static const String ttcIndexDoesntExistInThisTtcFile =
      "TTC index doesn't exist in this TTC file.";

  static const String typeOfFontIsNotRecognized =
      'Type of font is not recognized.';

  static const String typeOfFontIsNotRecognizedParameterized =
      'Type of font {0} is not recognized.';

  static const String unexpectedCloseBracket = 'Unexpected close bracket.';

  static const String unexpectedGtGt = "Unexpected '>>'.";

  static const String unknownCompressionType = 'Unknown compression type {0}.';

  static const String unknownIoException = 'Unknown I/O exception.';

  static const String unknownPngFilter = 'Unknown PNG filter.';

  static const String unsupportedBoxSizeEqEq0 = 'Unsupported box size == 0.';

  static const String unsupportedEncodingException =
      'Unsupported encoding exception.';

  static const String unsupportedJpegMarker =
      '{0} unsupported jpeg marker {1}.';

  static const String writeFailed = 'Writing woff2 exception';

  static const String encodingError =
      'Error during encoding the following code point: {0} in characterset: {1}';

  static const String onlyBmpEncoding =
      'This encoder only accepts BMP codepoints';

  static const String readingByteLimitMustNotBeLessZero =
      'The reading byte limit argument must not be less than zero.';
}
