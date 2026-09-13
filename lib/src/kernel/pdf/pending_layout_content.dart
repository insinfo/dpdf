/// A layout root that holds content which has not reached the page yet.
///
/// `Document` and `Canvas` queue what [add] receives and only lay it out when
/// they are closed. A [PdfDocument] refuses to close while such a queue is not
/// empty, so forgetting to close the layout root fails loudly instead of
/// producing a document that is silently missing its content.
abstract class PendingLayoutContent {
  /// How many elements are still waiting to be laid out and drawn.
  int pendingContentCount();

  /// Name used to identify this root in the error a [PdfDocument] raises.
  String pendingContentOwner();
}
