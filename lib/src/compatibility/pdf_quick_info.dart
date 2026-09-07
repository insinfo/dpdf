import 'dart:convert';
import 'dart:typed_data';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';

/// Header and document declarations, without signature or trust validation.
class PdfQuickInfo {
  final int? versionMajor, versionMinor, versionOffset;
  final String? versionRawHeader;
  final int? pageCount, docMdpPermissionP;
  final bool? isEncrypted;
  final bool hasDocMdp;
  const PdfQuickInfo._(
      this.versionMajor,
      this.versionMinor,
      this.versionOffset,
      this.versionRawHeader,
      this.pageCount,
      this.isEncrypted,
      this.hasDocMdp,
      this.docMdpPermissionP);

  String? get versionString =>
      versionMajor == null ? null : '$versionMajor.$versionMinor';
  bool get isPdf15OrAbove =>
      versionMajor != null &&
      (versionMajor! > 1 || (versionMajor == 1 && versionMinor! >= 5));

  /// [readDocument] false reads only the first 1024 header bytes, including
  /// incomplete inputs. Full inspection propagates parser/password errors.
  /// DocMDP is the catalog's declared certification transform, not proof
  /// that the signature is valid or that later revisions respect it.
  static Future<PdfQuickInfo> fromBytes(Uint8List bytes,
      {bool readDocument = true, bool readMDPInfo = true}) async {
    final prefix = latin1
        .decode(bytes.sublist(0, bytes.length < 1024 ? bytes.length : 1024));
    final header =
        RegExp(r'%PDF-([0-9]+)\.([0-9]+)(?=[\r\n\t ]|$)').firstMatch(prefix);
    final major = header == null ? null : int.parse(header.group(1)!);
    final minor = header == null ? null : int.parse(header.group(2)!);
    if (!readDocument) {
      return PdfQuickInfo._(major, minor, header?.start, header?.group(0), null,
          null, false, null);
    }
    final reader = CraftPdfReader.fromBytes(bytes);
    final doc = await CraftPdfDocument.open(reader);
    try {
      var declared = false;
      int? permission;
      if (readMDPInfo) {
        final permissions = await doc
            .rootCatalog()
            .pdfRepresentation()
            .dictionaryEntry(CraftPdfName('Perms'));
        final signature =
            await permissions?.dictionaryEntry(CraftPdfName('DocMDP'));
        declared = signature != null;
        final references =
            await signature?.arrayEntry(CraftPdfName('Reference'));
        if (references != null) {
          for (var index = 0; index < references.size(); index++) {
            final entry = await references.get(index);
            if (entry is! CraftPdfDictionary) continue;
            if ((await entry.nameEntry(CraftPdfName('TransformMethod')))
                    ?.getValue() !=
                'DocMDP') {
              continue;
            }
            final parameters =
                await entry.dictionaryEntry(CraftPdfName('TransformParams'));
            final value = await parameters?.numberEntry(CraftPdfName('P'));
            if (value != null &&
                value.doubleValue() == value.intValue() &&
                value.intValue() >= 1 &&
                value.intValue() <= 3) {
              permission = value.intValue();
            }
          }
        }
      }
      return PdfQuickInfo._(major, minor, header?.start, header?.group(0),
          doc.pageTotal(), reader.encrypted, declared, permission);
    } finally {
      await doc.close();
    }
  }
}
