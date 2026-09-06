/// Diagnostic templates for PDFCraft. Public identifiers and format slots are stable.
class CraftIoExceptionMessageConstant {
  CraftIoExceptionMessageConstant._();

  static const String allFillBitsPrecedingEolCodeMustBe0 =
      'Nonzero padding bits precede the fax EOL code; only zero fill bits are allowed.';

  static const String alreadyClosed = 'The resource has already been closed.';

  static const String badEndiannessTag0x4949Or0x4d4d =
      'Invalid TIFF byte-order marker; expected 0x4949 (II) or 0x4d4d (MM).';

  static const String badMagicNumberShouldBe42 =
      'The TIFF identification number must be 42.';

  static const String bitsPerComponentMustBe1248 =
      'Image component depth must be one of 1, 2, 4, or 8 bits.';

  static const String bitsPerSampleIsNotSupported =
      'Sample depth {0} is not implemented by this decoder.';

  static const String
      bitSamplesAreNotSupportedForHorizontalDifferencingPredictor =
      'Horizontal differencing cannot decode samples with {0} bits.';

  static const String bmpImageException = 'BMP image processing failed.';

  static const String brotliDecodingFailed =
      'Brotli decompression of the WOFF2 font failed.';

  static const String bufferReadFailed =
      'The WOFF2 input buffer could not be read.';

  static const String bytesCanBeAssignedToByteArrayOutputStreamOnly =
      'Assigning raw bytes requires a ByteArrayOutputStream destination.';

  static const String bytesCanBeResetInByteArrayOutputStreamOnly =
      'Resetting raw bytes requires a ByteArrayOutputStream destination.';

  static const String cannotFindFrame =
      'No image frame exists at zero-based index {0}.';

  static const String cannotGetTiffImageColor =
      'TIFF color information could not be determined.';

  static const String cannotHandleBoxSizesHigherThan2pow32 =
      'Box lengths above 2^32 are unsupported.';

  static const String cannotInflateTiffImage =
      'Inflate decompression of TIFF image data failed.';

  static const String cannotOpenOutputDirectory =
      'The output directory for <filename> could not be opened.';

  static const String cannotReadTiffImage =
      'TIFF image data could not be read.';

  static const String cannotWriteByte =
      'Writing a single byte to the output failed.';

  static const String cannotWriteBytes =
      'Writing the byte sequence to the output failed.';

  static const String cannotWriteFloatNumber =
      'The floating-point value could not be written.';

  static const String cannotWriteIntNumber =
      'The integer value could not be written.';

  static const String ccittCompressionTypeMustBeCcittg4Ccittg31dOrCcittg32d =
      'Select one of CCITTG4, CCITTG3_1D, or CCITTG3_2D for fax compression.';

  static const String characterCodeException =
      'Character-code processing failed.';

  static const String cmapTableMergingIsNotSupported =
      'Merging font cmap tables is unavailable.';

  static const String cmapWasNotFound =
      'CMap lookup returned no mapping for {0}.';

  static const String compareCommandIsNotSpecified =
      'Configure the ImageMagick comparison command before comparing images.';

  static const String compareCommandSpecifiedIncorrectly =
      'The configured ImageMagick comparison command is invalid.';

  static const String componentsMustBe134 =
      'An image must have 1, 3, or 4 color components.';

  static const String compressionIsNotSupported =
      'The decoder does not implement compression mode {0}.';

  static const String
      compressionJpegIsOnlySupportedWithASingleStripThisImageHasStrips =
      'JPEG-compressed TIFF requires one strip; this image contains {0} strips.';

  static const String corruptedJfifMarker =
      'Image {0} has a malformed JFIF marker.';

  static const String directoryNumberIsTooLarge =
      'The requested TIFF directory index exceeds the supported range.';

  static const String eolCodeWordEncounteredInBlackRun =
      'A fax EOL code interrupted a black-pixel run.';

  static const String eolCodeWordEncounteredInWhiteRun =
      'A fax EOL code interrupted a white-pixel run.';

  static const String errorAtFilePointer =
      'Input processing failed at file offset {0}.';

  static const String errorReadingString =
      'The input string could not be read.';

  static const String errorWithJpMarker =
      'The JPEG2000 JP signature marker is malformed.';

  static const String expectedFtypMarker =
      'JPEG2000 parsing requires an FTYP marker at this position.';

  static const String expectedIhdrMarker =
      'JPEG2000 parsing requires an IHDR marker at this position.';

  static const String expectedJp2hMarker =
      'JPEG2000 parsing requires a JP2H marker at this position.';

  static const String expectedJpMarker =
      'JPEG2000 parsing requires a JP signature marker at this position.';

  static const String expectedTrailingZeroBitsForByteAlignedLines =
      'Byte-aligned scanlines must finish with zero padding bits.';

  static const String extraSamplesAreNotSupported =
      'This decoder cannot process extra image samples.';

  static const String fdfStartxrefNotFound =
      'The FDF input has no startxref marker.';

  static const String firstScanlineMustBe1dEncoded =
      'Fax data must encode its initial scanline in one-dimensional mode.';

  static const String fontFileNotFound = 'The font path does not exist: {0}.';

  static const String ghostscriptFailed =
      'Ghostscript processing failed for <filename>.';

  static const String gifImageException = 'GIF image processing failed.';

  static const String gifSignatureNotFound =
      'The image does not begin with a GIF signature.';

  static const String gsEnvironmentVariableIsNotSpecified =
      'A valid Ghostscript command must be configured before rendering.';

  static const String gtNotExpected =
      'A closing angle bracket (>) appeared where it was not allowed.';

  static const String
      iccProfileContainsComponentsWhileTheImageDataContainsComponents =
      'Component counts differ: ICC profile {0}, image data {1}.';

  static const String illegalValueForPredictorInTiffFile =
      'The TIFF predictor field contains an invalid value.';

  static const String imageFormatCannotBeRecognized =
      'The input bytes do not identify a supported image format.';

  static const String imageIsNotAMaskYouMustCallImageDataMakeMask =
      'Call ImageData.makeMask() before using this image as a mask.';

  static const String imageMagickOutputIsNull =
      'The ImageMagick process returned no output.';

  static const String imageMagickProcessExecutionFailed =
      'ImageMagick reported errors while processing the image: ';

  static const String imageMaskCannotContainAnotherImageMask =
      'An image used as a mask cannot itself have an image mask.';

  static const String incompatibleGlyphDataDuringFontMerging =
      'The fonts being merged have incompatible glyph outlines or metrics.';

  static const String incompletePalette =
      'The image palette has fewer entries than required.';

  static const String incorrectSignature =
      'The WOFF2 signature bytes are invalid.';

  static const String invalidBmpFileCompression =
      'The BMP compression field is invalid.';

  static const String invalidCodeEncountered =
      'The compressed data contains an invalid code.';

  static const String
      invalidCodeEncounteredWhileDecoding2dGroup3CompressedData =
      'A code in the Group 3 two-dimensional fax data is invalid.';

  static const String
      invalidCodeEncounteredWhileDecoding2dGroup4CompressedData =
      'A code in the Group 4 two-dimensional fax data is invalid.';

  static const String invalidIccProfile =
      'The supplied bytes do not form a valid ICC profile.';

  static const String invalidJpeg2000File =
      'The supplied bytes do not form a valid JPEG2000 file.';

  static const String invalidMagicValueForBmpFileMustBeBm =
      'BMP input must begin with the BM identification bytes.';

  static const String invalidTtcFile =
      'Input {0} is not a valid TrueType collection.';

  static const String invalidWoff2FontFile =
      'The font does not have a valid WOFF2 structure.';

  static const String invalidWoffFile =
      'The font does not have a valid WOFF structure.';

  static const String ioException = 'An input/output operation failed.';

  static const String isNotAnAfmOrPfmFontFile =
      'Font {0} is neither an AFM nor a PFM file.';

  static const String isNotAValidJpegFile =
      'Image {0} does not have a valid JPEG structure.';

  static const String jbig2ImageException = 'JBIG2 image processing failed.';

  static const String jpeg2000ImageException =
      'JPEG2000 image processing failed.';

  static const String jpegImageException = 'JPEG image processing failed.';

  static const String locaSizeOverflow =
      'The reconstructed WOFF2 loca table exceeds its allowed size.';

  static const String missingTagsForOjpegCompression =
      'Required TIFF tags for OJPEG compression are absent.';

  static const String mustHave8BitsPerComponent =
      'Image {0} requires an 8-bit depth for each component.';

  static const String notAtTrueTypeFile =
      'Font {0} does not have a TrueType signature.';

  static const String notFoundAsFileOrResource =
      'No file or bundled resource was found for {0}.';

  static const String paddingOverflow =
      'WOFF2 alignment padding exceeds the available buffer.';

  static const String pageNumberMustBeGtEq1 =
      'Page numbers are one-based and cannot be below 1.';

  static const String pdfHeaderNotFound =
      'The input has no recognizable PDF header.';

  static const String pdfStartxrefNotFound =
      'The PDF input has no startxref marker.';

  static const String pdfEofNotFound = 'The PDF input has no %%EOF end marker.';

  static const String photometricIsNotSupported =
      'Photometric interpretation {0} is not implemented.';

  static const String planarImagesAreNotSupported =
      'Images with separate component planes cannot be decoded here.';

  static const String pngImageException = 'PNG image processing failed.';

  static const String prematureEofWhileReadingJpeg =
      'JPEG data ended before the image was fully read.';

  static const String readBase128Failed =
      'A WOFF2 Base128 integer could not be decoded.';

  static const String readCollectionHeaderFailed =
      'The WOFF2 collection header could not be decoded.';

  static const String readHeaderFailed =
      'The WOFF2 file header could not be decoded.';

  static const String readTableDirectoryFailed =
      'The WOFF2 table directory could not be decoded.';

  static const String reconstructGlyfTableFailed =
      'WOFF2 glyf table reconstruction failed.';

  static const String reconstructGlyphFailed =
      'A WOFF2 glyph could not be reconstructed.';

  static const String reconstructHmtxTableFailed =
      'WOFF2 horizontal-metrics table reconstruction failed.';

  static const String reconstructPointFailed =
      'A WOFF2 glyph point could not be reconstructed.';

  static const String reconstructTableDirectoryFailed =
      'WOFF2 table-directory reconstruction failed.';

  static const String scanlineMustBeginWithEolCodeWord =
      'The fax scanline is missing its leading EOL code.';

  static const String tableDoesNotExist = 'The requested table {0} is absent.';

  static const String tableDoesNotExistsIn =
      'Input {1} has no table named {0}.';

  static const String thisImageCanNotBeAnImageMask =
      'The image format or component layout does not permit use as a mask.';

  static const String tiff50StyleLzwCodesAreNotSupported =
      'This decoder cannot read the legacy TIFF 5.0 LZW variant.';

  static const String tiffFillOrderTagMustBeEither1Or2 =
      'TIFF FillOrder accepts only 1 or 2.';

  static const String tiffImageException = 'TIFF image processing failed.';

  static const String tilesAreNotSupported =
      'Tiled image decoding is unavailable.';

  static const String transparencyLengthMustBeEqualTo2WithCcittImages =
      'CCITT transparency must contain exactly two values.';

  static const String ttcIndexDoesntExistInThisTtcFile =
      'The requested font index is absent from this TrueType collection.';

  static const String typeOfFontIsNotRecognized =
      'The font format could not be identified.';

  static const String typeOfFontIsNotRecognizedParameterized =
      'The format of font {0} could not be identified.';

  static const String unexpectedCloseBracket =
      'A closing bracket appeared outside its matching structure.';

  static const String unexpectedGtGt =
      'A dictionary terminator (>>) appeared at an invalid position.';

  static const String unknownCompressionType =
      'Compression identifier {0} is unrecognized.';

  static const String unknownIoException =
      'An input/output failure occurred without a more specific diagnosis.';

  static const String unknownPngFilter =
      'The PNG scanline filter identifier is unrecognized.';

  static const String unsupportedBoxSizeEqEq0 =
      'A box length of zero cannot be handled here.';

  static const String unsupportedEncodingException =
      'The requested character encoding is unavailable.';

  static const String unsupportedJpegMarker =
      'Image {0} uses JPEG marker {1}, which this decoder does not implement.';

  static const String writeFailed =
      'Writing the reconstructed WOFF2 font failed.';

  static const String encodingError =
      'Code point {0} cannot be encoded in character set {1}.';

  static const String onlyBmpEncoding =
      'This encoder accepts only Unicode Basic Multilingual Plane code points.';

  static const String readingByteLimitMustNotBeLessZero =
      'The byte-read limit must be zero or greater.';
}
