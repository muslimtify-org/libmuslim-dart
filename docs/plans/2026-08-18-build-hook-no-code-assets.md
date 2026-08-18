# Build hook crashes when no code assets are requested — Implementation Plan

**Source:** the `debug` report of 2026-08-18. There is no spec for this cycle: it is a routed bug fix with a diagnosed root cause, not new behaviour, so `brainstorm` was not run and none of the package's public API changes.
**Goal:** Stop `hook/build.dart` crashing when the invoker runs it with no asset types requested, which today breaks `flutter run` on every platform.
**Architecture:** The hook reads `input.config.code` unconditionally. That getter builds a `CodeConfig` from the input JSON and dereferences `config.extensions`, which is absent whenever `build_asset_types` is empty. A guard on `input.config.buildCodeAssets` returns early for such invocations, leaving the code-asset path untouched. A new test drives the hook directly against a synthesized empty-type input, which is the only way to reach this path from `dart test`.

## Diagnosis, carried over

- The failing invocation's input is `{"config": {"build_asset_types": [], "linking_enabled": false}, ...}` with **no** `extensions` key.
- `code_assets-1.0.0/lib/src/code_assets/config.dart:52` is `: _syntax = ConfigSyntax.fromJson(json, path: path).extensions!.codeAssets!;`. Column 67 falls on the first `!`.
- Flutter issues such an invocation from `runFlutterSpecificHooks(..., buildCodeAssets: null, buildDataAssets: true)` on `flutter run`'s hot-reload devFS path. It is not Android-specific: `flutter run -d linux` reproduces it, while `flutter run -d linux --no-hot` does not.
- `HookConfig.buildAssetTypes` is a plain list getter and `buildCodeAssets` is `buildAssetTypes.contains(...)`, so neither can throw on this input. The refuter verified this.
- The Android **code asset** build itself works: the recorded `target_os: android` invocation succeeded and wrote its output.

## Global constraints

- `src/`, `ffigen/`, `lib/` and the generated bindings are not touched. This changes the build hook and adds a test.
- No public API changes, so no doc or README updates belong in this cycle.
- Observed toolchain, read from `pubspec.lock`: `code_assets` 1.0.0, `hooks` 1.0.3, `native_toolchain_c` 0.17.6. Dart SDK 3.12.2, Flutter 3.44.2 stable.
- The guard test must fail before the fix. Observed today at the repo root: `dart run hook/build.dart --config=<empty-type input>` exits 255 and writes no `output.json`.

---

### Task 1: Guard the build hook against an invocation with no code assets → verify: `dart test test/build_hook_test.dart` exits zero, `dart test` exits zero, and `dart analyze` exits zero

**Files:**
- Modify: `hook/build.dart` — the `build` callback body
- Create: `test/build_hook_test.dart`

- [ ] Step 1: In `hook/build.dart`, insert this guard as the first statement inside the `build(args, (input, output) async {` callback, immediately above the existing `final packageName = input.packageName;` line:
```dart
    // Flutter runs this hook with no asset types requested on `flutter run`'s
    // hot-reload path, and the input it sends then carries no `extensions`
    // object at all. Reading `input.config.code` in that state dereferences
    // null inside CodeConfig and takes the whole build down with it, so there
    // is nothing to build here and saying so early is the whole fix.
    if (!input.config.buildCodeAssets) return;

```

- [ ] Step 2: Create `test/build_hook_test.dart`:
```dart
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
          'package_name': 'libmuslim_dart',
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
```

- [ ] Step 3: Run `dart test test/build_hook_test.dart`
- [ ] Step 4: Run `dart test`
- [ ] Step 5: Run `dart analyze`
- [ ] Step 6: Commit
