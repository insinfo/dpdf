/// TIFF tag definitions and constants (from libtiff).
class TiffConstants {
  TiffConstants._();

  // ============ TIFF Tags ============

  /// Subfile data descriptor
  static const int tifftagSubfiletype = 254;

  /// Image width in pixels
  static const int tifftagImagewidth = 256;

  /// Image height in pixels
  static const int tifftagImagelength = 257;

  /// Bits per channel (sample)
  static const int tifftagBitspersample = 258;

  /// Data compression technique
  static const int tifftagCompression = 259;

  // ============ Compression Types ============

  /// Dump mode (no compression)
  static const int compressionNone = 1;

  /// CCITT modified Huffman RLE
  static const int compressionCcittrle = 2;

  /// CCITT Group 3 fax encoding
  static const int compressionCcittfax3 = 3;

  /// CCITT Group 4 fax encoding
  static const int compressionCcittfax4 = 4;

  /// Lempel-Ziv & Welch
  static const int compressionLzw = 5;

  /// Old-style JPEG
  static const int compressionOjpeg = 6;

  /// JPEG DCT compression
  static const int compressionJpeg = 7;

  /// Deflate compression (Adobe)
  static const int compressionAdobeDeflate = 8;

  /// Macintosh RLE (PackBits)
  static const int compressionPackbits = 32773;

  /// Deflate compression
  static const int compressionDeflate = 32946;

  // ============ Photometric Interpretation ============

  /// Photometric interpretation tag
  static const int tifftagPhotometric = 262;

  /// Min value is white
  static const int photometricMiniswhite = 0;

  /// Min value is black
  static const int photometricMinisblack = 1;

  /// RGB color model
  static const int photometricRgb = 2;

  /// Color map indexed
  static const int photometricPalette = 3;

  /// Transparency mask
  static const int photometricMask = 4;

  /// Color separations (CMYK)
  static const int photometricSeparated = 5;

  /// YCbCr
  static const int photometricYcbcr = 6;

  /// CIE L*a*b*
  static const int photometricCielab = 8;

  // ============ Fill Order ============

  /// Data order within a byte
  static const int tifftagFillorder = 266;

  /// Most significant -> least
  static const int fillorderMsb2lsb = 1;

  /// Least significant -> most
  static const int fillorderLsb2msb = 2;

  // ============ Image Structure ============

  /// Strip offsets
  static const int tifftagStripoffsets = 273;

  /// Samples per pixel
  static const int tifftagSamplesperpixel = 277;

  /// Rows per strip
  static const int tifftagRowsperstrip = 278;

  /// Bytes counts for strips
  static const int tifftagStripbytecounts = 279;

  /// Pixels/resolution in X
  static const int tifftagXresolution = 282;

  /// Pixels/resolution in Y
  static const int tifftagYresolution = 283;

  /// Storage organization
  static const int tifftagPlanarconfig = 284;

  /// Single image plane
  static const int planarconfigContig = 1;

  /// Separate planes of data
  static const int planarconfigSeparate = 2;

  // ============ Resolution Unit ============

  /// Units of resolution
  static const int tifftagResolutionunit = 296;

  /// No meaningful units
  static const int resunitNone = 1;

  /// English (inches)
  static const int resunitInch = 2;

  /// Metric (centimeters)
  static const int resunitCentimeter = 3;

  // ============ Predictor ============

  /// Prediction scheme with LZW
  static const int tifftagPredictor = 317;

  /// No predictor
  static const int predictorNone = 1;

  /// Horizontal differencing
  static const int predictorHorizontalDifferencing = 2;

  // ============ Color Map ============

  /// RGB map for palette image
  static const int tifftagColormap = 320;

  // ============ Tiles ============

  /// Tile width
  static const int tifftagTilewidth = 322;

  /// Tile length
  static const int tifftagTilelength = 323;

  /// Offsets to data tiles
  static const int tifftagTileoffsets = 324;

  /// Byte counts for tiles
  static const int tifftagTilebytecounts = 325;

  // ============ Extra Samples ============

  /// Info about extra samples
  static const int tifftagExtrasamples = 338;

  /// Unspecified data
  static const int extrasampleUnspecified = 0;

  /// Associated alpha data
  static const int extrasampleAssocalpha = 1;

  /// Unassociated alpha data
  static const int extrasampleUnassalpha = 2;

  // ============ Sample Format ============

  /// Data sample format
  static const int tifftagSampleformat = 339;

  /// Unsigned integer data
  static const int sampleformatUint = 1;

  /// Signed integer data
  static const int sampleformatInt = 2;

  /// IEEE floating point data
  static const int sampleformatIeeefp = 3;

  /// Untyped data
  static const int sampleformatVoid = 4;

  // ============ JPEG Tables ============

  /// JPEG table stream
  static const int tifftagJpegtables = 347;

  /// JPEG processing algorithm
  static const int tifftagJpegproc = 512;

  /// Baseline sequential
  static const int jpegprocBaseline = 1;

  // ============ Group 3/4 Options ============

  /// Group 3 options (32 flag bits)
  static const int tifftagGroup3options = 292;

  /// 2-dimensional coding
  static const int group3opt2dencoding = 0x1;

  /// Data not compressed
  static const int group3optUncompressed = 0x2;

  /// Fill to byte boundary
  static const int group3optFillbits = 0x4;

  /// Group 4 options (32 flag bits)
  static const int tifftagGroup4options = 293;

  /// ICC profile data
  static const int tifftagIccprofile = 34675;

  /// Orientation
  static const int tifftagOrientation = 274;

  /// Row 0 top, col 0 lhs
  static const int orientationTopleft = 1;
}
