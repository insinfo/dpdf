import 'dart:convert';
import 'dart:io';

import 'package:dpdf/src/html/dom/html_data_image.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:test/test.dart';

void main() {
  test('decodes PNG and JPEG data URIs while preserving requested dimensions',
      () async {
    final png = await File('test/assets/png_greyscale.png').readAsBytes();
    final jpeg = await File('test/assets/Desert.jpg').readAsBytes();
    final decodedPng = HtmlDataImage.tryParse(
        'data:image/png;base64,${base64Encode(png)}',
        width: '20',
        height: '10');
    final decodedJpeg =
        HtmlDataImage.tryParse('data:image/jpeg;base64,${base64Encode(jpeg)}');

    expect(decodedPng, isNotNull);
    expect(decodedPng!.image.getOriginalType(), ImageType.PNG);
    expect(decodedPng.width, 20);
    expect(decodedPng.height, 10);
    expect(decodedJpeg, isNotNull);
    expect(decodedJpeg!.image.getOriginalType(), ImageType.JPEG);
    expect(decodedJpeg.width, greaterThan(0));
    expect(decodedJpeg.height, greaterThan(0));
  });

  test('does not fetch external or malformed image sources', () {
    expect(HtmlDataImage.tryParse('https://example.test/image.png'), isNull);
    expect(HtmlDataImage.tryParse('data:image/gif;base64,AA=='), isNull);
    expect(HtmlDataImage.tryParse('data:image/png;base64,not-base64'), isNull);
  });
}
