import 'dart:convert';

import 'package:dpdf/src/io/font/cid_font_properties.dart';
import 'package:dpdf/src/io/font/cjk_resource_loader.dart';
import 'package:dpdf/src/io/font/cjk_resource_provider.dart';
import 'package:test/test.dart';

List<int> _bytes(String value) => utf8.encode(value);

void main() {
  tearDown(() => CraftCjkResourceLoader.setResourceProvider(null));

  test('loads registry, font metadata and CMaps from consumer bytes', () {
    final source = <String, List<int>>{
      'cjk_registry.properties': _bytes('fonts=OwnCJK\nOwn=Own-H\n'),
      'OwnCJK.properties': _bytes('Registry=Own\nW=7 1000\n'),
      'Own-H': _bytes('1 begincidchar <41> 7 endcidchar'),
    };
    final provider = CraftCjkMemoryResourceProvider(source);
    CraftCjkResourceLoader.setResourceProvider(provider);
    source['Own-H']![0] = 0;

    expect(CraftCidFontProperties.isCjkFont('OwnCJK'), isTrue);
    expect(CraftCidFontProperties.isCidFont('OwnCJK', 'Own-H'), isTrue);
    expect(CraftCjkResourceLoader.getCidToCodepointCmapSync('Own-H').lookup(7),
        [0x41]);
  });

  test('memory provider is browser-safe and does not expose mutable bytes', () {
    final provider = CraftCjkMemoryResourceProvider({
      'program': [1, 2]
    });
    final first = provider.readSync('program')!;
    first[0] = 99;
    expect(provider.readSync('program'), [1, 2]);
    expect(() => provider.readSync('../program'), throwsArgumentError);
    expect(
        () => CraftCjkMemoryResourceProvider({
              'a/b': [1]
            }),
        throwsArgumentError);
  });
}
