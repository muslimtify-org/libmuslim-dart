@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Drives `hook/build.dart` the way a build system does, with a hand-written
/// input document.
///
/// This is the only route to the no-code-assets path from `dart test`: every
/// other test in this suite reaches the native library through the asset the
/// hook already built, so none of them re-runs the hook, and none of them can
/// see it crash.
void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('libmuslim_hook_'));
  tearDown(() => work.deleteSync(recursive: true));

  ProcessResult runHook(Map<String, Object?> config) {
    final shared = Directory('${work.path}/shared')..createSync();
    final outFile = '${work.path}/output.json';
    final input = File('${work.path}/input.json')
      ..writeAsStringSync(
        jsonEncode({
          'assets': <String, Object?>{},
          'config': config,
          'out_dir_shared': '${shared.path}/',
          'out_file': outFile,
          'package_name': 'libmuslim',
          'package_root': '${Directory.current.path}/',
          'user_defines': <String, Object?>{},
        }),
      );

    return Process.runSync(Platform.resolvedExecutable, [
      'run',
      'hook/build.dart',
      '--config=${input.path}',
    ]);
  }

  test('succeeds when the invoker requests no asset types', () {
    // Flutter sends exactly this on `flutter run`'s hot-reload path: no
    // `extensions` key, because nothing is being asked for. The hook used to
    // read `input.config.code` regardless and die on a null dereference,
    // which failed the whole run on every platform.
    final result = runHook({
      'build_asset_types': <String>[],
      'linking_enabled': false,
    });

    expect(
      result.exitCode,
      0,
      reason: 'hook failed:\n${result.stdout}\n${result.stderr}',
    );
    expect(File('${work.path}/output.json').existsSync(), isTrue);
  });
}
