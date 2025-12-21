import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:itext/itext.dart';

/// Helper to create tokenizer from string
PdfTokenizer tokenizerFromString(String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final source = ArrayRandomAccessSource(bytes);
  return PdfTokenizer(RandomAccessFileOrArray(source));
}

void main() {
  group('PdfTokenizer', () {
    group('Basic Tokens', () {
      test('reads null as other token', () {
        final tokenizer = tokenizerFromString('null');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('null'));
      });

      test('reads true as other token', () {
        final tokenizer = tokenizerFromString('true');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('true'));
      });

      test('reads false as other token', () {
        final tokenizer = tokenizerFromString('false');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('false'));
      });

      test('reads integer number', () {
        final tokenizer = tokenizerFromString('12345');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('12345'));
      });

      test('reads negative integer', () {
        final tokenizer = tokenizerFromString('-42');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('-42'));
      });

      test('reads float number', () {
        final tokenizer = tokenizerFromString('3.14159');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('3.14159'));
      });

      test('reads negative float', () {
        final tokenizer = tokenizerFromString('-0.5');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('-0.5'));
      });
    });

    group('Name Tokens', () {
      test('reads simple name', () {
        final tokenizer = tokenizerFromString('/Type');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Type'));
      });

      test('reads name with numbers', () {
        final tokenizer = tokenizerFromString('/Font1');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Font1'));
      });
    });

    group('String Tokens', () {
      test('reads simple literal string', () {
        final tokenizer = tokenizerFromString('(Hello World)');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });

      test('reads string with nested parentheses', () {
        final tokenizer = tokenizerFromString('(Hello (nested) World)');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });

      test('reads hex string', () {
        final tokenizer = tokenizerFromString('<48656C6C6F>');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });

      test('reads empty string', () {
        final tokenizer = tokenizerFromString('()');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });
    });

    group('Array Tokens', () {
      test('reads array start', () {
        final tokenizer = tokenizerFromString('[');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startArray));
      });

      test('reads array end', () {
        final tokenizer = tokenizerFromString(']');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endArray));
      });
    });

    group('Dictionary Tokens', () {
      test('reads dictionary start', () {
        final tokenizer = tokenizerFromString('<<');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startDic));
      });

      test('reads dictionary end', () {
        final tokenizer = tokenizerFromString('>>');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endDic));
      });
    });

    group('Comments', () {
      test('skips single line comment', () {
        final tokenizer = tokenizerFromString('% this is a comment\n42');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('42'));
      });
    });

    group('Whitespace Handling', () {
      test('skips leading whitespace', () {
        final tokenizer = tokenizerFromString('   42');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('42'));
      });

      test('handles multiple tokens with whitespace', () {
        final tokenizer = tokenizerFromString('/Type /Page');

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Type'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Page'));
      });
    });

    group('PDF Header', () {
      test('checks valid PDF header', () {
        final tokenizer = tokenizerFromString('%PDF-1.7\n%more');
        final version = tokenizer.checkPdfHeader();
        expect(version, contains('1.7'));
      });

      test('checks PDF 2.0 header', () {
        final tokenizer = tokenizerFromString('%PDF-2.0\n');
        final version = tokenizer.checkPdfHeader();
        expect(version, contains('2.0'));
      });
    });

    group('Object References', () {
      test('reads obj keyword', () {
        final tokenizer = tokenizerFromString('1 0 obj');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.obj));
        expect(tokenizer.getObjNr(), equals(1));
        expect(tokenizer.getGenNr(), equals(0));
      });

      test('reads reference', () {
        final tokenizer = tokenizerFromString('5 0 R');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.ref));
        expect(tokenizer.getObjNr(), equals(5));
        expect(tokenizer.getGenNr(), equals(0));
      });
    });

    group('Stream Keywords', () {
      test('reads stream keyword', () {
        final tokenizer = tokenizerFromString('stream');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('stream'));
      });

      test('reads endstream keyword', () {
        final tokenizer = tokenizerFromString('endstream');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('endstream'));
      });
    });

    group('Complex Sequences', () {
      test('tokenizes simple dictionary', () {
        final tokenizer = tokenizerFromString('<< /Type /Page /Count 5 >>');

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startDic));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Type'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Page'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Count'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('5'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endDic));
      });

      test('tokenizes array with mixed types', () {
        final tokenizer = tokenizerFromString('[ 1 2.5 /Name (String) ]');

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startArray));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('1'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('2.5'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Name'));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endArray));
      });
    });

    group('End of File', () {
      test('detects end of file', () {
        final tokenizer = tokenizerFromString('42');
        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));

        tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endOfFile));
      });
    });
  });
}
