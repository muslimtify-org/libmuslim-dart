@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
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
    final out = Directory('${work.path}/out')..createSync();
    final outFile = '${work.path}/output.json';
    final input = File('${work.path}/input.json')
      ..writeAsStringSync(
        jsonEncode({
          'assets': <String, Object?>{},
          'config': config,
          'out_dir': '${out.path}/',
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

  test('declares the vendored header as a dependency', () {
    // src/prayertimes.c is two lines that #include the header holding every
    // line of the implementation, so a dependency set naming only the sources
    // watches files that can never change. Editing prayertimes.h then leaves
    // the cached library in place, and the suite passes against code that is
    // no longer on disk. That is not hypothetical: it is what a header sync
    // looks like, and it is why this asserts on the hook's own output rather
    // than on a rebuild happening.
    final abi = Abi.current().toString().split('_');
    final result = runHook({
      'build_asset_types': ['code_assets/code'],
      'linking_enabled': false,
      'extensions': {
        'code_assets': {
          'target_os': abi.first,
          'target_architecture': abi.last,
          'link_mode_preference': 'dynamic',
        },
      },
    });

    expect(
      result.exitCode,
      0,
      reason: 'hook failed:\n${result.stdout}\n${result.stderr}',
    );

    final output =
        jsonDecode(File('${work.path}/output.json').readAsStringSync())
            as Map<String, Object?>;
    final dependencies = (output['dependencies'] as List).cast<String>();

    expect(
      dependencies,
      contains(endsWith('src/prayertimes.h')),
      reason:
          'the header is not watched, so a sync cannot invalidate the '
          'cached library:\n${dependencies.join('\n')}',
    );
  });
}
