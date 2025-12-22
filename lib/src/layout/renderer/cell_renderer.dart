import 'package:dpdf/src/layout/renderer/block_renderer.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';

class CellRenderer extends BlockRenderer {
  CellRenderer(Cell modelElement) : super(modelElement);

  // Cell specific layout logic if needed, e.g. vertical alignment.
  // For now, standard Block layout is sufficient for content INSIDE the cell.

  // However, the TableRenderer will likely FORCE the size of the CellRenderer
  // rather than the CellRenderer deciding its own size freely in a vacuum.
  // The layout() method will be called with a constrained area defined by the Table.

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    // Use block layout
    LayoutResult? result = super.layout(layoutContext);

    // If result is full, we might need to ensure the occupied area matches the Cell's expected height?
    // Or TableRenderer handles that.
    return result;
  }
}
