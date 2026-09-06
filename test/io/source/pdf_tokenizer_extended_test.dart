import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

/// Helper to create tokenizer from string
PdfTokenizer tokenizerFromString(String content) {
  final bytes = Uint8List.fromList(latin1.encode(content));
  return PdfTokenizer(RandomAccessFileOrArray(bytes));
}

void main() {
  group('PdfTokenizer Extended', () {
    group('Seek and Position', () {
      test('seekTest', () async {
        final data = '/Name1 70';
        final expectedTypes = [
          TokenType.name,
          TokenType.number,
          TokenType.endOfFile
        ];

        final tok = tokenizerFromString(data);

        tok.seek(0); // seek is sync, does not return Future
        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(expectedTypes[0]));
        expect(tok.getStringValue(), equals('Name1'));

        tok.seek(7);
        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(expectedTypes[1]));
        expect(tok.getStringValue(), equals('70'));

        tok.seek(8);
        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(expectedTypes[1]));
        expect(tok.getStringValue(), equals('0'));

        tok.seek(9);
        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(expectedTypes[2]));
      });

      test('peekTest', () async {
        final data = '/Name1 70';
        final tokenizer = tokenizerFromString(data);

        tokenizer.seek(0);
        var symbol = await tokenizer.peek();
        expect(symbol, equals('/'.codeUnitAt(0)));
        expect(tokenizer.getPosition(), equals(0)); // getPosition is sync

        tokenizer.seek(7);
        symbol = await tokenizer.peek();
        expect(symbol, equals('7'.codeUnitAt(0)));
        expect(tokenizer.getPosition(), equals(7));

        tokenizer.seek(9);
        symbol = await tokenizer.peek();
        expect(symbol, equals(-1));
        expect(tokenizer.getPosition(), equals(9));
      });

      test('getPositionTest', () async {
        final data = '/Name1 70';
        final tok = tokenizerFromString(data);

        expect(tok.getPosition(), equals(0));
        await tok.nextValidToken();
        expect(tok.getPosition(), equals(6)); // After "/Name1"
        await tok.nextValidToken();
        expect(tok.getPosition(), equals(9)); // After "/Name1 70"
      });
    });

    group('Value Parsing', () {
      test('getLongValueTest', () async {
        final data = '21474836470';
        final tok = tokenizerFromString(data);
        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getLongValue(), equals(21474836470));
      });

      test('getIntValueTest', () async {
        final data = '15';
        final tok = tokenizerFromString(data);
        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getIntValue(), equals(15));
      });
    });

    group('Length and Read', () {
      test('lengthTest', () async {
        final data = '/Name1';
        final tok = tokenizerFromString(data);
        expect(await tok.length(), equals(6));
      });

      test('lengthTwoTokenTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        expect(await tok.length(), equals(9));
      });

      test('readTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        final read = Uint8List(7);
        for (var i = 0; i < 7; i++) {
          read[i] = await tok.read();
        }
        expect(String.fromCharCodes(read), equals('/Name1 '));
      });

      test('readStringFullTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        expect(await tok.readString(data.length), equals(data));
      });

      test('readStringShortTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        expect(await tok.readString(5), equals('/Name'));
      });

      test('readStringLongerThenDataTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        expect(await tok.readString(data.length + 10), equals(data));
      });

      test('readFullyPartThenReadStringTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        await tok.readFully(Uint8List(6));
        expect(await tok.readString(data.length), equals(' 15'));
      });

      test('readFullyThenReadStringTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);
        await tok.readFully(Uint8List(7));
        expect(await tok.readString(data.length), equals('15'));
      });
    });

    group('EOF Parsing', () {
      test('getNextEofShortTextTest', () async {
        final data = 'some text to test \ngetting end of\n file logic%%EOF';
        final tok = tokenizerFromString(data);
        final eofPosition = await tok.getNextEof();
        expect(eofPosition, equals(data.length));
      });

      test('getNextEofLongTextTest', () async {
        final dataChunk = 'some text to test \ngetting end of\n file logic';
        final buffer = StringBuffer();
        for (var i = 0; i < 20; i++) {
          buffer.write(dataChunk);
        }
        buffer.write('%%EOF');
        final data = buffer.toString();

        final tok = tokenizerFromString(data);
        final eofPosition = await tok.getNextEof();
        expect(eofPosition, equals(dataChunk.length * 20 + 5));
      });

      test('getNextEofWhichIsCutTest', () async {
        final buffer = StringBuffer();
        // 124 'a's so %%EOF is cut at buffer boundary (buffer is 128 bytes)
        for (var i = 0; i < 124; i++) {
          buffer.write('a');
        }
        buffer.write('%%EOF');

        final tok = tokenizerFromString(buffer.toString());
        final eofPosition = await tok.getNextEof();
        expect(eofPosition, equals(124 + 5));
      });

      test('getNextEofSeveralEofTest', () async {
        final data =
            'some text %%EOFto test \nget%%EOFting end of\n fil%%EOFe logic%%EOF';
        final tok = tokenizerFromString(data);
        final eofPosition = await tok.getNextEof();
        expect(eofPosition, equals(data.indexOf('%%EOF') + 5));
      });

      test('getNextEofFollowedByEOLTest', () async {
        final data =
            'some text to test \ngetting end of\n file logic%%EOF\n\r\r\n\r\r\n';
        final tok = tokenizerFromString(data);
        final eofPosition = await tok.getNextEof();
        // After %%EOF + trailing EOL characters
        expect(eofPosition,
            equals(data.indexOf('%%EOF') + 4 + 5)); // 4 EOL chars after %%EOF
      });

      test('getNextEofNoEofTest', () async {
        final data = 'some text to test \ngetting end of\n file logic';
        final tok = tokenizerFromString(data);
        expect(
          () async => await tok.getNextEof(),
          throwsA(isA<IoException>()),
        );
      });
    });

    group('String Content', () {
      test('getDecodedStringContentTest', () async {
        final data = '/Name1 15';
        final tok = tokenizerFromString(data);

        await tok.nextToken();
        expect(String.fromCharCodes(tok.getDecodedStringContent()),
            equals('Name1'));

        await tok.nextToken();
        expect(
            String.fromCharCodes(tok.getDecodedStringContent()), equals('15'));

        await tok.nextToken();
        expect(String.fromCharCodes(tok.getDecodedStringContent()), equals(''));
      });

      test('getDecodedStringContentHexTest', () async {
        final data = '<736f6d652068657820737472696e67>';
        final tok = tokenizerFromString(data);
        await tok.nextToken();
        expect(tok.isHexString(), isTrue);
        expect(String.fromCharCodes(tok.getDecodedStringContent()),
            equals('some hex string'));
      });
    });

    group('Token Types', () {
      test('testOneNumber', () async {
        await checkTokenTypes('/Name1 70',
            [TokenType.name, TokenType.number, TokenType.endOfFile]);
      });

      test('testTwoNumbers', () async {
        await checkTokenTypes('/Name1 70/Name 2', [
          TokenType.name,
          TokenType.number,
          TokenType.name,
          TokenType.number,
          TokenType.endOfFile,
        ]);
      });

      test('tokenTypesTest', () async {
        await checkTokenTypes(
          '<<Size 70/Root 46 0 R/Info 44 0 R/ID[<8C2547D58D4BD2C6F3D32B830BE3259D><8F69587888569A458EB681A4285D5879>]/Prev 116 >>',
          [
            TokenType.startDic, // <<
            TokenType.other, // Size (keyword-like)
            TokenType.number, // 70
            TokenType.name, // /Root
            TokenType.ref, // 46 0 R
            TokenType.name, // /Info
            TokenType.ref, // 44 0 R
            TokenType.name, // /ID
            TokenType.startArray, // [
            TokenType.string, // <hex>
            TokenType.string, // <hex>
            TokenType.endArray, // ]
            TokenType.name, // /Prev
            TokenType.number, // 116
            TokenType.endDic, // >>
            TokenType.endOfFile,
          ],
        );
      });
    });

    group('Token Value Comparison', () {
      test('tokenValueEqualsToTest', () async {
        final data = 'SomeString';
        final tok = tokenizerFromString(data);
        await tok.nextToken();
        expect(tok.tokenValueEqualsTo(Uint8List.fromList(latin1.encode(data))),
            isTrue);
      });

      test('tokenValueEqualsToEmptyTest', () async {
        final data = 'SomeString';
        final tok = tokenizerFromString(data);
        await tok.nextToken();
        // Test with empty bytes (analogous to null in C#)
        expect(tok.tokenValueEqualsTo(Uint8List(0)), isFalse);
      });

      test('tokenValueEqualsToNotSameStringTest', () async {
        final data = 'SomeString';
        final tok = tokenizerFromString(data);
        await tok.nextToken();
        expect(
            tok.tokenValueEqualsTo(
                Uint8List.fromList(latin1.encode('${data}s'))),
            isFalse);
      });

      test('tokenValueEqualsToNotCaseSensitiveStringTest', () async {
        final data = 'SomeString';
        final tok = tokenizerFromString(data);
        await tok.nextToken();
        expect(
            tok.tokenValueEqualsTo(
                Uint8List.fromList(latin1.encode('Somestring'))),
            isFalse);
      });
    });

    group('PDF Header', () {
      test('checkPdfHeaderTest from file', () async {
        final file = File('test/assets/test.pdf');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final tok = PdfTokenizer(RandomAccessFileOrArray(bytes));
          final version = await tok.checkPdfHeader();
          expect(version, contains('1.7'));
        }
      });

      test('getHeaderOffsetTest', () async {
        final data = '%PDF-1.7\n%more content';
        final tok = tokenizerFromString(data);
        // getHeaderOffset reads from current position, so we need to get it first
        // before any other operations
        final offset = await tok.getHeaderOffset();
        expect(offset, equals(0));
      });
    });

    group('Primitives', () {
      test('primitivesTest', () async {
        final data = '<<Size 70.%comment\n'
            '/Value#20 .1'
            '/Root 46 0 R'
            '/Info 44 0 R'
            '/ID[<736f6d652068657820737472696e672>(some simple string )<8C2547D58D4BD2C6F3D32B830BE3259D2>-70.1--0.2]'
            '/Name1 --15'
            '/Prev ---116.23 >>';

        final tok = tokenizerFromString(data);

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.startDic));

        await tok.nextValidToken();
        expect(tok.getTokenType(),
            equals(TokenType.other)); // Size (not a name without /)

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getStringValue(), equals('70.'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.name));
        expect(tok.getStringValue(), equals('Value#20'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getStringValue(), equals('.1'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.name));
        expect(tok.getStringValue(), equals('Root'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.ref));
        expect(tok.getObjNr(), equals(46));
        expect(tok.getGenNr(), equals(0));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.name));
        expect(tok.getStringValue(), equals('Info'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.ref));
        expect(tok.getObjNr(), equals(44));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.name));
        expect(tok.getStringValue(), equals('ID'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.startArray));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.string));
        expect(tok.isHexString(), isTrue);
        expect(tok.getStringValue(), equals('736f6d652068657820737472696e672'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.string));
        expect(tok.isHexString(), isFalse);
        expect(tok.getStringValue(), equals('some simple string '));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.string));
        expect(tok.isHexString(), isTrue);

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getStringValue(), equals('-70.1'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getStringValue(), equals('-0.2'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.endArray));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.name));
        expect(tok.getStringValue(), equals('Name1'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        // Double negative becomes positive 0
        expect(tok.getStringValue(), equals('0'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.name));
        expect(tok.getStringValue(), equals('Prev'));

        await tok.nextValidToken();
        expect(tok.getTokenType(), equals(TokenType.number));
        expect(tok.getStringValue(), equals('-116.23'));
      });
    });

    group('Octal String Decoding', () {
      test('octalNumberLong1Test', () {
        // 49 equal to string "1", octal 1 equals to 1 in decimal
        final bytes = Uint8List.fromList([92, 49]);
        final result = PdfTokenizer.decodeStringContent2(bytes, false);
        expect(result, equals([1]));
      });

      test('octalNumberLong2Test', () {
        // 49 50 equal to string "12", octal 12 equals to 10 in decimal
        final bytes = Uint8List.fromList([92, 49, 50]);
        final result = PdfTokenizer.decodeStringContent2(bytes, false);
        expect(result, equals([10]));
      });

      test('octalNumberLong3Test', () {
        // 49 50 51 equal to string "123", octal 123 equals to 83 in decimal
        final bytes = Uint8List.fromList([92, 49, 50, 51]);
        final result = PdfTokenizer.decodeStringContent2(bytes, false);
        expect(result, equals([83]));
      });

      test('slashAfterShortOctalTest', () {
        // \0\(
        final bytes = Uint8List.fromList([92, 48, 92, 40]);
        final result = PdfTokenizer.decodeStringContent2(bytes, false);
        expect(result, equals([0, 40]));
      });

      test('notOctalAfterShortOctalTest', () {
        // \0 followed by char 26
        final bytes = Uint8List.fromList([92, 48, 26]);
        final result = PdfTokenizer.decodeStringContent2(bytes, false);
        expect(result, equals([0, 26]));
      });

      test('notOctalAfterShortOctalTest2', () {
        // \12 followed by char 26
        final bytes = Uint8List.fromList([92, 49, 50, 26]);
        final result = PdfTokenizer.decodeStringContent2(bytes, false);
        expect(result, equals([10, 26]));
      });

      test('twoShortOctalsWithGarbageTest', () {
        // \0\23 + garbage (4 which should not be taken into account)
        // bytes: 92=backslash, 48='0', 92=backslash, 50='2', 51='3', 52='4'
        // We want to decode \0\23 (bytes 0-4, exclusive end means 5 bytes)
        final bytes = Uint8List.fromList([92, 48, 92, 50, 51, 52]);
        // Use decodeStringContent directly with proper range (0 to 4, inclusive)
        // This decodes bytes 0,1,2,3,4 = \0\23
        final result = PdfTokenizer.decodeStringContent(bytes, 0, 4, false);
        expect(result, equals([0, 19]));
      });
    });
  });
}

/// Helper method to check token types match expected sequence
Future<void> checkTokenTypes(String data, List<TokenType> expectedTypes) async {
  final tok = tokenizerFromString(data);
  for (var i = 0; i < expectedTypes.length; i++) {
    await tok.nextValidToken();
    expect(tok.getTokenType(), equals(expectedTypes[i]), reason: 'Position $i');
  }
}
