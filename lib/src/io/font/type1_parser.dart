import '../../platform/io.dart';
import 'dart:typed_data';
import '../resources/embedded_font_resources.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';

class Type1Parser {
  static const String AFM_HEADER = "StartFontMetrics";

  String? afmPath;
  String? pfbPath;
  Uint8List? pfbData;
  Uint8List? afmData;
  bool isBuiltInFontValue = false;

  Type1Parser(this.afmPath, this.pfbPath, this.afmData, this.pfbData);

  RandomAccessFileOrArray getMetricsFile() {
    isBuiltInFontValue = false;
    if (afmPath != null && StandardFonts.isStandardFont(afmPath!)) {
      isBuiltInFontValue = true;
      final bytes = EmbeddedFontResources.metrics(afmPath!) ?? afmData;
      if (bytes == null) {
        throw StateError('No embedded AFM metrics available for $afmPath');
      }
      return RandomAccessFileOrArray(bytes);
    }

    if (afmPath != null) {
      if (afmPath!.toLowerCase().endsWith(".afm")) {
        return RandomAccessFileOrArray.fromFile(File(afmPath!));
      }
      // PFM support is not implemented.
    }

    if (afmData != null) {
      return RandomAccessFileOrArray(afmData!);
    }

    throw Exception("Invalid afm font file.");
  }

  RandomAccessFileOrArray getPostscriptBinary() {
    if (pfbData != null) {
      return RandomAccessFileOrArray(pfbData!);
    }
    if (pfbPath != null && pfbPath!.toLowerCase().endsWith(".pfb")) {
      return RandomAccessFileOrArray.fromFile(File(pfbPath!));
    } else if (afmPath != null) {
      String pfb = "${afmPath!.substring(0, afmPath!.length - 3)}pfb";
      File f = File(pfb);
      if (f.existsSync()) {
        return RandomAccessFileOrArray.fromFile(f);
      }
    }
    throw Exception("PFB file not found");
  }

  bool isBuiltInFont() => isBuiltInFontValue;

  String? getAfmPath() => afmPath;
}
