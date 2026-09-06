import 'dart:typed_data';
import 'cmap/cmap_cid_to_codepoint.dart';
import 'cmap/cmap_codepoint_to_cid.dart';
import 'cmap/cmap_uni_cid.dart';
import 'cmap/cmap_parser.dart';
import 'cmap/cmap_location_from_bytes.dart';
import 'cjk_resource_loader.dart';

class CMapEncoding {
  static final List<Uint8List> _identityHVCodeSpaceRanges = [
    Uint8List.fromList([0, 0]),
    Uint8List.fromList([255, 255])
  ];

  final String cmap;
  String? uniMap;
  bool _isDirect = false;

  late CMapCidToCodepoint _cid2Code;
  late CMapCodepointToCid _code2Cid;
  List<Uint8List> codeSpaceRanges = _identityHVCodeSpaceRanges;

  CMapEncoding(this.cmap) {
    if (cmap == "Identity-H" || cmap == "Identity-V") {
      _isDirect = true;
      codeSpaceRanges = _identityHVCodeSpaceRanges;
    } else {
      _isDirect = false;
      _cid2Code = CjkResourceLoader.getCidToCodepointCmapSync(cmap);
      _code2Cid = getCodeToCidCmapSync(cmap, _cid2Code);
      codeSpaceRanges = _cid2Code.getCodeSpaceRanges();
    }
  }

  CMapEncoding.withUniMap(this.cmap, this.uniMap) {
    if (cmap == "Identity-H" || cmap == "Identity-V") {
      _isDirect = true;
      codeSpaceRanges = _identityHVCodeSpaceRanges;
    } else {
      _isDirect = false;
      _cid2Code = CjkResourceLoader.getCidToCodepointCmapSync(cmap);
      if (uniMap != null) {
        _code2Cid = CjkResourceLoader.getCodepointToCidCmapSync(uniMap!);
      } else {
        _code2Cid = getCodeToCidCmapSync(cmap, _cid2Code);
      }
      codeSpaceRanges = _cid2Code.getCodeSpaceRanges();
    }
  }

  CMapEncoding.fromBytes(this.cmap, Uint8List cmapBytes) {
    _cid2Code = CMapCidToCodepoint();
    _isDirect = false;
    CMapParser.parseCidSync(cmap, _cid2Code, CMapLocationFromBytes(cmapBytes));
    _code2Cid = CMapCodepointToCid.fromReverseMap(_cid2Code);
    codeSpaceRanges = _cid2Code.getCodeSpaceRanges();
  }

  static CMapCodepointToCid getCodeToCidCmapSync(
      String cmap, CMapCidToCodepoint cid2Code) {
    // If it's a known CJK CMap, we might have a predefined UniMap for it.
    //  tries to load a predefined map first.
    CMapUniCid cp2cid = CjkResourceLoader.getUni2CidCmapSync(cmap);
    if (cp2cid.map.isEmpty()) {
      // If not found, fall back to reversing
      return CMapCodepointToCid.fromReverseMap(cid2Code);
    }
    // Need to convert CMapUniCid to CMapCodepointToCid or just use map.
    CMapCodepointToCid res = CMapCodepointToCid();
    res.map.clear();
    res.map = cp2cid.map.clone();
    return res;
  }

  bool isDirect() => _isDirect;

  String getCmapName() => cmap;

  Uint8List getCmapBytes(int cid) {
    if (_isDirect) {
      return Uint8List.fromList([(cid >> 8) & 0xFF, cid & 0xFF]);
    } else {
      return _cid2Code.lookup(cid);
    }
  }

  int getCmapBytesLength(int cid) {
    if (_isDirect) return 2;
    return _cid2Code.lookup(cid).length;
  }

  int getCidCode(int cmapCode) {
    if (_isDirect) return cmapCode;
    return _code2Cid.lookup(cmapCode);
  }

  int getCidCodeFromBytes(Uint8List bytes, int offset) {
    int length = getCidCodeLengthFromBytes(bytes, offset);
    int code = 0;
    for (int i = 0; i < length; i++) {
      code <<= 8;
      code |= bytes[offset + i] & 0xFF;
    }
    return getCidCode(code);
  }

  int getCidCodeLengthFromBytes(Uint8List bytes, int offset) {
    if (_isDirect) return 2;
    for (int i = 0; i < codeSpaceRanges.length; i += 2) {
      Uint8List low = codeSpaceRanges[i];
      Uint8List high = codeSpaceRanges[i + 1];
      int len = low.length;
      if (offset + len > bytes.length) continue;

      bool match = true;
      for (int k = 0; k < len; k++) {
        int b = bytes[offset + k] & 0xFF;
        if (b < (low[k] & 0xFF) || b > (high[k] & 0xFF)) {
          match = false;
          break;
        }
      }
      if (match) return len;
    }
    return 1;
  }

  List<Uint8List> getCodeSpaceRanges() => codeSpaceRanges;

  String getRegistry() =>
      _isDirect ? "Adobe" : _cid2Code.getRegistry() ?? "Adobe";
  String getOrdering() =>
      _isDirect ? "Identity" : _cid2Code.getOrdering() ?? "Unknown";
  int getSupplement() => _isDirect ? 0 : _cid2Code.getSupplement();
}
