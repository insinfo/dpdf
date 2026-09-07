import 'dart:typed_data';

import 'package:dpdf/src/io/source/pdf_tokenizer.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/kernel/geom/matrix.dart';
import 'package:dpdf/src/kernel/pdf/canvas/canvas_graphics_state.dart';
import 'package:dpdf/src/kernel/pdf/pdf_literal.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_resources.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

import 'content_operator.dart';
import 'listener/event_listener.dart';
import 'standard_operators.dart';

/// Processor for PDF content streams.
class CraftPdfCanvasProcessor {
  final CraftEventListener _eventListener;
  final Map<String, CraftContentOperator> _operators = {};

  final List<CraftCanvasGraphicsState> _gsStack = [];
  late CraftCanvasGraphicsState _currentGs;

  CraftMatrix _textMatrix = CraftMatrix();
  CraftMatrix _textLineMatrix = CraftMatrix();

  CraftPdfResources? _resources;

  CraftPdfCanvasProcessor(this._eventListener) {
    _currentGs = CraftCanvasGraphicsState();
    _registerOperators();
  }

  /// Registers a content operator.
  void registerContentOperator(
      String operatorName, CraftContentOperator operator) {
    _operators[operatorName] = operator;
  }

  /// Gets the registered content operator.
  CraftContentOperator? getContentOperator(String operatorName) {
    return _operators[operatorName];
  }

  /// Processes content from a page.
  Future<void> processPageContent(CraftPdfPage page) async {
    _resources = await page.resourceDirectory();
    final bytes = await page.contentPayload();
    await processContent(bytes, _resources);
  }

  /// Processes a content stream.
  Future<void> processContent(
      Uint8List contentBytes, CraftPdfResources? resources) async {
    _resources = resources;
    final tokenizer =
        CraftPdfTokenizer(CraftRandomAccessFileOrArray(contentBytes));
    final operands = <CraftPdfObject>[];

    try {
      while (tokenizer.nextToken()) {
        if (tokenizer.getTokenType() == TokenType.other) {
          final operator = tokenizer.getStringValue();
          final op = _operators[operator];
          if (op != null) {
            final pending =
                op.invoke(this, CraftPdfLiteral(operator), List.from(operands));
            if (pending is Future<void>) await pending;
          } else {
            // Unknown operator or just unsupported
          }
          operands.clear();
        } else {
          operands.add(_readObject(tokenizer));
        }
      }
    } finally {
      tokenizer.close();
    }
  }

  CraftPdfObject _readObject(CraftPdfTokenizer tokenizer) {
    final type = tokenizer.getTokenType();
    switch (type) {
      case TokenType.startArray:
        final array = CraftPdfArray();
        while (tokenizer.nextToken()) {
          if (tokenizer.getTokenType() == TokenType.endArray) {
            break;
          }
          array.add(_readObject(tokenizer));
        }
        return array;
      case TokenType.startDic:
        final dict = CraftPdfDictionary();
        // Simple dictionary parsing - might need improvements for nested dicts/correct key/value
        // Dictionary in content stream is usually for inline image or marked content
        // This logic is simplified
        while (tokenizer.nextToken()) {
          if (tokenizer.getTokenType() == TokenType.endDic) {
            break;
          }
          final key = _readObject(tokenizer);
          if (tokenizer.nextToken()) {
            final val = _readObject(tokenizer);
            if (key is CraftPdfName) {
              dict.put(key, val);
            }
          }
        }
        return dict;
      case TokenType.number:
        return CraftPdfNumber.fromString(tokenizer.getStringValue());
      case TokenType.string:
        if (tokenizer.isHexString()) {
          return CraftPdfString.fromBytes(tokenizer.getByteContent())
            ..setHexWriting(true);
        } else {
          return CraftPdfString(tokenizer.getStringValue());
        }
      case TokenType.name:
        return CraftPdfName(tokenizer.getStringValue());
      case TokenType.ref:
        // Indirect reference in content stream? Possible but rare (e.g. XObject)
        // Usually references are just "1 0 R", which tokenizer might split into Number Number Other(R)
        // But PdfTokenizer might recognize Ref if implemented logic allows
        // Here simplified:
        return CraftPdfLiteral(tokenizer.getStringValue());
      default:
        return CraftPdfLiteral(tokenizer.getStringValue());
    }
  }

  CraftEventListener getEventListener() {
    return _eventListener;
  }

  void _registerOperators() {
    registerContentOperator('BT', BeginText());
    registerContentOperator('ET', EndText());
    registerContentOperator('Tj', ShowText());
    registerContentOperator('q', SaveState());
    registerContentOperator('Q', RestoreState());
  }

  CraftCanvasGraphicsState getGraphicsState() {
    return _currentGs;
  }

  void saveGraphicsState() {
    _gsStack.add(CraftCanvasGraphicsState(_currentGs));
  }

  void restoreGraphicsState() {
    if (_gsStack.isNotEmpty) {
      _currentGs = _gsStack.removeLast();
    }
  }

  CraftMatrix getTextMatrix() => _textMatrix;

  CraftMatrix getTextLineMatrix() => _textLineMatrix;

  void setTextMatrix(CraftMatrix matrix) {
    _textMatrix = matrix;
  }

  void setTextLineMatrix(CraftMatrix matrix) {
    _textLineMatrix = matrix;
  }

  CraftPdfResources? resourceDirectory() {
    return _resources;
  }
}
