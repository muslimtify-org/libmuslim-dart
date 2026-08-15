# prayertimes FFI follow-up — Implementation Plan

**Spec:** docs/specs/2026-08-15-prayertimes-ffi-bindings-design.md
**Goal:** Close the two blockers `verify` raised against the prayertimes FFI cycle — Goal 3's regeneration command and Goal 7's unmeasured display half — and remove the stale template text the cycle left behind.
**Architecture:** A committed regeneration entry point at `tool/regen.dart` supplies libclang the resource directory it fails to find on its own, derived from `clang -print-resource-dir` rather than hardcoded, and loops over every config in `ffigen/` so future modules need no change to it. A widget test in the example package turns "displays prayer times" from inference into a measurement. The README and the package description stop describing the deleted `sum` scaffold.

## Global constraints

- `src/prayertimes.h` is vendored upstream code and must not be edited.
- Generated bindings are never hand-edited; they are regenerated from the header.
- The raw layer adds no validation, no Dart enums, no `DateTime` conversion, and no value classes. That is a later cycle.
- Observed toolchain, from `pubspec.lock`, `example/pubspec.yaml`, `dart --version` and `clang --version`: Dart SDK 3.12.2, `ffigen` 20.1.1, `ffi` 2.2.0 (root, dev) and `ffi: ^2.1.4` (example), `flutter_test` from the Flutter SDK already in `example/pubspec.yaml` dev-dependencies, clang 22.1.8 with its resource directory at the path `clang -print-resource-dir` reports.
- ffigen resolves `headers.entry-points` and `output` against the config file's own directory, so paths in `ffigen/*.yaml` are prefixed `../`.
- Spec Goal 8 is waived and deferred to the hijri cycle; no task here attempts to observe it.

---

### Task 1: Regeneration entry point → verify: `dart run tool/regen.dart && git diff --exit-code lib/src/` exits zero on a clean tree, with no `CPATH` set in the invoking shell

Spec Goal 3 named a command that exits 1 here: libclang does not locate its own resource directory, so parsing `/usr/include/string.h` fails on `stddef.h`. Two candidates were tested before this plan was written — `llvm-path: ['/usr']` in the ffigen config does **not** fix it, and `CPATH="$(clang -print-resource-dir)/include"` does. This task commits the second as a runnable entry point rather than leaving it as lore.

Looping over `ffigen/*.yaml` rather than naming one config is what keeps spec Goal 8 true: adding hijri adds a config and changes nothing here.

**Files:**
- Create: `tool/regen.dart`
- Modify: `ffigen/prayertimes.yaml` — the `Run with` comment on its first line

- [x] Step 1: Create `tool/regen.dart`:
```dart
import 'dart:io';

/// Regenerates the ffigen bindings for every module under `ffigen/`.
///
/// This exists because libclang does not always locate its own resource
/// directory. When it does not, parsing `/usr/include/string.h` fails with
/// `stddef.h: file not found` and ffigen exits 1 having written nothing
/// useful. Supplying the directory through CPATH fixes it, and asking clang
/// for the path rather than hardcoding one keeps this working across clang
/// versions and machines.
///
/// Run it with `dart run tool/regen.dart`.
Future<void> main() async {
  final environment = <String, String>{};

  final probe = await Process.run('clang', ['-print-resource-dir']);
  if (probe.exitCode == 0) {
    final include = '${(probe.stdout as String).trim()}/include';
    final existing = Platform.environment['CPATH'];
    environment['CPATH'] = (existing == null || existing.isEmpty)
        ? include
        : '$include${Platform.isWindows ? ';' : ':'}$existing';
  } else {
    stderr.writeln(
      'warning: `clang -print-resource-dir` failed; running ffigen without '
      'CPATH. If generation fails on a missing stddef.h, this is why.',
    );
  }

  final configs =
      Directory('ffigen')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (configs.isEmpty) {
    stderr.writeln('no ffigen configs found under ffigen/');
    exit(1);
  }

  for (final config in configs) {
    stdout.writeln('regenerating from ${config.path}');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ffigen',
      '--config',
      config.path,
    ], environment: environment);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) exit(result.exitCode);
  }
}
```

- [x] Step 2: In `ffigen/prayertimes.yaml`, replace the first-line comment `# Run with \`dart run ffigen --config ffigen/prayertimes.yaml\`.` with:
```yaml
# Regenerate with `dart run tool/regen.dart`, which runs every config in this
# directory. Invoking ffigen directly works only if CPATH already points at
# clang's resource include directory; tool/regen.dart sets that for you.
```

- [x] Step 3: Run `dart run tool/regen.dart` in a shell with no `CPATH` set
- [x] Step 4: Run `git diff --exit-code lib/src/`
- [x] Step 5: Commit

**Result:** `f731569`. Clause passed, re-run independently with `env -u CPATH`: `dart run tool/regen.dart` exit 0, `git diff --exit-code lib/src/` exit 0 (no drift). Spec Goal 3 now has a runnable command. No deviation.

---

### Task 2: Example widget test → verify: `flutter test` inside `example/` exits zero

Spec Goal 7 requires the example to build **and display** prayer times. `flutter build linux` covers the first half; nothing covers the second, so `verify` recorded it unmeasured. A widget test that pumps `MyApp` and counts rendered `HH:MM` rows measures it.

`example/pubspec.yaml` already carries `flutter_test` from the Flutter SDK in its dev-dependencies, so no dependency changes. `example/test/` does not exist yet.

The open question this task answers by running: whether `flutter test` builds the native asset from `hook/build.dart` the way `dart test` and `flutter build linux` do. If it does not, that is a `blocked` result naming the failure, not a reason to weaken the test into one that never touches the native library.

**Files:**
- Create: `example/test/widget_test.dart`

- [x] Step 1: Create `example/test/widget_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libmuslim_dart_example/main.dart';

void main() {
  testWidgets('renders one HH:MM row per prayer time', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Every row the example builds is "<Name>: HH:MM", one per field of the
    // C struct. Matching the shape rather than the values keeps this passing
    // as the date changes, while still failing if the FFI call returns
    // nothing, throws, or yields NaN.
    final row = RegExp(
      r'^(Fajr|Sunrise|Dhuha|Dhuhr|Asr|Maghrib|Isha): \d{2}:\d{2}$',
    );
    final rows = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && row.hasMatch(w.data!),
    );

    // struct PrayerTimes has seven fields; the example renders all of them.
    expect(rows, findsNWidgets(7));
  });
}
```

- [x] Step 2: Run `flutter pub get` inside `example/`
- [x] Step 3: Run `flutter test` inside `example/`
- [x] Step 4: Commit

**Result:** `eea341c`. Clause passed, re-run independently: `flutter test` in `example/` exit 0, 1 test. The open question is answered — `flutter test` does build the native asset from `hook/build.dart`, so the widget test exercises the real library. Assertion intact: it pumps the real `MyApp` and requires seven rendered `HH:MM` rows, with no stub or mock. Spec Goal 7's display half is now measured rather than inferred.

---

### Task 3: Replace the stale template documentation → verify: `git grep -n -E '\bsum\b|sumAsync|src/libmuslim_dart|ffigen\.yaml|A new Dart FFI package project' -- README.md pubspec.yaml` reports no match

`verify` recorded one dangling reference at `README.md:43`. Reading the whole file found the problem is wider: the README still describes the deleted scaffold at five separate points, and `pubspec.yaml`'s description is the unedited template string. Each names a file or symbol that no longer exists, so a reader following the README cannot succeed.

Observed stale points, all read from the files: `README.md:3` package description, `README.md:21` claims `build.dart` lives in `bin` when it is in `hook/`, `README.md:33` names the deleted `src/libmuslim_dart.h`, `README.md:34` names the deleted root `ffigen.yaml`, `README.md:39` and `README.md:43` name the deleted `sum` and `sumAsync`. `pubspec.yaml` carries the template `description`.

**Files:**
- Modify: `README.md` — replace everything from the top through the `## Invoking native code` section, keeping the `## Flutter help` section and anything after it unchanged
- Modify: `pubspec.yaml` — the `description` field

- [x] Step 1: In `README.md`, replace everything above the `## Flutter help` heading with the content between the four-backtick fences below. The inner triple-backtick fences are part of the README content and must be written into the file as-is:

````markdown
# libmuslim_dart

Dart FFI bindings for [libmuslim](https://github.com/muslimtify-org), a
collection of stb-style single-header C libraries for Muslim applications.

Currently bound: `prayertimes.h` — prayer times for a date and location across
21 calculation methods.

## Usage

```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:libmuslim_dart/prayertimes.dart';

final key = 'kemenag'.toNativeUtf8();
final params = method_params_get(method_from_string(key.cast<Char>()));
final times = calculate_prayer_times(
  2025, 11, 21,    // date
  -6.2851291,      // latitude, negative = South
  106.9814968,     // longitude, positive = East
  7.0,             // UTC offset in hours
  params,
);

final buf = calloc<Char>(16);
format_time_hm(times.fajr, buf, 16);
print(buf.cast<Utf8>().toDartString());   // 04:05
calloc.free(buf);
malloc.free(key);
```

These are the raw generated bindings: pointers, decimal-hour doubles, and
caller-allocated buffers. An idiomatic Dart layer is a later addition. The
ownership and failure rules are documented on `lib/prayertimes.dart` — read
them before calling anything, in particular that `calculate_prayer_times`
segfaults rather than throwing if handed a null `params`.

## Project structure

Each module is one vendored header, one translation unit that instantiates it,
one ffigen config, and one public entry point.

* `src/` — the vendored single-header libraries and the `.c` files that define
  their `*_IMPLEMENTATION` macro, plus `abi_probe.c`, which exports the
  header's own `sizeof` and constants so the tests can verify the Dart structs
  against the compiled C.

* `ffigen/` — one config per module. Paths inside are relative to this
  directory, and every config pins the same `asset-id` so all generated files
  resolve against the single shared library.

* `lib/<module>.dart` — the public entry point per module.
  `lib/src/<module>/` holds its generated bindings, which are never hand-edited.

* `hook/build.dart` — compiles every listed `.c` into one shared library.

## Regenerating the bindings

```sh
dart run tool/regen.dart
```

This runs every config in `ffigen/`. Do not invoke `ffigen` directly unless
`CPATH` already points at clang's resource include directory — libclang does
not always find it, and the failure surfaces as a missing `stddef.h`.

## Testing

```sh
dart test              # ABI verification and a published golden
cd example && flutter test
```
````

- [x] Step 2: In `pubspec.yaml`, replace the `description` field value `"A new Dart FFI package project."` with `"Dart FFI bindings for libmuslim: prayer times and other tools for Muslim applications."`
- [x] Step 3: Run `dart pub get`
- [x] Step 4: Run `dart analyze`
- [x] Step 5: Commit

**Result:** `07200ef`. Clause passed, re-run independently: the grep reports no match (exit 1), `dart analyze` exit 0, the `## Flutter help` section is preserved at line 76, no stray four-backtick fence leaked into the file, and `pubspec.yaml` name and version are unchanged. Scope was exactly the two planned files.
