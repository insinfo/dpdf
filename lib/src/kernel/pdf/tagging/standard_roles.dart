/// Standard structure element roles as defined by PDF specification.
/// These roles are used for accessibility tagging in PDF documents.
class StandardRoles {
  StandardRoles._();

  static const String annot = 'Annot';
  static const String art = 'Art';
  static const String artifact = 'Artifact';
  static const String aside = 'Aside';
  static const String bibEntry = 'BibEntry';
  static const String blockQuote = 'BlockQuote';
  static const String caption = 'Caption';
  static const String code = 'Code';
  static const String div = 'Div';
  static const String document = 'Document';
  static const String documentFragment = 'DocumentFragment';
  static const String em = 'Em';
  static const String feNote = 'FENote';
  static const String figure = 'Figure';
  static const String form = 'Form';
  static const String formula = 'Formula';
  static const String h = 'H';
  static const String h1 = 'H1';
  static const String h2 = 'H2';
  static const String h3 = 'H3';
  static const String h4 = 'H4';
  static const String h5 = 'H5';
  static const String h6 = 'H6';
  static const String index = 'Index';
  static const String l = 'L';
  static const String lbl = 'Lbl';
  static const String lBody = 'LBody';
  static const String li = 'LI';
  static const String link = 'Link';
  static const String nonStruct = 'NonStruct';
  static const String note = 'Note';
  static const String p = 'P';
  static const String part = 'Part';
  static const String private = 'Private';
  static const String quote = 'Quote';
  static const String rb = 'RB';
  static const String reference = 'Reference';
  static const String rp = 'RP';
  static const String rt = 'RT';
  static const String ruby = 'Ruby';
  static const String sect = 'Sect';
  static const String span = 'Span';
  static const String strong = 'Strong';
  static const String sub = 'Sub';
  static const String table = 'Table';
  static const String tBody = 'TBody';
  static const String td = 'TD';
  static const String tFoot = 'TFoot';
  static const String th = 'TH';
  static const String tHead = 'THead';
  static const String title = 'Title';
  static const String toc = 'TOC';
  static const String toci = 'TOCI';
  static const String tr = 'TR';
  static const String warichu = 'Warichu';
  static const String wp = 'WP';
  static const String wt = 'WT';

  // ----------------------------------------------- standard type categories

  /// Grouping elements (ISO 32000-1:2008, 14.8.4.2, Table 333). They group
  /// other structure elements and are never associated with content items.
  static const Set<String> groupingTypes = {
    document,
    part,
    art,
    sect,
    div,
    blockQuote,
    caption,
    toc,
    toci,
    index,
    nonStruct,
    private,
  };

  /// Block-level structure elements (14.8.4.3, Tables 334 to 337): the
  /// paragraphlike, list and table types.
  static const Set<String> blockLevelTypes = {
    p,
    h,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    l,
    li,
    lbl,
    lBody,
    table,
    tr,
    th,
    td,
    tHead,
    tBody,
    tFoot,
  };

  /// The list types of Table 336.
  static const Set<String> listTypes = {l, li, lbl, lBody};

  /// The table types of Table 337.
  static const Set<String> tableTypes = {
    table,
    tr,
    th,
    td,
    tHead,
    tBody,
    tFoot,
  };

  /// Inline-level structure elements (14.8.4.4, Table 338) together with the
  /// ruby and warichu types of Table 339.
  static const Set<String> inlineLevelTypes = {
    span,
    quote,
    note,
    reference,
    bibEntry,
    code,
    link,
    annot,
    ruby,
    rb,
    rt,
    rp,
    warichu,
    wt,
    wp,
  };

  /// Illustration elements (14.8.4.5, Table 340), the types that stand in for
  /// content a reader cannot read and therefore need /Alt or /ActualText.
  static const Set<String> illustrationTypes = {figure, formula, form};

  /// Every structure type ISO 32000-1 standardizes.
  static Set<String> get standardTypes => {
        ...groupingTypes,
        ...blockLevelTypes,
        ...inlineLevelTypes,
        ...illustrationTypes,
      };

  /// Whether [role] is one of the standard structure types of 14.8.4.
  static bool isStandardType(String role) => standardTypes.contains(role);

  /// Whether [role] is a heading: H, or Hn for a positive n (14.8.4.3.2 and,
  /// for arbitrary n, the PDF 2.0 namespace).
  static bool isHeading(String role) {
    if (role == h) return true;
    if (!role.startsWith('H') || role.length < 2) return false;
    final level = int.tryParse(role.substring(1));
    return level != null && level > 0 && !role.startsWith('H0');
  }
}
