import 'dart:io';

/// Run from the repository root. Requires Dart SDK and Node with WasmGC.
Future<void> main() async {
  final folder = Directory('.dart_tool/platform_check');
  await folder.create(recursive: true);
  final base = '${folder.path}/smoke';
  final dart = Platform.resolvedExecutable;
  Future<void> command(String executable, List<String> arguments,
      {String? expected}) async {
    print('$executable ${arguments.join(' ')}');
    final result = await Process.run(executable, arguments);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0 ||
        (expected != null && !result.stdout.toString().contains(expected))) {
      throw StateError(
          'Platform verification failed (exit ${result.exitCode})');
    }
  }

  await command(dart, ['run', 'example/platform_smoke.dart'],
      expected: 'DPDF vm:');
  final native = '$base${Platform.isWindows ? '.exe' : '.native'}';
  await command(
      dart, ['compile', 'exe', 'example/platform_smoke.dart', '-o', native]);
  await command(File(native).absolute.path, [], expected: 'DPDF vm:');
  await command(
      dart, ['compile', 'js', 'example/platform_smoke.dart', '-o', '$base.js']);
  await File('$base.cjs')
      .writeAsString("globalThis.self = globalThis; require('./smoke.js');\n");
  await command('node', ['$base.cjs'], expected: 'DPDF javascript:');
  await command(dart,
      ['compile', 'wasm', 'example/platform_smoke.dart', '-o', '$base.wasm']);
  await File('$base-run.mjs').writeAsString('''
import {readFile} from 'node:fs/promises';
import {compile} from './smoke.mjs';
const module = await compile(await readFile(new URL('./smoke.wasm', import.meta.url)));
const instance = await module.instantiate({});
instance.invokeMain();
''');
  await command('node', ['$base-run.mjs'], expected: 'DPDF webassembly:');

  // Force compilation of modules not reached through the main public barrel.
  final imports = <String>[];
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (path.startsWith('lib/src/platform/') || path.endsWith('_vm.dart'))
      continue;
    if (RegExp(r'^\s*part of\b', multiLine: true)
        .hasMatch(await entity.readAsString())) continue;
    imports.add(
        "import 'package:dpdf/${path.substring(4)}' as surface${imports.length};");
  }
  final surface = '${folder.path}/surface.dart';
  await File(surface).writeAsString('${imports.join('\n')}\nvoid main() {}\n');
  for (final target in ['js', 'wasm']) {
    await command(dart,
        ['compile', target, surface, '-o', '${folder.path}/surface.$target']);
  }
  print('Compiled surface: ${imports.length} libraries.');
}
