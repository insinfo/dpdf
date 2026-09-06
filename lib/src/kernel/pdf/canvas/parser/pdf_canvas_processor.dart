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

import 'i_content_operator.dart';
import 'listener/i_event_listener.dart';
import 'standard_operators.dart';

/// Processor for PDF content streams.
class PdfCanvasProcessor {
  final IEventListener _eventListener;
  final Map<String, IContentOperator> _operators = {};

  final List<CanvasGraphicsState> _gsStack = [];
  late CanvasGraphicsState _currentGs;

  Matrix _textMatrix = Matrix();
  Matrix _textLineMatrix = Matrix();

  PdfResources? _resources;

  PdfCanvasProcessor(this._eventListener) {
    _currentGs = CanvasGraphicsState();
    _registerOperators();
  }

  /// Registers a content operator.
  void registerContentOperator(String operatorName, IContentOperator operator) {
    _operators[operatorName] = operator;
  }

  /// Gets the registered content operator.
  IContentOperator? getContentOperator(String operatorName) {
    return _operators[operatorName];
  }

  /// Processes content from a page.
  Future<void> processPageContent(PdfPage page) async {
    _resources = await page.getResources();
    final bytes = await page.getContentBytes();
    await processContent(bytes, _resources);
  }

  /// Processes a content stream.
  Future<void> processContent(
      Uint8List contentBytes, PdfResources? resources) async {
    _resources = resources;
    final tokenizer = PdfTokenizer(RandomAccessFileOrArray(contentBytes));
    final operands = <PdfObject>[];

    try {
      while (await tokenizer.nextToken()) {
        if (tokenizer.getTokenType() == TokenType.other) {
          final operator = tokenizer.getStringValue();
          final op = _operators[operator];
          if (op != null) {
            await op.invoke(this, PdfLiteral(operator), List.from(operands));
          } else {
            // Unknown operator or just unsupported
          }
          operands.clear();
        } else {
          operands.add(await _readObject(tokenizer));
        }
      }
    } finally {
      await tokenizer.close();
    }
  }

  Future<PdfObject> _readObject(PdfTokenizer tokenizer) async {
    final type = tokenizer.getTokenType();
    switch (type) {
      case TokenType.startArray:
        final array = PdfArray();
        while (await tokenizer.nextToken()) {
          if (tokenizer.getTokenType() == TokenType.endArray) {
            break;
          }
          array.add(await _readObject(tokenizer));
        }
        return array;
      case TokenType.startDic:
        final dict = PdfDictionary();
        // Simple dictionary parsing - might need improvements for nested dicts/correct key/value
        // Dictionary in content stream is usually for inline image or marked content
        // This logic is simplified
        while (await tokenizer.nextToken()) {
          if (tokenizer.getTokenType() == TokenType.endDic) {
            break;
          }
          final key = await _readObject(tokenizer);
          if (await tokenizer.nextToken()) {
            final val = await _readObject(tokenizer);
            if (key is PdfName) {
              dict.put(key, val);
            }
          }
        }
        return dict;
      case TokenType.number:
        return PdfNumber.fromString(tokenizer.getStringValue());
      case TokenType.string:
        if (tokenizer.isHexString()) {
          return PdfString.fromBytes(tokenizer.getByteContent())
            ..setHexWriting(true);
        } else {
          return PdfString(tokenizer.getStringValue());
        }
      case TokenType.name:
        return PdfName(tokenizer.getStringValue());
      case TokenType.ref:
        // Indirect reference in content stream? Possible but rare (e.g. XObject)
        // Usually references are just "1 0 R", which tokenizer might split into Number Number Other(R)
        // But PdfTokenizer might recognize Ref if implemented logic allows
        // Here simplified:
        return PdfLiteral(tokenizer.getStringValue());
      default:
        return PdfLiteral(tokenizer.getStringValue());
    }
  }

  IEventListener getEventListener() {
    return _eventListener;
  }

  void _registerOperators() {
    registerContentOperator('BT', BeginText());
    registerContentOperator('ET', EndText());
    registerContentOperator('Tj', ShowText());
    registerContentOperator('q', SaveState());
    registerContentOperator('Q', RestoreState());
  }

  CanvasGraphicsState getGraphicsState() {
    return _currentGs;
  }

  void saveGraphicsState() {
    _gsStack.add(CanvasGraphicsState(_currentGs));
  }

  void restoreGraphicsState() {
    if (_gsStack.isNotEmpty) {
      _currentGs = _gsStack.removeLast();
    }
  }

  Matrix getTextMatrix() => _textMatrix;

  Matrix getTextLineMatrix() => _textLineMatrix;

  void setTextMatrix(Matrix matrix) {
    _textMatrix = matrix;
  }

  void setTextLineMatrix(Matrix matrix) {
    _textLineMatrix = matrix;
  }

  PdfResources? getResources() {
    return _resources;
  }
}
