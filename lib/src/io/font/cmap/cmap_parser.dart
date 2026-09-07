import 'dart:typed_data';
import 'abstract_cmap.dart';
import 'cmap_content_parser.dart';
import 'cmap_object.dart';
import 'cmap_location.dart';

/// Reads mapping programs, sharing command semantics between both I/O modes.
class CraftCMapParser {
  static const String def = 'def';
  static const String endcidrange = 'endcidrange';
  static const String endcidchar = 'endcidchar';
  static const String endbfrange = 'endbfrange';
  static const String endbfchar = 'endbfchar';
  static const String endcodespacerange = 'endcodespacerange';
  static const String usecmap = 'usecmap';
  static const String registry = 'Registry';
  static const String ordering = 'Ordering';
  static const String supplement = 'Supplement';
  static const String cmapName = 'CMapName';

  /// Maximum number of simultaneously open mapping programs, including root.
  static const int maxLevel = 10;

  static Future<void> loadCidMappings(
          String name, CraftAbstractCMap map, CraftCMapLocation location) =>
      _read(name, map, location, <String>[]);

  static void loadCidMappingsSync(
          String name, CraftAbstractCMap map, CraftCMapLocation location) =>
      _readSync(name, map, location, <String>[]);

  static List<String> _enter(String name, List<String> ancestors) {
    if (ancestors.contains(name)) {
      throw FormatException(
          'CMap inclusion cycle: ${[...ancestors, name].join(' -> ')}');
    }
    if (ancestors.length >= maxLevel) {
      throw FormatException(
          'CMap inclusion exceeds $maxLevel open programs: $name');
    }
    return [...ancestors, name];
  }

  static Future<void> _read(String name, CraftAbstractCMap map,
      CraftCMapLocation location, List<String> ancestors) async {
    final path = _enter(name, ancestors);
    final input = await location.getLocation(name);
    try {
      final parser = CraftCMapContentParser(input);
      final program = _MappingCommands(map, ancestors.isEmpty);
      final operands = <CraftCMapObject>[];
      while (true) {
        parser.parse(operands);
        if (operands.isEmpty) {
          program.finish();
          return;
        }
        final included = program.accept(operands);
        if (included != null) await _read(included, map, location, path);
      }
    } catch (error) {
      throw FormatException('CMap "$name" could not be read: $error');
    } finally {
      input.close();
    }
  }

  static void _readSync(String name, CraftAbstractCMap map,
      CraftCMapLocation location, List<String> ancestors) {
    final path = _enter(name, ancestors);
    final input = location.getLocationSync(name);
    try {
      final parser = CraftCMapContentParser(input);
      final program = _MappingCommands(map, ancestors.isEmpty);
      final operands = <CraftCMapObject>[];
      while (true) {
        parser.parseSync(operands);
        if (operands.isEmpty) {
          program.finish();
          return;
        }
        final included = program.accept(operands);
        if (included != null) _readSync(included, map, location, path);
      }
    } catch (error) {
      throw FormatException('CMap "$name" could not be read: $error');
    } finally {
      input.closeSync();
    }
  }
}

class _MappingCommands {
  final CraftAbstractCMap map;
  final bool root;
  String? pending;
  int expected = 0;
  _MappingCommands(this.map, this.root);

  static const widths = {
    'cidchar': 2,
    'bfchar': 2,
    'cidrange': 3,
    'bfrange': 3,
    'codespacerange': 2,
  };

  void finish() {
    if (pending != null)
      throw FormatException('CMap block $pending has no closing command');
  }

  String? accept(List<CraftCMapObject> tokens) {
    if (!tokens.last.isLiteral()) {
      throw const FormatException('CMap operands have no command');
    }
    final command = tokens.last.toString();
    final values = tokens.sublist(0, tokens.length - 1);
    if (pending != null) {
      final kind = pending!;
      if (command != 'end$kind') {
        throw FormatException('CMap block $kind ended with $command');
      }
      if (values.length != expected * widths[kind]!) {
        throw FormatException('CMap block $kind expected $expected entries');
      }
      pending = null;
      _mapEntries(kind, values);
      return null;
    }
    for (final kind in widths.keys) {
      if (command == 'begin$kind') {
        if (values.length != 1 ||
            !values.single.isNumber() ||
            values.single.getValue() is! int ||
            (values.single.getValue() as int) < 0) {
          throw FormatException(
              'CMap block $kind requires a nonnegative entry count');
        }
        pending = kind;
        expected = values.single.getValue() as int;
        return null;
      }
      if (command == 'end$kind') {
        throw FormatException(
            'CMap closing command $command has no opening block');
      }
    }
    if (command == CraftCMapParser.usecmap) {
      if (values.length != 1 || !values.single.isName()) {
        throw const FormatException('CMap inclusion requires one name');
      }
      return values.single.toString();
    }
    if (root &&
        command == CraftCMapParser.def &&
        values.length == 2 &&
        values[0].isName()) {
      final value = values[1];
      switch (values[0].toString()) {
        case CraftCMapParser.registry:
          map.assignCharacterRegistry(value.toString());
        case CraftCMapParser.ordering:
          map.assignCharacterCollection(value.toString());
        case CraftCMapParser.cmapName:
          map.setName(value.toString());
        case CraftCMapParser.supplement:
          if (!value.isNumber() ||
              value.getValue() is! int ||
              (value.getValue() as int) < 0) {
            throw const FormatException(
                'CMap supplement requires a nonnegative integer');
          }
          map.assignCollectionSupplement(value.getValue() as int);
      }
    }
    return null;
  }

  void _mapEntries(String kind, List<CraftCMapObject> values) {
    final stride = widths[kind]!;
    for (var offset = 0; offset < values.length; offset += stride) {
      final first = values[offset];
      final second = values[offset + 1];
      if (!first.isString())
        throw FormatException('CMap $kind source must be a byte string');
      switch (kind) {
        case 'cidchar':
        case 'bfchar':
          if (kind == 'cidchar' ? !second.isNumber() : !second.isString()) {
            throw FormatException('CMap $kind destination has an invalid type');
          }
          map.registerMappedCode(first.toString(), second);
        case 'cidrange':
        case 'bfrange':
          final target = values[offset + 2];
          if (!second.isString() ||
              (kind == 'cidrange'
                  ? !target.isNumber()
                  : !(target.isString() || target.isArray()))) {
            throw FormatException(
                'CMap $kind range has an invalid endpoint or destination');
          }
          map.expandMappingInterval(
              first.toString(), second.toString(), target);
        case 'codespacerange':
          if (!first.isHexString() || !second.isHexString()) {
            throw const FormatException(
                'CMap code space requires two hexadecimal byte strings');
          }
          final low = Uint8List.fromList(first.toHexByteArray()!);
          final high = Uint8List.fromList(second.toHexByteArray()!);
          if (low.isEmpty ||
              low.length != high.length ||
              _compare(low, high) > 0) {
            throw const FormatException(
                'CMap code space endpoints are incompatible');
          }
          map.registerCodeInterval(low, high);
      }
    }
  }

  static int _compare(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }
}
