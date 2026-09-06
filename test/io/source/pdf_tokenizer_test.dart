import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

/// Helper to create tokenizer from string
PdfTokenizer tokenizerFromString(String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return PdfTokenizer(RandomAccessFileOrArray(bytes));
}

void main() {
  group('PdfTokenizer', () {
    group('Basic Tokens', () {
      test('reads null as other token', () async {
        final tokenizer = tokenizerFromString('null');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('null'));
      });

      test('reads true as other token', () async {
        final tokenizer = tokenizerFromString('true');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('true'));
      });

      test('reads false as other token', () async {
        final tokenizer = tokenizerFromString('false');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('false'));
      });

      test('reads integer number', () async {
        final tokenizer = tokenizerFromString('12345');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('12345'));
      });

      test('reads negative integer', () async {
        final tokenizer = tokenizerFromString('-42');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('-42'));
      });

      test('reads float number', () async {
        final tokenizer = tokenizerFromString('3.14159');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('3.14159'));
      });

      test('reads negative float', () async {
        final tokenizer = tokenizerFromString('-0.5');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('-0.5'));
      });
    });

    group('Name Tokens', () {
      test('reads simple name', () async {
        final tokenizer = tokenizerFromString('/Type');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Type'));
      });

      test('reads name with numbers', () async {
        final tokenizer = tokenizerFromString('/Font1');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Font1'));
      });
    });

    group('String Tokens', () {
      test('reads simple literal string', () async {
        final tokenizer = tokenizerFromString('(Hello World)');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });

      test('reads string with nested parentheses', () async {
        final tokenizer = tokenizerFromString('(Hello (nested) World)');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });

      test('reads hex string', () async {
        final tokenizer = tokenizerFromString('<48656C6C6F>');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });

      test('reads empty string', () async {
        final tokenizer = tokenizerFromString('()');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));
      });
    });

    group('Array Tokens', () {
      test('reads array start', () async {
        final tokenizer = tokenizerFromString('[');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startArray));
      });

      test('reads array end', () async {
        final tokenizer = tokenizerFromString(']');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endArray));
      });
    });

    group('Dictionary Tokens', () {
      test('reads dictionary start', () async {
        final tokenizer = tokenizerFromString('<<');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startDic));
      });

      test('reads dictionary end', () async {
        final tokenizer = tokenizerFromString('>>');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endDic));
      });
    });

    group('Comments', () {
      test('skips single line comment', () async {
        final tokenizer = tokenizerFromString('% this is a comment\n42');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('42'));
      });
    });

    group('Whitespace Handling', () {
      test('skips leading whitespace', () async {
        final tokenizer = tokenizerFromString('   42');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('42'));
      });

      test('handles multiple tokens with whitespace', () async {
        final tokenizer = tokenizerFromString('/Type /Page');

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Type'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Page'));
      });
    });

    group('PDF Header', () {
      test('checks valid PDF header', () async {
        final tokenizer = tokenizerFromString('%PDF-1.7\n%more');
        final version = await tokenizer.checkPdfHeader();
        expect(version, contains('1.7'));
      });

      test('checks PDF 2.0 header', () async {
        final tokenizer = tokenizerFromString('%PDF-2.0\n');
        final version = await tokenizer.checkPdfHeader();
        expect(version, contains('2.0'));
      });
    });

    group('Object References', () {
      test('reads obj keyword', () async {
        final tokenizer = tokenizerFromString('1 0 obj');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.obj));
        expect(tokenizer.getObjNr(), equals(1));
        expect(tokenizer.getGenNr(), equals(0));
      });

      test('reads reference', () async {
        final tokenizer = tokenizerFromString('5 0 R');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.ref));
        expect(tokenizer.getObjNr(), equals(5));
        expect(tokenizer.getGenNr(), equals(0));
      });
    });

    group('Stream Keywords', () {
      test('reads stream keyword', () async {
        final tokenizer = tokenizerFromString('stream');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('stream'));
      });

      test('reads endstream keyword', () async {
        final tokenizer = tokenizerFromString('endstream');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.other));
        expect(tokenizer.getStringValue(), equals('endstream'));
      });
    });

    group('Complex Sequences', () {
      test('tokenizes simple dictionary', () async {
        final tokenizer = tokenizerFromString('<< /Type /Page /Count 5 >>');

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startDic));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Type'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Page'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Count'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('5'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endDic));
      });

      test('tokenizes array with mixed types', () async {
        final tokenizer = tokenizerFromString('[ 1 2.5 /Name (String) ]');

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.startArray));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('1'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));
        expect(tokenizer.getStringValue(), equals('2.5'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.name));
        expect(tokenizer.getStringValue(), equals('Name'));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.string));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endArray));
      });
    });

    group('End of File', () {
      test('detects end of file', () async {
        final tokenizer = tokenizerFromString('42');
        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.number));

        await tokenizer.nextValidToken();
        expect(tokenizer.getTokenType(), equals(TokenType.endOfFile));
      });
    });
  });
}
