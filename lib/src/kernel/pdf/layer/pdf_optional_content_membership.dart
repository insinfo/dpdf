import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_group.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_name.dart';

/// A node of a visibility expression, ISO 32000-1, clause 8.11.2.2 (`/VE`).
///
/// An expression is an array whose first element is `/And`, `/Or` or `/Not`
/// and whose remaining elements are optional content groups or nested
/// expressions. Evaluating it equates the ON state of a group with true.
abstract class PdfVisibilityExpression {
  /// Nesting depth accepted while parsing.
  ///
  /// A malformed or hostile file can point an expression at itself through
  /// indirect references; a hard limit keeps parsing from recursing forever.
  static const int maxDepth = 32;

  const PdfVisibilityExpression();

  /// Evaluates the expression, asking [isGroupOn] for the state of each group.
  bool evaluate(bool Function(PdfDictionary group) isGroupOn);

  /// Rebuilds the PDF object form of this expression.
  PdfObject toPdfObject();

  /// Appends every group this expression reads to [into].
  void collectGroups(List<PdfDictionary> into);

  /// Parses `/VE`-style [object]; returns null when it is not an expression.
  static Future<PdfVisibilityExpression?> parse(PdfObject? object,
      [int depth = 0]) async {
    if (depth > maxDepth) return null;

    var resolved = object;
    if (resolved is PdfIndirectReference) {
      resolved = await resolved.targetObject(true);
    }

    // A bare group standing where an operand is expected is a leaf.
    if (resolved is PdfDictionary) {
      final group = await PdfOptionalContentGroup.parse(resolved);
      if (group == null) return null;
      return PdfVisibilityGroup(group.pdfRepresentation());
    }

    if (resolved is! PdfArray || resolved.size() < 1) return null;
    final operator = await resolved.nameEntry(0);
    if (operator == null) return null;

    final isNot = operator == PdfOcName.not;
    if (!isNot && operator != PdfOcName.and && operator != PdfOcName.or) {
      return null;
    }
    // `/Not` takes exactly one operand, `/And` and `/Or` one or more.
    if (isNot && resolved.size() != 2) return null;
    if (!isNot && resolved.size() < 2) return null;

    final operands = <PdfVisibilityExpression>[];
    for (var i = 1; i < resolved.size(); i++) {
      final operand = await parse(await resolved.get(i, false), depth + 1);
      if (operand == null) return null;
      operands.add(operand);
    }
    return PdfVisibilityOperation(operator, operands);
  }
}

/// A leaf of a visibility expression: one optional content group.
class PdfVisibilityGroup extends PdfVisibilityExpression {
  final PdfDictionary group;

  const PdfVisibilityGroup(this.group);

  @override
  bool evaluate(bool Function(PdfDictionary group) isGroupOn) =>
      isGroupOn(group);

  @override
  PdfObject toPdfObject() => group;

  @override
  void collectGroups(List<PdfDictionary> into) => into.add(group);
}

/// An `/And`, `/Or` or `/Not` node of a visibility expression.
class PdfVisibilityOperation extends PdfVisibilityExpression {
  final PdfName operator;

  final List<PdfVisibilityExpression> operands;

  const PdfVisibilityOperation(this.operator, this.operands);

  /// `[/And ...]` over [operands].
  factory PdfVisibilityOperation.and(List<PdfVisibilityExpression> operands) =>
      PdfVisibilityOperation(PdfOcName.and, operands);

  /// `[/Or ...]` over [operands].
  factory PdfVisibilityOperation.or(List<PdfVisibilityExpression> operands) =>
      PdfVisibilityOperation(PdfOcName.or, operands);

  /// `[/Not operand]`.
  factory PdfVisibilityOperation.not(PdfVisibilityExpression operand) =>
      PdfVisibilityOperation(PdfOcName.not, <PdfVisibilityExpression>[operand]);

  @override
  bool evaluate(bool Function(PdfDictionary group) isGroupOn) {
    if (operator == PdfOcName.not) {
      return operands.isEmpty || !operands.first.evaluate(isGroupOn);
    }
    if (operator == PdfOcName.and) {
      return operands.every((operand) => operand.evaluate(isGroupOn));
    }
    return operands.any((operand) => operand.evaluate(isGroupOn));
  }

  @override
  PdfObject toPdfObject() {
    final array = PdfArray()..add(operator);
    for (final operand in operands) {
      array.add(operand.toPdfObject());
    }
    return array;
  }

  @override
  void collectGroups(List<PdfDictionary> into) {
    for (final operand in operands) {
      operand.collectGroups(into);
    }
  }
}

/// An optional content membership dictionary, ISO 32000-1, clause 8.11.2.2
/// (table 99).
///
/// It expresses a visibility policy over several groups, either with the
/// simple `/P` policy or with the more general `/VE` expression of PDF 1.6.
class PdfOptionalContentMembership extends PdfObjectWrapper<PdfDictionary> {
  /// The `/P` values of table 99.
  static final Set<PdfName> policies = Set<PdfName>.unmodifiable(<PdfName>{
    PdfOcName.allOn,
    PdfOcName.anyOn,
    PdfOcName.anyOff,
    PdfOcName.allOff,
  });

  /// Creates `<< /Type /OCMD /OCGs [...] /P policy >>`.
  PdfOptionalContentMembership(List<PdfOptionalContentGroup> groups,
      {PdfName? policy})
      : super(PdfDictionary()) {
    pdfRepresentation().put(PdfOcName.type, PdfOcName.ocmd);
    setGroups(groups);
    if (policy != null) setPolicy(policy);
  }

  /// Wraps an existing membership dictionary without validating it.
  PdfOptionalContentMembership.fromDictionary(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;

  /// Reads a membership dictionary from [object], which may be a reference.
  ///
  /// Returns null when `/Type` is not `/OCMD`.
  static Future<PdfOptionalContentMembership?> parse(PdfObject? object) async {
    final dict = await PdfOptionalContentGroup.resolveDictionary(object);
    if (dict == null) return null;
    final type = await dict.nameEntry(PdfOcName.type);
    if (type != PdfOcName.ocmd) return null;
    return PdfOptionalContentMembership.fromDictionary(dict);
  }

  /// The groups named by `/OCGs`, as dictionaries.
  ///
  /// Table 99 allows a single dictionary or an array, and requires null
  /// entries and references to deleted objects to be ignored, so anything
  /// that does not resolve to an `/OCG` dictionary is dropped here.
  Future<List<PdfDictionary>> getGroups() async {
    final direct = await pdfRepresentation().get(PdfOcName.ocgs, true);
    final groups = <PdfDictionary>[];
    if (direct is PdfDictionary) {
      final group = await PdfOptionalContentGroup.parse(direct);
      if (group != null) groups.add(group.pdfRepresentation());
    } else if (direct is PdfArray) {
      for (var i = 0; i < direct.size(); i++) {
        final group = await PdfOptionalContentGroup.parse(await direct.get(i));
        if (group != null) groups.add(group.pdfRepresentation());
      }
    }
    return groups;
  }

  void setGroups(List<PdfOptionalContentGroup> groups) {
    pdfRepresentation().put(
        PdfOcName.ocgs,
        PdfArray.fromList(groups
            .map<PdfObject>((group) => group.pdfRepresentation())
            .toList(growable: false)));
  }

  /// The `/P` visibility policy; defaults to `/AnyOn` (table 99).
  Future<PdfName> getPolicy() async {
    final policy = await pdfRepresentation().nameEntry(PdfOcName.p);
    if (policy == null || !policies.contains(policy)) return PdfOcName.anyOn;
    return policy;
  }

  void setPolicy(PdfName policy) {
    pdfRepresentation().put(PdfOcName.p, policy);
  }

  /// The `/VE` visibility expression, or null when there is none.
  Future<PdfVisibilityExpression?> getVisibilityExpression() async {
    return PdfVisibilityExpression.parse(
        await pdfRepresentation().get(PdfOcName.ve, false));
  }

  void setVisibilityExpression(PdfVisibilityExpression expression) {
    pdfRepresentation().put(PdfOcName.ve, expression.toPdfObject());
  }

  /// Applies a `/P` policy to the states of [groups].
  ///
  /// An empty group list means the dictionary has no effect on visibility
  /// (table 99), which this reports as visible.
  static bool applyPolicy(PdfName policy, List<bool> groups) {
    if (groups.isEmpty) return true;
    if (policy == PdfOcName.allOn) return groups.every((state) => state);
    if (policy == PdfOcName.anyOff) return groups.any((state) => !state);
    if (policy == PdfOcName.allOff) return groups.every((state) => !state);
    return groups.any((state) => state);
  }
}
