import 'dart:typed_data';
import '../exceptions/io_exception.dart';
import '../exceptions/io_exception_message_constant.dart';

/// Decodes TIFF FAX compressed data (CCITT Group 3 and Group 4).
class TIFFFaxDecoder {
  int _bitPointer = 0;
  int _bytePointer = 0;
  Uint8List? _data;
  final int _w;
  final int _h;
  final int _fillOrder;

  int _changingElemSize = 0;
  late List<int> _prevChangingElems;
  late List<int> _currChangingElems;
  int _lastChangingElement = 0;
  // int _compression = 2; // Unused
  // int _uncompressedMode = 0; // Unused
  int _fillBits = 0;
  int _oneD = 0;

  int fails = 0;
  // int _lineBitNum = 0; // Unused

  bool recoverFromImageError = false;

  void setRecoverFromImageError(bool r) {
    recoverFromImageError = r;
  }

  /// Table for flipping bytes when fillOrder = 2.
  static final Uint8List flipTable = Uint8List.fromList([
    0x00,
    0x80,
    0x40,
    0xc0,
    0x20,
    0xa0,
    0x60,
    0xe0,
    0x10,
    0x90,
    0x50,
    0xd0,
    0x30,
    0xb0,
    0x70,
    0xf0,
    0x08,
    0x88,
    0x48,
    0xc8,
    0x28,
    0xa8,
    0x68,
    0xe8,
    0x18,
    0x98,
    0x58,
    0xd8,
    0x38,
    0xb8,
    0x78,
    0xf8,
    0x04,
    0x84,
    0x44,
    0xc4,
    0x24,
    0xa4,
    0x64,
    0xe4,
    0x14,
    0x94,
    0x54,
    0xd4,
    0x34,
    0xb4,
    0x74,
    0xf4,
    0x0c,
    0x8c,
    0x4c,
    0xcc,
    0x2c,
    0xac,
    0x6c,
    0xec,
    0x1c,
    0x9c,
    0x5c,
    0xdc,
    0x3c,
    0xbc,
    0x7c,
    0xfc,
    0x02,
    0x82,
    0x42,
    0xc2,
    0x22,
    0xa2,
    0x62,
    0xe2,
    0x12,
    0x92,
    0x52,
    0xd2,
    0x32,
    0xb2,
    0x72,
    0xf2,
    0x0a,
    0x8a,
    0x4a,
    0xca,
    0x2a,
    0xaa,
    0x6a,
    0xea,
    0x1a,
    0x9a,
    0x5a,
    0xda,
    0x3a,
    0xba,
    0x7a,
    0xfa,
    0x06,
    0x86,
    0x46,
    0xc6,
    0x26,
    0xa6,
    0x66,
    0xe6,
    0x16,
    0x96,
    0x56,
    0xd6,
    0x36,
    0xb6,
    0x76,
    0xf6,
    0x0e,
    0x8e,
    0x4e,
    0xce,
    0x2e,
    0xae,
    0x6e,
    0xee,
    0x1e,
    0x9e,
    0x5e,
    0xde,
    0x3e,
    0xbe,
    0x7e,
    0xfe,
    0x01,
    0x81,
    0x41,
    0xc1,
    0x21,
    0xa1,
    0x61,
    0xe1,
    0x11,
    0x91,
    0x51,
    0xd1,
    0x31,
    0xb1,
    0x71,
    0xf1,
    0x09,
    0x89,
    0x49,
    0xc9,
    0x29,
    0xa9,
    0x69,
    0xe9,
    0x19,
    0x99,
    0x59,
    0xd9,
    0x39,
    0xb9,
    0x79,
    0xf9,
    0x05,
    0x85,
    0x45,
    0xc5,
    0x25,
    0xa5,
    0x65,
    0xe5,
    0x15,
    0x95,
    0x55,
    0xd5,
    0x35,
    0xb5,
    0x75,
    0xf5,
    0x0d,
    0x8d,
    0x4d,
    0xcd,
    0x2d,
    0xad,
    0x6d,
    0xed,
    0x1d,
    0x9d,
    0x5d,
    0xdd,
    0x3d,
    0xbd,
    0x7d,
    0xfd,
    0x03,
    0x83,
    0x43,
    0xc3,
    0x23,
    0xa3,
    0x63,
    0xe3,
    0x13,
    0x93,
    0x53,
    0xd3,
    0x33,
    0xb3,
    0x73,
    0xf3,
    0x0b,
    0x8b,
    0x4b,
    0xcb,
    0x2b,
    0xab,
    0x6b,
    0xeb,
    0x1b,
    0x9b,
    0x5b,
    0xdb,
    0x3b,
    0xbb,
    0x7b,
    0xfb,
    0x07,
    0x87,
    0x47,
    0xc7,
    0x27,
    0xa7,
    0x67,
    0xe7,
    0x17,
    0x97,
    0x57,
    0xd7,
    0x37,
    0xb7,
    0x77,
    0xf7,
    0x0f,
    0x8f,
    0x4f,
    0xcf,
    0x2f,
    0xaf,
    0x6f,
    0xef,
    0x1f,
    0x9f,
    0x5f,
    0xdf,
    0x3f,
    0xbf,
    0x7f,
    0xff
  ]);

  static const List<int> _white = [
    6430,
    6400,
    6400,
    6400,
    3225,
    3225,
    3225,
    3225,
    944,
    944,
    944,
    944,
    976,
    976,
    976,
    976,
    1456,
    1456,
    1456,
    1456,
    1488,
    1488,
    1488,
    1488,
    718,
    718,
    718,
    718,
    718,
    718,
    718,
    718,
    750,
    750,
    750,
    750,
    750,
    750,
    750,
    750,
    1520,
    1520,
    1520,
    1520,
    1552,
    1552,
    1552,
    1552,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    428,
    654,
    654,
    654,
    654,
    654,
    654,
    654,
    654,
    1072,
    1072,
    1072,
    1072,
    1104,
    1104,
    1104,
    1104,
    1136,
    1136,
    1136,
    1136,
    1168,
    1168,
    1168,
    1168,
    1200,
    1200,
    1200,
    1200,
    1232,
    1232,
    1232,
    1232,
    622,
    622,
    622,
    622,
    622,
    622,
    622,
    622,
    1008,
    1008,
    1008,
    1008,
    1040,
    1040,
    1040,
    1040,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    44,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    396,
    1712,
    1712,
    1712,
    1712,
    1744,
    1744,
    1744,
    1744,
    846,
    846,
    846,
    846,
    846,
    846,
    846,
    846,
    1264,
    1264,
    1264,
    1264,
    1296,
    1296,
    1296,
    1296,
    1328,
    1328,
    1328,
    1328,
    1360,
    1360,
    1360,
    1360,
    1392,
    1392,
    1392,
    1392,
    1424,
    1424,
    1424,
    1424,
    686,
    686,
    686,
    686,
    686,
    686,
    686,
    686,
    910,
    910,
    910,
    910,
    910,
    910,
    910,
    910,
    1968,
    1968,
    1968,
    1968,
    2000,
    2000,
    2000,
    2000,
    2032,
    2032,
    2032,
    2032,
    16,
    16,
    16,
    16,
    10257,
    10257,
    10257,
    10257,
    12305,
    12305,
    12305,
    12305,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    330,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    362,
    878,
    878,
    878,
    878,
    878,
    878,
    878,
    878,
    1904,
    1904,
    1904,
    1904,
    1936,
    1936,
    1936,
    1936,
    -18413,
    -18413,
    -16365,
    -16365,
    -14317,
    -14317,
    -10221,
    -10221,
    590,
    590,
    590,
    590,
    590,
    590,
    590,
    590,
    782,
    782,
    782,
    782,
    782,
    782,
    782,
    782,
    1584,
    1584,
    1584,
    1584,
    1616,
    1616,
    1616,
    1616,
    1648,
    1648,
    1648,
    1648,
    1680,
    1680,
    1680,
    1680,
    814,
    814,
    814,
    814,
    814,
    814,
    814,
    814,
    1776,
    1776,
    1776,
    1776,
    1808,
    1808,
    1808,
    1808,
    1840,
    1840,
    1840,
    1840,
    1872,
    1872,
    1872,
    1872,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    6157,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    -12275,
    14353,
    14353,
    14353,
    14353,
    16401,
    16401,
    16401,
    16401,
    22547,
    22547,
    24595,
    24595,
    20497,
    20497,
    20497,
    20497,
    18449,
    18449,
    18449,
    18449,
    26643,
    26643,
    28691,
    28691,
    30739,
    30739,
    -32749,
    -32749,
    -30701,
    -30701,
    -28653,
    -28653,
    -26605,
    -26605,
    -24557,
    -24557,
    -22509,
    -22509,
    -20461,
    -20461,
    8207,
    8207,
    8207,
    8207,
    8207,
    8207,
    8207,
    8207,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    72,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    104,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    4107,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    266,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    298,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    136,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    168,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    460,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    492,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    2059,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    200,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232,
    232
  ];

  static const List<int> _additionalMakeup = [
    28679,
    28679,
    31752,
    -32759,
    -31735,
    -30711,
    -29687,
    -28663,
    29703,
    29703,
    30727,
    30727,
    -27639,
    -26615,
    -25591,
    -24567
  ];

  static const List<int> _initBlack = [
    3226,
    6412,
    200,
    168,
    38,
    38,
    134,
    134,
    100,
    100,
    100,
    100,
    68,
    68,
    68,
    68
  ];

  static const List<int> _twoBitBlack = [292, 260, 226, 226];

  static const List<int> _black = [
    62,
    62,
    30,
    30,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    3225,
    588,
    588,
    588,
    588,
    588,
    588,
    588,
    588,
    1680,
    1680,
    20499,
    22547,
    24595,
    26643,
    1776,
    1776,
    1808,
    1808,
    -24557,
    -22509,
    -20461,
    -18413,
    1904,
    1904,
    1936,
    1936,
    -16365,
    -14317,
    782,
    782,
    782,
    782,
    814,
    814,
    814,
    814,
    -12269,
    -10221,
    10257,
    10257,
    12305,
    12305,
    14353,
    14353,
    16403,
    18451,
    1712,
    1712,
    1744,
    1744,
    28691,
    30739,
    -32749,
    -30701,
    -28653,
    -26605,
    2061,
    2061,
    2061,
    2061,
    2061,
    2061,
    2061,
    2061,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    424,
    750,
    750,
    750,
    750,
    1616,
    1616,
    1648,
    1648,
    1424,
    1424,
    1456,
    1456,
    1488,
    1488,
    1520,
    1520,
    1840,
    1840,
    1872,
    1872,
    1968,
    1968,
    8209,
    8209,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    524,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    556,
    1552,
    1552,
    1584,
    1584,
    2000,
    2000,
    2032,
    2032,
    976,
    976,
    1008,
    1008,
    1040,
    1040,
    1072,
    1072,
    1296,
    1296,
    1328,
    1328,
    718,
    718,
    718,
    718,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    456,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    326,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    358,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    490,
    4113,
    4113,
    6161,
    6161,
    848,
    848,
    880,
    880,
    912,
    912,
    944,
    944,
    622,
    622,
    622,
    622,
    654,
    654,
    654,
    654,
    1104,
    1104,
    1136,
    1136,
    1168,
    1168,
    1200,
    1200,
    1232,
    1232,
    1264,
    1264,
    686,
    686,
    686,
    686,
    1360,
    1360,
    1392,
    1392,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390,
    390
  ];

  static const List<int> _twoDCodes = [
    80,
    88,
    23,
    71,
    30,
    30,
    62,
    62,
    4,
    4,
    4,
    4,
    4,
    4,
    4,
    4,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    35,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    51,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41,
    41
  ];

  /// Creates a TIFFFaxDecoder.
  TIFFFaxDecoder(this._fillOrder, this._w, this._h) {
    _prevChangingElems = List<int>.filled(2 * _w, 0);
    _currChangingElems = List<int>.filled(2 * _w, 0);
  }

  /// Sets options for decoding.
  void setOptions(int compression, int tiffT4Options, int tiffT6Options) {
    // _compression = compression;
    _oneD = tiffT4Options & 0x01;
    // _uncompressedMode = (tiffT4Options & 0x02) >> 1;
    _fillBits = (tiffT4Options & 0x04) >> 2;
    // tiffT6Options are used locally in decodeT6 or passed down
  }

  /// Reverses the bits in each byte of the array.

  /// Decodes Group 4 compressed data.
  void decodeT6(Uint8List buffer, Uint8List compData, int startX, int height,
      int tiffT6Options) {
    _data = compData;
    // _compression = 4;
    _bitPointer = 0;
    _bytePointer = 0;

    int scanlineStride = (_w + 7) ~/ 8;
    int a0;
    int a1;
    int b1;
    int b2;
    int entry;
    int code;
    int bits;
    bool isWhite;
    int currIndex;
    List<int> temp;
    // Return values from getNextChangingElement
    final b = List<int>.filled(2, 0);

    // uncompressedMode = (tiffT6Options & 0x02) >> 1;
    _fillBits = (tiffT6Options & 0x04) >> 2;

    // Local cached reference
    var cce = _currChangingElems;

    // Assume invisible preceding row of all white pixels
    _changingElemSize = 0;
    cce[_changingElemSize++] = _w;
    cce[_changingElemSize++] = _w;

    int lineOffset = 0;
    int bitOffset;

    for (int lines = 0; lines < height; lines++) {
      a0 = -1;
      isWhite = true;

      // Swap changing elements
      temp = _prevChangingElems;
      _prevChangingElems = _currChangingElems;
      _currChangingElems = temp;
      cce = _currChangingElems;
      currIndex = 0;

      bitOffset = startX;

      if (_fillBits == 1) {
        if (_bitPointer > 0) {
          int bitsLeft = 8 - _bitPointer;
          if (_nextNBits(bitsLeft) != 0) {
            throw IoException(IoExceptionMessageConstant
                .expectedTrailingZeroBitsForByteAlignedLines);
          }
        }
      }

      _lastChangingElement = 0;

      while (bitOffset < _w && _bytePointer < _data!.length - 1) {
        _getNextChangingElement(a0, isWhite, b);
        b1 = b[0];
        b2 = b[1];

        entry = _nextLesserThan8Bits(7);
        entry = _twoDCodes[entry] & 0xff;
        code = (entry & 0x78) >> 3;
        bits = entry & 0x07;

        if (code == 0) {
          // Pass
          if (!isWhite) {
            _setToBlack(buffer, lineOffset, bitOffset, b2 - bitOffset);
          }
          bitOffset = a0 = b2;
          _updatePointer(7 - bits);
        } else {
          if (code == 1) {
            // Horizontal
            _updatePointer(7 - bits);
            int number;
            if (isWhite) {
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            } else {
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            }
            a0 = bitOffset;
          } else {
            // Vertical
            if (code <= 8) {
              a1 = b1 + (code - 5);
              cce[currIndex++] = a1;
              if (!isWhite) {
                _setToBlack(buffer, lineOffset, bitOffset, a1 - bitOffset);
              }
              bitOffset = a0 = a1;
              isWhite = !isWhite;
              _updatePointer(7 - bits);
            } else {
              if (code == 11) {
                if (_nextLesserThan8Bits(3) != 7) {
                  throw IoException(IoExceptionMessageConstant
                      .invalidCodeEncounteredWhileDecoding2dGroup4CompressedData);
                }
                // EOF logic simplified
                bool exit = false;
                int zeros = 0;
                while (!exit) {
                  while (_nextLesserThan8Bits(1) != 1) {
                    zeros++;
                  }
                  if (zeros > 5) {
                    // Exit code
                    zeros = zeros - 6;
                    if (!isWhite && (zeros > 0)) {
                      cce[currIndex++] = bitOffset;
                    }
                    bitOffset += zeros;
                    if (zeros > 0) {
                      isWhite = true;
                    }
                    if (_nextLesserThan8Bits(1) == 0) {
                      if (!isWhite) cce[currIndex++] = bitOffset;
                      isWhite = true;
                    } else {
                      if (isWhite) cce[currIndex++] = bitOffset;
                      isWhite = false;
                    }
                    exit = true;
                  } else if (zeros == 5) {
                    if (!isWhite) cce[currIndex++] = bitOffset;
                    bitOffset += zeros;
                    isWhite = true;
                  } else {
                    bitOffset += zeros;
                    cce[currIndex++] = bitOffset;
                    _setToBlack(buffer, lineOffset, bitOffset, 1);
                    ++bitOffset;
                    isWhite = false;
                  }
                }
              } else {
                bitOffset = _w;
                _updatePointer(7 - bits);
              }
            }
          }
        }
      }

      if (currIndex < cce.length) {
        cce[currIndex++] = bitOffset;
      }
      _changingElemSize = currIndex;
      lineOffset += scanlineStride;
    }
  }

  void _getNextChangingElement(int a0, bool isWhite, List<int> b) {
    int start = _lastChangingElement & 0xFFFE;
    if (isWhite) start += 0;

    final pce = _prevChangingElems;

    for (int i = start; i < _changingElemSize; i++) {
      if (pce[i] > a0) {
        if (isWhite && (i & 1) == 1) {
          continue;
        }
        if (!isWhite && (i & 1) == 0) {
          continue;
        }

        _lastChangingElement = i;
        b[0] = pce[i];

        if (i + 1 < _changingElemSize) {
          b[1] = pce[i + 1];
        } else {
          b[1] = _w + 1000;
        }
        return;
      }
    }
    b[0] = _w;
    b[1] = _w;
  }

  void _setToBlack(
      Uint8List buffer, int lineOffset, int bitOffset, int numBits) {
    int bitNum = 8 * lineOffset + bitOffset;
    int lastBit = bitNum + numBits;
    int byteNum = bitNum >> 3;

    int shift = bitNum & 0x7;
    if (shift > 0) {
      int maskVal = 1 << (7 - shift);
      int val = buffer[byteNum];
      while (maskVal > 0 && bitNum < lastBit) {
        val |= maskVal;
        maskVal >>= 1;
        ++bitNum;
      }
      buffer[byteNum] = val; // Store back modified value
    }

    byteNum = bitNum >> 3;
    while (bitNum < lastBit - 7) {
      buffer[byteNum++] = 0xFF;
      bitNum += 8;
    }

    while (bitNum < lastBit) {
      byteNum = bitNum >> 3;
      if (byteNum < buffer.length) {
        buffer[byteNum] = buffer[byteNum] | (1 << (7 - (bitNum & 0x7)));
      }
      ++bitNum;
    }
  }

  int _nextNBits(int bitsToGet) {
    int b, next, next2;
    int l = _data!.length - 1;
    int bp = _bytePointer;

    if (_fillOrder == 2) {
      b = flipTable[_data![bp] & 0xFF];
      if (bp == l) {
        next = 0;
        next2 = 0;
      } else if ((bp + 1) == l) {
        next = flipTable[_data![bp + 1] & 0xFF];
        next2 = 0;
      } else {
        next = flipTable[_data![bp + 1] & 0xFF];
        next2 = flipTable[_data![bp + 2] & 0xFF];
      }
    } else {
      b = _data![bp] & 0xFF;
      if (bp == l) {
        next = 0;
        next2 = 0;
      } else if ((bp + 1) == l) {
        next = _data![bp + 1] & 0xFF;
        next2 = 0;
      } else {
        next = _data![bp + 1] & 0xFF;
        next2 = _data![bp + 2] & 0xFF;
      }
    }

    int val = (b << 16) | (next << 8) | next2;
    int shift = 24 - _bitPointer - bitsToGet;
    int result = (val >> shift) & ((1 << bitsToGet) - 1);

    _bitPointer += bitsToGet;
    if (_bitPointer >= 8) {
      _bytePointer += (_bitPointer >> 3);
      _bitPointer &= 7;
    }
    return result;
  }

  int _nextLesserThan8Bits(int bitsToGet) {
    int b, next;
    int l = _data!.length - 1;
    int bp = _bytePointer;

    if (_fillOrder == 2) {
      b = flipTable[_data![bp] & 0xFF];
      if (bp == l) {
        next = 0;
      } else {
        next = flipTable[_data![bp + 1] & 0xFF];
      }
    } else {
      b = _data![bp] & 0xFF;
      if (bp == l) {
        next = 0;
      } else {
        next = _data![bp + 1] & 0xFF;
      }
    }

    int val = (b << 8) | next;
    int shift = 16 - _bitPointer - bitsToGet;
    int result = (val >> shift) & ((1 << bitsToGet) - 1);

    _bitPointer += bitsToGet;
    if (_bitPointer >= 8) {
      _bytePointer++;
      _bitPointer &= 7;
    }
    return result;
  }

  void _updatePointer(int bitsToMoveBack) {
    _bitPointer -= bitsToMoveBack;
    while (_bitPointer < 0) {
      _bytePointer--;
      _bitPointer += 8;
    }
  }

  int _decodeWhiteCodeWord() {
    int current;
    int entry;
    int bits;
    int isT;
    int twoBits;
    int code = -1;
    int runLength = 0;
    bool isWhite = true;

    while (isWhite) {
      current = _nextNBits(10);
      entry = _white[current];
      isT = entry & 0x0001;
      bits = (entry >> 1) & 0x0f;

      if (bits == 12) {
        twoBits = _nextLesserThan8Bits(2);
        current = ((current << 2) & 0x000c) | twoBits;
        entry = _additionalMakeup[current];
        bits = (entry >> 1) & 0x07;
        code = (entry >> 4) & 0x0fff;
        runLength += code;
        _updatePointer(4 - bits);
      } else {
        if (bits == 0) {
          return runLength;
        }
        if (bits == 15) {
          return runLength;
        }
        code = (entry >> 5) & 0x07ff;
        runLength += code;
        _updatePointer(10 - bits);
        if (isT == 0) {
          isWhite = false;
        }
      }
    }
    return runLength;
  }

  int _decodeBlackCodeWord() {
    int current;
    int entry;
    int bits;
    int isT;
    int code = -1;
    int runLength = 0;
    bool isWhite = false;

    while (!isWhite) {
      current = _nextLesserThan8Bits(4);
      entry = _initBlack[current];
      bits = (entry >> 1) & 0x000f;
      code = (entry >> 5) & 0x07ff;

      if (code == 100) {
        current = _nextNBits(9);
        entry = _black[current];
        isT = entry & 0x0001;
        bits = (entry >> 1) & 0x000f;
        code = (entry >> 5) & 0x07ff;

        if (bits == 12) {
          _updatePointer(5);
          current = _nextLesserThan8Bits(4);
          entry = _additionalMakeup[current];
          bits = (entry >> 1) & 0x07;
          code = (entry >> 4) & 0x0fff;
          runLength += code;
          _updatePointer(4 - bits);
        } else if (bits == 15) {
          return runLength;
        } else {
          runLength += code;
          _updatePointer(9 - bits);
          if (isT == 0) {
            isWhite = true;
          }
        }
      } else if (code == 200) {
        current = _nextLesserThan8Bits(2);
        entry = _twoBitBlack[current];
        code = (entry >> 5) & 0x07ff;
        bits = (entry >> 1) & 0x0f;
        runLength += code;
        _updatePointer(2 - bits);
        isWhite = true;
      } else {
        runLength += code;
        _updatePointer(4 - bits);
        isWhite = true;
      }
    }
    return runLength;
  }

  /// Decodes a single scanline (1D).
  void _decodeNextScanline(Uint8List buffer, int lineOffset) {
    int code = 0;
    int isT = 0;
    int current;
    int entry;
    // float bits;
    int bits;
    int twoBits;
    bool isWhite = true;
    int bitOffset = 0;

    _changingElemSize = 0;
    final cce = _currChangingElems;

    while (bitOffset < _w) {
      int runOffset = bitOffset;
      while (isWhite && bitOffset < _w) {
        current = _nextNBits(10);
        entry = _white[current];
        isT = entry & 0x0001;
        bits = (entry >> 1) & 0x0f;

        if (bits == 12) {
          twoBits = _nextLesserThan8Bits(2);
          current = ((current << 2) & 0x000c) | twoBits;
          entry = _additionalMakeup[current];
          bits = (entry >> 1) & 0x07;
          code = (entry >> 4) & 0x0fff;
          bitOffset += code;
          _updatePointer(4 - bits);
        } else {
          if (bits == 0) {
            fails++;
            // Invalid code encountered
          } else {
            if (bits == 15) {
              fails++;
              // EOL?
              return;
            } else {
              code = (entry >> 5) & 0x07ff;
              bitOffset += code;
              _updatePointer(10 - bits);
              if (isT == 0) {
                isWhite = false;
                cce[_changingElemSize++] = bitOffset;
              }
            }
          }
        }
      }

      if (bitOffset == _w) {
        int runLength = bitOffset - runOffset;
        if (isWhite && runLength != 0 && runLength % 64 == 0) {
          // Ensure next code is terminating code for white run of length zero?
          // C# check: NextNBits(8) != 0x35
          // But here we might just consume.
          try {
            if (_nextNBits(8) != 0x35) {
              fails++;
            }
            _updatePointer(8);
          } catch (e) {
            // ignore
          }
        }
        break;
      }

      // Black run
      // int runOffsetBlack = bitOffset;
      while (!isWhite && bitOffset < _w) {
        current = _nextLesserThan8Bits(4);
        entry = _initBlack[current];
        isT = entry & 0x0001;
        bits = (entry >> 1) & 0x000f;
        code = (entry >> 5) & 0x07ff;

        if (code == 100) {
          current = _nextNBits(9);
          entry = _black[current];
          isT = entry & 0x0001;
          bits = (entry >> 1) & 0x000f;
          code = (entry >> 5) & 0x07ff;

          if (bits == 12) {
            _updatePointer(5);
            current = _nextLesserThan8Bits(4);
            entry = _additionalMakeup[current];
            bits = (entry >> 1) & 0x07;
            code = (entry >> 4) & 0x0fff;
            _setToBlack(buffer, lineOffset, bitOffset, code);
            bitOffset += code;
            _updatePointer(4 - bits);
          } else {
            if (bits == 15) {
              fails++;
              return;
            } else {
              _setToBlack(buffer, lineOffset, bitOffset, code);
              bitOffset += code;
              _updatePointer(9 - bits);
              if (isT == 0) {
                isWhite = true;
                cce[_changingElemSize++] = bitOffset;
              }
            }
          }
        } else {
          if (code == 200) {
            current = _nextLesserThan8Bits(2);
            entry = _twoBitBlack[current];
            code = (entry >> 5) & 0x07ff;
            bits = (entry >> 1) & 0x0f;
            _setToBlack(buffer, lineOffset, bitOffset, code);
            bitOffset += code;
            _updatePointer(2 - bits);
            isWhite = true;
            cce[_changingElemSize++] = bitOffset;
          } else {
            _setToBlack(buffer, lineOffset, bitOffset, code);
            bitOffset += code;
            _updatePointer(4 - bits);
            isWhite = true;
            cce[_changingElemSize++] = bitOffset;
          }
        }
      }

      if (bitOffset == _w) {
        // Check termination?
        break;
      }
    }
    cce[_changingElemSize++] = bitOffset;
  }

  /// Decodes RLE.
  void decodeRLE(Uint8List buffer, Uint8List compData) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    // _lineBitNum = 0;
    fails = 0;
    _prevChangingElems = List<int>.filled(_w + 1, 0);
    _currChangingElems = List<int>.filled(_w + 1, 0);

    int scanlineStride = (_w + 7) ~/ 8;
    int lineOffset = 0;

    for (int i = 0; i < _h; i++) {
      _decodeNextScanline(buffer, lineOffset);
      if (_bitPointer != 0) {
        _bytePointer++;
        _bitPointer = 0;
      }
      // _lineBitNum += _w; // Should be bitsPerScanline?
      lineOffset += scanlineStride;
    }
  }

  /// Decodes Group 3 (T4).
  void decodeT4(Uint8List buffer, Uint8List compData) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    // _lineBitNum = 0;
    fails = 0;
    _prevChangingElems = List<int>.filled(_w + 1, 0);
    _currChangingElems = List<int>.filled(_w + 1, 0);

    int scanlineStride = (_w + 7) ~/ 8;
    int lineOffset = 0;

    // EOL check
    if (_data!.length < 2) {
      // Error
      return;
    }

    // Check initial EOL
    // int next12 = _nextNBits(12);
    // if (next12 != 1) fails++; -- C# logic

    try {
      int next12 = _nextNBits(12);
      if (next12 != 1) fails++;
    } catch (e) {
      fails++;
    }
    _updatePointer(12);

    int modeFlag = 0;
    int lines = -1;

    try {
      while (modeFlag != 1) {
        modeFlag = _findNextLine();
        lines++;
      }
    } catch (e) {
      // failed finding line
    }

    _decodeNextScanline(buffer, lineOffset);
    lines++;
    // _lineBitNum += _w;
    lineOffset += scanlineStride;

    int a0, a1, b1, b2;
    // int b0 = 0;
    // int b_1 = 0;
    final b = List<int>.filled(2, 0);
    int entry, code, bits;
    bool isWhite;
    int currIndex;
    List<int> temp;

    while (lines < _h) {
      try {
        modeFlag = _findNextLine();
      } catch (e) {
        fails++;
        break;
      }

      if (modeFlag == 0) {
        // 2D
        temp = _prevChangingElems;
        _prevChangingElems = _currChangingElems;
        _currChangingElems = temp;
        final cce = _currChangingElems; // alias
        currIndex = 0;
        a0 = -1;
        isWhite = true;
        int bitOffset = 0;
        _lastChangingElement = 0;

        while (bitOffset < _w) {
          _getNextChangingElement(a0, isWhite, b);
          b1 = b[0];
          b2 = b[1];

          entry = _nextLesserThan8Bits(7);
          entry = _twoDCodes[entry] & 0xff;
          code = (entry & 0x78) >> 3;
          bits = entry & 0x07;

          if (code == 0) {
            // Pass
            if (!isWhite) {
              _setToBlack(buffer, lineOffset, bitOffset, b2 - bitOffset);
            }
            bitOffset = a0 = b2;
            _updatePointer(7 - bits);
          } else if (code == 1) {
            // Horizontal
            _updatePointer(7 - bits);
            int number;
            if (isWhite) {
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            } else {
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            }
            a0 = bitOffset;
          } else {
            // Vertical
            if (code <= 8) {
              a1 = b1 + (code - 5);
              cce[currIndex++] = a1;
              if (!isWhite) {
                _setToBlack(buffer, lineOffset, bitOffset, a1 - bitOffset);
              }
              bitOffset = a0 = a1;
              isWhite = !isWhite;
              _updatePointer(7 - bits);
            } else {
              fails++;
              break;
            }
          }
        }
        cce[currIndex++] = bitOffset;
        _changingElemSize = currIndex;
      } else {
        // 1D
        _decodeNextScanline(buffer, lineOffset);
      }

      lines++;
      lineOffset += scanlineStride;
    }
  }

  int _findNextLine() {
    int bitIndexMax = (_data!.length * 8) - 1;
    int bitIndexMax12 = bitIndexMax - 12;
    int bitIndex = (_bytePointer * 8) + _bitPointer;

    while (bitIndex <= bitIndexMax12) {
      int next12 = _nextNBits(12);
      bitIndex += 12;
      while (next12 != 1 && bitIndex < bitIndexMax) {
        next12 = ((next12 & 0x7FF) << 1) | (_nextLesserThan8Bits(1) & 1);
        bitIndex++;
      }
      if (next12 == 1) {
        if (_oneD == 1) {
          if (bitIndex < bitIndexMax) {
            return _nextLesserThan8Bits(1);
          }
        } else {
          return 1;
        }
      }
    }
    throw IoException("EOL not found");
  }

  static void reverseBits(Uint8List b) {
    for (int i = 0; i < b.length; i++) {
      // C# FlipTable is 0-255 map.
      // flipTable is available as static final Uint8List in this class.
      b[i] = flipTable[b[i] & 0xff];
    }
  }

  /// Decodes 1D
  void decode1D(Uint8List buffer, Uint8List compData, int startX, int height) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    // _compression = 2; // G3 1D

    int scanlineStride = (_w + 7) ~/ 8;
    int lineOffset = 0;

    for (int lines = 0; lines < height; lines++) {
      _decodeNextScanline(buffer, lineOffset);
      lineOffset += scanlineStride;
    }
  }

  /// Decodes 2D (G3)
  void decode2D(Uint8List buffer, Uint8List compData, int startX, int height,
      int tiffT4Options) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    _fillBits = (tiffT4Options & 0x04) >> 2;
    _oneD = tiffT4Options & 0x01;

    int scanlineStride = (_w + 7) ~/ 8;
    int a0, a1, b1, b2;
    int entry, code, bits;
    bool isWhite;
    int currIndex;
    List<int> temp;
    final b = List<int>.filled(2, 0);

    // Initial invisible white line
    _changingElemSize = 0;
    _currChangingElems[0] = _w;
    _currChangingElems[1] = _w;
    _changingElemSize = 2;

    int lineOffset = 0;

    for (int lines = 0; lines < height; lines++) {
      bool is1D = true;
      try {
        int tag = _findNextLine();
        is1D = (tag == 1);
      } catch (e) {
        fails++;
        // On error, we might skip to next EOL?
        // For now, let's assume it's 1D if we can't find tag
      }

      if (is1D) {
        _decodeNextScanline(buffer, lineOffset);
      } else {
        // 2D line
        temp = _prevChangingElems;
        _prevChangingElems = _currChangingElems;
        _currChangingElems = temp;
        final cce = _currChangingElems;
        currIndex = 0;
        a0 = -1;
        isWhite = true;
        int bitOffset = startX;
        _lastChangingElement = 0;

        while (bitOffset < _w) {
          _getNextChangingElement(a0, isWhite, b);
          b1 = b[0];
          b2 = b[1];

          entry = _nextLesserThan8Bits(7);
          entry = _twoDCodes[entry] & 0xff;
          code = (entry & 0x78) >> 3;
          bits = entry & 0x07;

          if (code == 0) {
            // Pass
            if (!isWhite) {
              _setToBlack(buffer, lineOffset, bitOffset, b2 - bitOffset);
            }
            bitOffset = a0 = b2;
            _updatePointer(7 - bits);
          } else if (code == 1) {
            // Horizontal
            _updatePointer(7 - bits);
            int number;
            if (isWhite) {
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            } else {
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            }
            a0 = bitOffset;
          } else if (code <= 8) {
            // Vertical
            a1 = b1 + (code - 5);
            cce[currIndex++] = a1;
            if (!isWhite) {
              _setToBlack(buffer, lineOffset, bitOffset, a1 - bitOffset);
            }
            bitOffset = a0 = a1;
            isWhite = !isWhite;
            _updatePointer(7 - bits);
          } else {
            // Error
            fails++;
            _updatePointer(7 - bits);
            break;
          }
        }
        cce[currIndex++] = bitOffset;
        _changingElemSize = currIndex;
      }
      lineOffset += scanlineStride;
    }
  }
}
