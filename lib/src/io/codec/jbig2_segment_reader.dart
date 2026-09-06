import 'dart:collection';
import 'dart:typed_data';

import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';

/// Class to read a JBIG2 file at a basic level: understand all the segments,
/// understand what segments belong to which pages, how many pages there are,
/// what the width and height of each page is, and global segments if there
/// are any.
class Jbig2SegmentReader {
  static const int symbolDictionary = 0;
  static const int intermediateTextRegion = 4;
  static const int immediateTextRegion = 6;
  static const int immediateLosslessTextRegion = 7;
  static const int patternDictionary = 16;
  static const int intermediateHalftoneRegion = 20;
  static const int immediateHalftoneRegion = 22;
  static const int immediateLosslessHalftoneRegion = 23;
  static const int intermediateGenericRegion = 36;
  static const int immediateGenericRegion = 38;
  static const int immediateLosslessGenericRegion = 39;
  static const int intermediateGenericRefinementRegion = 40;
  static const int immediateGenericRefinementRegion = 42;
  static const int immediateLosslessGenericRefinementRegion = 43;
  static const int pageInformation = 48;
  static const int endOfPage = 49;
  static const int endOfStripe = 50;
  static const int endOfFile = 51;
  static const int profiles = 52;
  static const int tables = 53;
  static const int extension = 62;

  final Map<int, Jbig2Segment> _segments = SplayTreeMap();
  final Map<int, Jbig2Page> _pages = SplayTreeMap();
  final Set<Jbig2Segment> _globals = SplayTreeSet();

  final RandomAccessFileOrArray _ra;
  bool _sequential = false;
  bool _numberOfPagesKnown = false;
  // int _numberOfPages = -1;
  bool _read = false;

  Jbig2SegmentReader(this._ra);

  static Uint8List copyByteArray(Uint8List b) {
    return Uint8List.fromList(b);
  }

  void read() {
    if (_read) {
      throw StateError("already.attempted.a.read.on.this.jbig2.file");
    }
    _read = true;
    _readFileHeader();

    if (_sequential) {
      while (_ra.getPosition() < _ra.length()) {
        Jbig2Segment tmp = _readHeader();
        _readSegment(tmp);
        _segments[tmp.segmentNumber] = tmp;
        // If EOF is reached inside readHeader/readSegment?
        // C# loop condition: ra.GetPosition() < ra.Length()
        // _readHeader might read EOF and return it.
      }
    } else {
      Jbig2Segment tmp;
      do {
        tmp = _readHeader();
        _segments[tmp.segmentNumber] = tmp;
      } while (tmp.type != endOfFile);

      for (var integer in _segments.keys) {
        _readSegment(_segments[integer]!);
      }
    }
  }

  void _readSegment(Jbig2Segment s) {
    int ptr = _ra.getPosition();
    if (s.dataLength == 0xffffffff) {
      // Indeterminate
      return;
    }

    Uint8List data = Uint8List(s.dataLength);
    _ra.readFully(data);
    s.setData(data);

    if (s.type == pageInformation) {
      int last = _ra.getPosition();
      _ra.seek(ptr);
      int pageBitmapWidth = _ra.readInt();
      int pageBitmapHeight = _ra.readInt();
      _ra.seek(last);
      Jbig2Page? p = _pages[s.page];
      if (p == null) {
        throw IoException(
            "Referring to width or height of a page we haven't seen yet: ${s.page}");
      }
      p.setPageBitmapWidth(pageBitmapWidth);
      p.setPageBitmapHeight(pageBitmapHeight);
    }
  }

  Jbig2Segment _readHeader() {
    int ptr = _ra.getPosition();
    int segmentNumber = _ra.readInt();
    Jbig2Segment s = Jbig2Segment(segmentNumber);

    int segmentHeaderFlags = _ra.read();
    bool deferredNonRetain = (segmentHeaderFlags & 0x80) == 0x80;
    s.setDeferredNonRetain(deferredNonRetain);
    bool pageAssociationSize = (segmentHeaderFlags & 0x40) == 0x40;
    int segmentType = segmentHeaderFlags & 0x3f;
    s.setType(segmentType);

    int referredToByte0 = _ra.read();
    int countOfReferredToSegments = (referredToByte0 & 0xE0) >> 5;
    List<int>? referredToSegmentNumbers;
    List<bool>? segmentRetentionFlags;

    if (countOfReferredToSegments == 7) {
      _ra.seek(_ra.getPosition() - 1);
      countOfReferredToSegments = _ra.readInt() & 0x1fffffff;
      segmentRetentionFlags = List.filled(countOfReferredToSegments + 1, false);
      int i = 0;
      int referredToCurrentByte = 0;
      do {
        int j = i % 8;
        if (j == 0) {
          referredToCurrentByte = _ra.read();
        }
        // checking bit j
        segmentRetentionFlags[i] =
            (((1 << j) & referredToCurrentByte) >> j) == 1;
        i++;
      } while (i <= countOfReferredToSegments);
    } else {
      if (countOfReferredToSegments <= 4) {
        segmentRetentionFlags =
            List.filled(countOfReferredToSegments + 1, false);
        referredToByte0 &= 0x1f;
        for (int i = 0; i <= countOfReferredToSegments; i++) {
          segmentRetentionFlags[i] = (((1 << i) & referredToByte0) >> i) == 1;
        }
      } else if (countOfReferredToSegments == 5 ||
          countOfReferredToSegments == 6) {
        throw IoException("Count of referred-to segments has forbidden value");
      }
    }
    s.setSegmentRetentionFlags(segmentRetentionFlags ?? []);
    s.setCountOfReferredToSegments(countOfReferredToSegments);

    if (countOfReferredToSegments > 0) {
      referredToSegmentNumbers = List.filled(
          countOfReferredToSegments + 1, 0); // index 1 based in C# loop?
      // C# for (int i = 1; i <= count_of_referred_to_segments; i++)
      // index 0 is unused?
      // Let's use 0-based and adjust size?
      // But code uses size + 1.
      // I'll stick to 0-based List and adjust access?
      // C# code: referred_to_segment_numbers = new int[count_of_referred_to_segments + 1];
      // access referred_to_segment_numbers[i]

      for (int i = 1; i <= countOfReferredToSegments; i++) {
        if (segmentNumber <= 256) {
          referredToSegmentNumbers[i] = _ra.read();
        } else if (segmentNumber <= 65536) {
          referredToSegmentNumbers[i] = _ra.readUnsignedShort();
        } else {
          referredToSegmentNumbers[i] = _ra.readUnsignedInt();
        }
      }
      s.setReferredToSegmentNumbers(referredToSegmentNumbers);
    }

    int segmentPageAssociation;
    int pageAssociationOffset = _ra.getPosition() - ptr;
    if (pageAssociationSize) {
      segmentPageAssociation = _ra.readInt();
    } else {
      segmentPageAssociation = _ra.read();
    }

    if (segmentPageAssociation < 0) {
      throw IoException(
          "Page $segmentPageAssociation is invalid for segment $segmentNumber starting at $ptr");
    }
    s.setPage(segmentPageAssociation);
    s.setPageAssociationSize(pageAssociationSize);
    s.setPageAssociationOffset(pageAssociationOffset);

    if (segmentPageAssociation > 0 &&
        !_pages.containsKey(segmentPageAssociation)) {
      _pages[segmentPageAssociation] = Jbig2Page(segmentPageAssociation, this);
    }
    if (segmentPageAssociation > 0) {
      _pages[segmentPageAssociation]!.addSegment(s);
    } else {
      _globals.add(s);
    }

    int segmentDataLength = _ra.readUnsignedInt();
    s.setDataLength(segmentDataLength); // using int, assuming 32bit fits

    int endPtr = _ra.getPosition();
    _ra.seek(ptr);
    Uint8List headerData = Uint8List(endPtr - ptr);
    _ra.readFully(headerData);
    s.setHeaderData(headerData);

    return s;
  }

  void _readFileHeader() {
    _ra.seek(0);
    Uint8List idstring = Uint8List(8);
    _ra.readFully(idstring);
    Uint8List refidstring =
        Uint8List.fromList([0x97, 0x4A, 0x42, 0x32, 0x0D, 0x0A, 0x1A, 0x0A]);

    for (int i = 0; i < idstring.length; i++) {
      if (idstring[i] != refidstring[i]) {
        throw IoException("File header idstring is not good at byte $i");
      }
    }

    int fileheaderflags = _ra.read();
    _sequential = (fileheaderflags & 0x1) == 0x1;
    _numberOfPagesKnown = (fileheaderflags & 0x2) == 0x0;

    if ((fileheaderflags & 0xfc) != 0x0) {
      throw IoException("File header flags bits from 2 to 7 should be 0");
    }

    if (_numberOfPagesKnown) {
      _ra.readInt();
    }
  }

  int numberOfPages() => _pages.length;

  int getPageHeight(int i) => _pages[i]!.getPageBitmapHeight();
  int getPageWidth(int i) => _pages[i]!.getPageBitmapWidth();

  Jbig2Page? getPage(int page) => _pages[page];

  Uint8List? getGlobal(bool forEmbedding) {
    BytesBuilder os = BytesBuilder();
    try {
      for (var s in _globals) {
        if (forEmbedding && (s.type == endOfFile || s.type == endOfPage)) {
          continue;
        }
        os.add(s.headerData!);
        os.add(s.data!);
      }
      if (os.length > 0) return os.toBytes();
    } catch (e) {
      // Log debug
    }
    return null;
  }

  @override
  String toString() {
    if (_read) {
      return "Jbig2SegmentReader: number of pages: ${numberOfPages()}";
    } else {
      return "Jbig2SegmentReader in indeterminate state.";
    }
  }
}

class Jbig2Segment implements Comparable<Jbig2Segment> {
  final int segmentNumber;
  int dataLength = -1;
  int page = -1;
  List<int>? referredToSegmentNumbers;
  List<bool>? segmentRetentionFlags;
  int type = -1;
  bool deferredNonRetain = false;
  int countOfReferredToSegments = -1;
  Uint8List? data;
  Uint8List? headerData;
  bool pageAssociationSize = false;
  int pageAssociationOffset = -1;

  Jbig2Segment(this.segmentNumber);

  @override
  int compareTo(Jbig2Segment other) {
    return segmentNumber - other.segmentNumber;
  }

  void setDataLength(int len) => dataLength = len;
  void setPage(int p) => page = p;
  void setReferredToSegmentNumbers(List<int> rs) =>
      referredToSegmentNumbers = rs;
  void setSegmentRetentionFlags(List<bool> flags) =>
      segmentRetentionFlags = flags;
  void setType(int t) => type = t;
  void setDeferredNonRetain(bool d) => deferredNonRetain = d;
  void setCountOfReferredToSegments(int c) => countOfReferredToSegments = c;
  void setData(Uint8List d) => data = d;
  void setHeaderData(Uint8List h) => headerData = h;
  void setPageAssociationSize(bool p) => pageAssociationSize = p;
  void setPageAssociationOffset(int o) => pageAssociationOffset = o;
}

class Jbig2Page {
  final int page;
  final Jbig2SegmentReader sr;
  final Map<int, Jbig2Segment> segs = SplayTreeMap();
  int pageBitmapWidth = -1;
  int pageBitmapHeight = -1;

  Jbig2Page(this.page, this.sr);

  void setPageBitmapWidth(int w) => pageBitmapWidth = w;
  void setPageBitmapHeight(int h) => pageBitmapHeight = h;
  int getPageBitmapWidth() => pageBitmapWidth;
  int getPageBitmapHeight() => pageBitmapHeight;

  void addSegment(Jbig2Segment s) {
    segs[s.segmentNumber] = s;
  }

  Uint8List getData(bool forEmbedding) {
    BytesBuilder os = BytesBuilder();
    for (var sn in segs.keys) {
      Jbig2Segment s = segs[sn]!;
      if (forEmbedding &&
          (s.type == Jbig2SegmentReader.endOfFile ||
              s.type == Jbig2SegmentReader.endOfPage)) {
        continue;
      }
      if (forEmbedding) {
        Uint8List headerDataEmb =
            Jbig2SegmentReader.copyByteArray(s.headerData!);
        if (s.pageAssociationSize) {
          headerDataEmb[s.pageAssociationOffset] = 0x0;
          headerDataEmb[s.pageAssociationOffset + 1] = 0x0;
          headerDataEmb[s.pageAssociationOffset + 2] = 0x0;
          headerDataEmb[s.pageAssociationOffset + 3] = 0x1;
        } else {
          headerDataEmb[s.pageAssociationOffset] = 0x1;
        }
        os.add(headerDataEmb);
      } else {
        os.add(s.headerData!);
      }
      os.add(s.data!);
    }
    return os.toBytes();
  }
}
