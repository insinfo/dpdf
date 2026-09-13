/// The type of an explicit break requested by an [AreaBreak] element.
enum AreaBreakType {
  /// Moves to the next area of the current page, or to the next page when the
  /// root renderer works with a single area per page.
  NEXT_AREA,

  /// Moves to a brand new page.
  NEXT_PAGE,

  /// Moves to the last page of the document.
  LAST_PAGE,
}
