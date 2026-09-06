import 'standard_roles.dart';
import 'pdf_namespace.dart';

class CraftStandardNamespaces {
  static const String mathMl = "http://www.w3.org/1998/Math/MathML";
  static const String pdf17 = "http://iso.org/pdf/ssn";
  static const String pdf20 = "http://iso.org/pdf2/ssn";

  static final Set<String> _stdStructNamespace17Types = {
    CraftStandardRoles.document,
    CraftStandardRoles.part,
    CraftStandardRoles.div,
    CraftStandardRoles.p,
    CraftStandardRoles.h,
    CraftStandardRoles.h1,
    CraftStandardRoles.h2,
    CraftStandardRoles.h3,
    CraftStandardRoles.h4,
    CraftStandardRoles.h5,
    CraftStandardRoles.h6,
    CraftStandardRoles.lbl,
    CraftStandardRoles.span,
    CraftStandardRoles.link,
    CraftStandardRoles.annot,
    CraftStandardRoles.form,
    CraftStandardRoles.ruby,
    CraftStandardRoles.rb,
    CraftStandardRoles.rt,
    CraftStandardRoles.rp,
    CraftStandardRoles.warichu,
    CraftStandardRoles.wp,
    CraftStandardRoles.l,
    CraftStandardRoles.li,
    CraftStandardRoles.lBody,
    CraftStandardRoles.table,
    CraftStandardRoles.tr,
    CraftStandardRoles.th,
    CraftStandardRoles.td,
    CraftStandardRoles.tHead,
    CraftStandardRoles.tBody,
    CraftStandardRoles.tFoot,
    CraftStandardRoles.caption,
    CraftStandardRoles.figure,
    CraftStandardRoles.formula,
    CraftStandardRoles.sect,
    CraftStandardRoles.art,
    CraftStandardRoles.blockQuote,
    CraftStandardRoles.toc,
    CraftStandardRoles.toci,
    CraftStandardRoles.index,
    CraftStandardRoles.nonStruct,
    CraftStandardRoles.private,
    CraftStandardRoles.quote,
    CraftStandardRoles.note,
    CraftStandardRoles.reference,
    CraftStandardRoles.bibEntry,
    CraftStandardRoles.code
  };

  static final Set<String> _stdStructNamespace20Types = {
    CraftStandardRoles.document,
    CraftStandardRoles.documentFragment,
    CraftStandardRoles.part,
    CraftStandardRoles.sect,
    CraftStandardRoles.nonStruct,
    CraftStandardRoles.div,
    CraftStandardRoles.aside,
    CraftStandardRoles.title,
    CraftStandardRoles.sub,
    CraftStandardRoles.p,
    CraftStandardRoles.h,
    CraftStandardRoles.lbl,
    CraftStandardRoles.em,
    CraftStandardRoles.strong,
    CraftStandardRoles.span,
    CraftStandardRoles.link,
    CraftStandardRoles.annot,
    CraftStandardRoles.form,
    CraftStandardRoles.ruby,
    CraftStandardRoles.rb,
    CraftStandardRoles.rt,
    CraftStandardRoles.rp,
    CraftStandardRoles.warichu,
    CraftStandardRoles.wp,
    CraftStandardRoles.feNote,
    CraftStandardRoles.l,
    CraftStandardRoles.li,
    CraftStandardRoles.lBody,
    CraftStandardRoles.table,
    CraftStandardRoles.tr,
    CraftStandardRoles.th,
    CraftStandardRoles.td,
    CraftStandardRoles.tHead,
    CraftStandardRoles.tBody,
    CraftStandardRoles.tFoot,
    CraftStandardRoles.caption,
    CraftStandardRoles.figure,
    CraftStandardRoles.formula,
    CraftStandardRoles.artifact
  };

  static String getDefault() => pdf17;

  static Future<bool> isKnownDomainSpecificNamespace(
      CraftPdfNamespace namespace) async {
    return mathMl == await namespace.getNamespaceName();
  }

  static bool roleBelongsToStandardNamespace(
      String role, String standardNamespaceName) {
    if (pdf17 == standardNamespaceName) {
      return _stdStructNamespace17Types.contains(role);
    } else if (pdf20 == standardNamespaceName) {
      return _stdStructNamespace20Types.contains(role) || isHnRole(role);
    }
    return false;
  }

  static bool isHnRole(String role) {
    if (role.startsWith("H") && role.length > 1 && role[1] != '0') {
      final sub = role.substring(1);
      final val = int.tryParse(sub);
      return val != null && val > 0;
    }
    return false;
  }
}
