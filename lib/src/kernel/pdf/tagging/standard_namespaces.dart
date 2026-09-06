import 'standard_roles.dart';
import 'pdf_namespace.dart';

class StandardNamespaces {
  static const String mathMl = "http://www.w3.org/1998/Math/MathML";
  static const String pdf17 = "http://iso.org/pdf/ssn";
  static const String pdf20 = "http://iso.org/pdf2/ssn";

  static final Set<String> _stdStructNamespace17Types = {
    StandardRoles.document, StandardRoles.part, StandardRoles.div, StandardRoles.p,
    StandardRoles.h, StandardRoles.h1, StandardRoles.h2, StandardRoles.h3,
    StandardRoles.h4, StandardRoles.h5, StandardRoles.h6, StandardRoles.lbl,
    StandardRoles.span, StandardRoles.link, StandardRoles.annot, StandardRoles.form,
    StandardRoles.ruby, StandardRoles.rb, StandardRoles.rt, StandardRoles.rp,
    StandardRoles.warichu, StandardRoles.wp, StandardRoles.l,
    StandardRoles.li, StandardRoles.lBody, StandardRoles.table, StandardRoles.tr,
    StandardRoles.th, StandardRoles.td, StandardRoles.tHead, StandardRoles.tBody,
    StandardRoles.tFoot, StandardRoles.caption, StandardRoles.figure,
    StandardRoles.formula, StandardRoles.sect, StandardRoles.art,
    StandardRoles.blockQuote, StandardRoles.toc, StandardRoles.toci,
    StandardRoles.index, StandardRoles.nonStruct, StandardRoles.private,
    StandardRoles.quote, StandardRoles.note, StandardRoles.reference,
    StandardRoles.bibEntry, StandardRoles.code
  };

  static final Set<String> _stdStructNamespace20Types = {
    StandardRoles.document, StandardRoles.documentFragment, StandardRoles.part,
    StandardRoles.sect, StandardRoles.nonStruct, StandardRoles.div,
    StandardRoles.aside, StandardRoles.title, StandardRoles.sub, StandardRoles.p,
    StandardRoles.h, StandardRoles.lbl, StandardRoles.em, StandardRoles.strong,
    StandardRoles.span, StandardRoles.link, StandardRoles.annot, StandardRoles.form,
    StandardRoles.ruby, StandardRoles.rb, StandardRoles.rt, StandardRoles.rp,
    StandardRoles.warichu, StandardRoles.wp, StandardRoles.feNote,
    StandardRoles.l, StandardRoles.li, StandardRoles.lBody, StandardRoles.table,
    StandardRoles.tr, StandardRoles.th, StandardRoles.td, StandardRoles.tHead,
    StandardRoles.tBody, StandardRoles.tFoot, StandardRoles.caption,
    StandardRoles.figure, StandardRoles.formula, StandardRoles.artifact
  };

  static String getDefault() => pdf17;

  static Future<bool> isKnownDomainSpecificNamespace(PdfNamespace namespace) async {
    return mathMl == await namespace.getNamespaceName();
  }

  static bool roleBelongsToStandardNamespace(String role, String standardNamespaceName) {
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
