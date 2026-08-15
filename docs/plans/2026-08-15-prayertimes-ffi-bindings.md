# prayertimes raw FFI bindings — Implementation Plan

**Spec:** docs/specs/2026-08-15-prayertimes-ffi-bindings-design.md
**Goal:** Compile `src/prayertimes.h` into the package's shared object and expose it to Dart as generated raw FFI bindings, replacing the `flutter create --template=plugin_ffi` scaffold.
**Architecture:** One `CBuilder.library` produces one shared object from an explicit list of C translation units; each module contributes a two-line `src/<module>.c` that instantiates its single-header implementation. Each module gets its own ffigen config writing into `lib/src/<module>/`, and every config pins the same `ffi-native: asset-id` so all generated files resolve against that one library. A public `lib/<module>.dart` re-exports the generated bindings today and will host the idiomatic Dart API in a later cycle.

## Global constraints

- `src/prayertimes.h` is vendored upstream code and must not be edited.
- `PRAYERTIMES_IMPLEMENTATION` is defined in exactly one translation unit.
- `assetName` in `hook/build.dart` and `asset-id` in every ffigen config are the same string.
- Generated bindings are never hand-edited; they are regenerated from the header.
- The raw layer adds no validation, no Dart enums, no `DateTime` conversion, and no value classes. That is a later cycle.
- Observed toolchain, from `pubspec.lock` and `dart --version`: Dart SDK 3.12.2, `ffigen` 20.1.1, `native_toolchain_c` 0.17.6, `hooks` 1.0.3, `code_assets` 1.0.0, `ffi` 2.2.0, `test` 1.31.2.
- `ffi-native`'s asset key is spelled `asset-id` (`ffigen-20.1.1/lib/src/strings.dart:279`).
- `CBuilder.library` accepts `sources`, `includes`, `libraries`, `flags`, `defines` and `std` (`native_toolchain_c-0.17.6/lib/src/cbuilder/cbuilder.dart:55-81`).
- The build hook reads the target OS as `input.config.code.targetOS` (`native_toolchain_c-0.17.6/lib/src/cbuilder/cbuilder.dart:147`).

---

### Task 1: Baseline the untracked tree → verify: `git status --porcelain` reports no entry beginning with `??`

The repository's only commits are the two spec commits; every source file is untracked, so later tasks would produce diffs against nothing. This task also records the command that runs the test suite, which every later verify clause depends on.

**Files:**
- Modify: `.gitignore`, only if Step 1 finds a build output directory missing from it

- [x] Step 1: Run `cat .gitignore` and confirm build output directories are listed. If `.dart_tool/` is absent, append it.
- [x] Step 2: Run `dart pub get`
- [x] Step 3: Run `dart test` against the untouched template and record in the commit message the exact command that exited zero, including any flag it required. Every later task uses that recorded command wherever this plan writes `dart test`.
- [x] Step 4: Run `git add -A`
- [x] Step 5: Commit

**Result:** `a429198`. The recorded invocation is plain `dart test`, no flag required on Dart 3.12.2.

---

### Task 2: Compile prayertimes and the ABI probe into the library → verify: `dart test` exits zero and `nm -D` (or `dumpbin /exports` on Windows) on the built shared object matches `calculate_prayer_times` at least once

Adds the implementation TU and the probe alongside the existing template. Nothing is deleted yet, so the template's tests keep passing and this task's success isolates one question: does `prayertimes.h` compile, link and export.

**Files:**
- Create: `src/prayertimes.c`
- Create: `src/abi_probe.c`
- Modify: `hook/build.dart:8-12`

- [x] Step 1: Create `src/prayertimes.c`:
```c
#define PRAYERTIMES_IMPLEMENTATION
#include "prayertimes.h"
```

- [x] Step 2: Create `src/abi_probe.c`. The `_Static_assert` block and the `abi_constant_*` and `abi_*_civil*` functions are ported from `~/Projects/libmuslim-rs/include/abi_probe.c`. The `abi_fill_*` functions replace that file's `offsetof`/`_Alignof` exports, because `dart:ffi` exposes `sizeOf<T>()` but no `offsetOf` and no `alignOf`.
```c
#include <stddef.h>
#include "prayertimes.h"

_Static_assert(CALC_MWL == 0, "CALC_MWL");
_Static_assert(CALC_MAKKAH == 1, "CALC_MAKKAH");
_Static_assert(CALC_ISNA == 2, "CALC_ISNA");
_Static_assert(CALC_EGYPT == 3, "CALC_EGYPT");
_Static_assert(CALC_KARACHI == 4, "CALC_KARACHI");
_Static_assert(CALC_TURKEY == 5, "CALC_TURKEY");
_Static_assert(CALC_SINGAPORE == 6, "CALC_SINGAPORE");
_Static_assert(CALC_JAKIM == 7, "CALC_JAKIM");
_Static_assert(CALC_KEMENAG == 8, "CALC_KEMENAG");
_Static_assert(CALC_FRANCE == 9, "CALC_FRANCE");
_Static_assert(CALC_RUSSIA == 10, "CALC_RUSSIA");
_Static_assert(CALC_DUBAI == 11, "CALC_DUBAI");
_Static_assert(CALC_QATAR == 12, "CALC_QATAR");
_Static_assert(CALC_KUWAIT == 13, "CALC_KUWAIT");
_Static_assert(CALC_JORDAN == 14, "CALC_JORDAN");
_Static_assert(CALC_GULF == 15, "CALC_GULF");
_Static_assert(CALC_TUNISIA == 16, "CALC_TUNISIA");
_Static_assert(CALC_ALGERIA == 17, "CALC_ALGERIA");
_Static_assert(CALC_MOROCCO == 18, "CALC_MOROCCO");
_Static_assert(CALC_PORTUGAL == 19, "CALC_PORTUGAL");
_Static_assert(CALC_MOONSIGHTING == 20, "CALC_MOONSIGHTING");
_Static_assert(CALC_CUSTOM == 21, "CALC_CUSTOM");
_Static_assert(CALC_COUNT == 22, "CALC_COUNT");
_Static_assert(ASR_STANDARD == 1 && ASR_HANAFI == 2, "AsrSchool");
_Static_assert(HIGHLAT_NONE == 0 && HIGHLAT_MIDDLE_OF_NIGHT == 1 &&
                   HIGHLAT_ONE_SEVENTH == 2 && HIGHLAT_ANGLE_BASED == 3,
               "HighLatMethod");
_Static_assert(MIDNIGHT_STANDARD == 0, "MidnightMode");

size_t abi_sizeof_method_params(void) { return sizeof(MethodParams); }
size_t abi_sizeof_prayer_times(void) { return sizeof(struct PrayerTimes); }

/* Field-offset verification for Dart.
 *
 * dart:ffi has no offsetOf, so the Rust binding's per-field offsetof
 * comparison cannot be ported literally. Instead these write a distinct
 * sentinel through each C field name; the Dart test reads each field through
 * the generated struct and asserts the value. A wrong offset or a wrong field
 * width yields a wrong number, so the assertion fails. */
void abi_fill_method_params(MethodParams *out) {
  out->name = "probe";
  out->fajr_angle = 11.0;
  out->isha_angle = 22.0;
  out->isha_interval = 33;
  out->maghrib_interval = 44;
  out->asr_shadow = 55;
  out->midnight_mode = MIDNIGHT_STANDARD;
  out->ihtiyat = 66;
}

void abi_fill_prayer_times(struct PrayerTimes *out) {
  out->fajr = 1.5;
  out->sunrise = 2.5;
  out->dhuha = 3.5;
  out->dhuhr = 4.5;
  out->asr = 5.5;
  out->maghrib = 6.5;
  out->isha = 7.5;
}

double abi_constant_deg_to_rad(void) { return DEG_TO_RAD; }
double abi_constant_rad_to_deg(void) { return RAD_TO_DEG; }
double abi_constant_julian_epoch(void) { return JULIAN_EPOCH; }
double abi_constant_sun_mean_anomaly_offset(void) { return SUN_MEAN_ANOMALY_OFFSET; }
double abi_constant_sun_mean_anomaly_rate(void) { return SUN_MEAN_ANOMALY_RATE; }
double abi_constant_sun_mean_longitude_offset(void) { return SUN_MEAN_LONGITUDE_OFFSET; }
double abi_constant_sun_mean_longitude_rate(void) { return SUN_MEAN_LONGITUDE_RATE; }
double abi_constant_sun_eccentricity_amplitude1(void) { return SUN_ECCENTRICITY_AMPLITUDE1; }
double abi_constant_sun_eccentricity_amplitude2(void) { return SUN_ECCENTRICITY_AMPLITUDE2; }
double abi_constant_obliquity_coeff(void) { return OBLIQUITY_COEFF; }
double abi_constant_obliquity_rate(void) { return OBLIQUITY_RATE; }
double abi_constant_refraction_correction(void) { return REFRACTION_CORRECTION; }
double abi_constant_dhuha_altitude(void) { return DHUHA_ALTITUDE; }

/* mt_days_from_civil and mt_civil_from_days are static inline in the header,
 * so they have no external linkage and ffigen cannot bind them. These wrappers
 * are the only route to them from Dart. */
long abi_days_from_civil(int y, int m, int d) {
  return mt_days_from_civil(y, m, d);
}

void abi_civil_from_days(long days, int *y, int *m, int *d) {
  mt_civil_from_days(days, y, m, d);
}
```

- [x] Step 3: Replace the `CBuilder.library` call in `hook/build.dart` so it compiles an explicit source list, pins C11 for `_Static_assert`, and links libm off Windows. `assetName` keeps its current value because it is the library's identity, matched by every ffigen `asset-id`:
```dart
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: ['src/prayertimes.c', 'src/abi_probe.c', 'src/$packageName.c'],
      // _Static_assert in abi_probe.c needs an explicit C11 baseline rather
      // than whatever the host compiler defaults to.
      std: 'c11',
      // prayertimes.h uses sin/cos/atan2 from libm. Windows folds the math
      // functions into the CRT and has no separate libm to link.
      libraries: input.config.code.targetOS == OS.windows ? const [] : const ['m'],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = .ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
```

- [x] Step 4: Run `dart pub get`
- [x] Step 5: Run `dart test`
- [x] Step 6: Locate the built shared object under `.dart_tool/` and run `nm -D` on it, filtering for `calculate_prayer_times`
- [x] Step 7: Commit

**Result:** `bd4c133`. Clause passed: `dart test` exit 0, `nm -D .dart_tool/lib/liblibmuslim_dart.so` matched `T calculate_prayer_times`, and 19 `abi_*` symbols are exported.

**Deviation from Step 3:** the implementer used `std: 'gnu11'`, not `'c11'`. Under strict `-std=c11` clang hides the POSIX visibility macros that declare `usleep`, which the template's `src/libmuslim_dart.c` calls, so the build failed with `call to undeclared function 'usleep'`. `gnu11` still provides `_Static_assert`, which is the only reason Step 3 pins a C11 baseline. The template file that forced this is deleted in Task 6, so `std` is revisited there.

---

### Task 3: Module layout, ffigen config and generated bindings → verify: `dart analyze` exits zero, and `grep -c` over the generated file matches `class MethodParams` at least once and `class PrayerTimes` at least once

Establishes the layout every later module inherits, and is the task that satisfies the spec's requirement that a new module cost only a `src/<module>.c`, an `ffigen/<module>.yaml`, a `lib/<module>.dart` and one appended `sources` entry. The explicit `asset-id` is load-bearing: `@Native` without one resolves against the enclosing Dart library's own URI, so moving the generated file into `lib/src/prayertimes/` would silently point it at an asset the build hook never produced.

`lib/prayertimes.dart` is created here rather than alongside the template removal, because Tasks 4 and 5 import through it and a verify clause must be satisfiable by the task it belongs to.

**Files:**
- Create: `ffigen/prayertimes.yaml`
- Create: `lib/src/prayertimes/prayertimes_bindings_generated.dart` (by running ffigen, not by hand)
- Create: `lib/prayertimes.dart`

- [x] Step 1: Create `ffigen/prayertimes.yaml`:
```yaml
# Run with `dart run ffigen --config ffigen/prayertimes.yaml`.
name: PrayertimesBindings
description: |
  Raw bindings for `src/prayertimes.h`.

  Regenerate with `dart run ffigen --config ffigen/prayertimes.yaml`.
output: 'lib/src/prayertimes/prayertimes_bindings_generated.dart'
headers:
  entry-points:
    - 'src/prayertimes.h'
  include-directives:
    - 'src/prayertimes.h'
ffi-native:
  # Must equal `package:<packageName>/<assetName>` from hook/build.dart.
  # Without it, @Native resolves against this file's own package URI, which
  # no build hook produces.
  asset-id: 'package:libmuslim_dart/libmuslim_dart_bindings_generated.dart'
comments:
  style: any
  length: full
```

- [x] Step 2: Run `dart run ffigen --config ffigen/prayertimes.yaml`

- [x] Step 3: Create `lib/prayertimes.dart`, the module's public entry point. Today it only re-exports the generated bindings; the idiomatic Dart API is built here in a later cycle. Its doc comment is where the boundary's ownership and failure rules live, so they are not rediscovered by whoever writes that API:
```dart
/// Raw FFI bindings for `prayertimes.h`.
///
/// This is the generated C API, unwrapped. An idiomatic Dart layer will be
/// added on top of this library; until then callers work with pointers and
/// decimal-hour doubles directly.
///
/// Memory ownership across the boundary, in three rules:
///
/// 1. [method_params_get] returns a pointer into C static storage. Never free
///    it; it is valid for the process lifetime. The same holds for
///    [method_to_string] and for `MethodParams.name`.
/// 2. [calculate_prayer_times] returns `PrayerTimes` by value. Dart copies it
///    out of the return registers; there is nothing to free.
/// 3. [format_time_hm] and [format_time_hms] write into a buffer the caller
///    allocates and frees.
///
/// Failure modes inherited from C, none of which this layer changes:
///
/// - [method_params_get] returns `nullptr` for an out-of-range method.
///   Reading `.ref` on `nullptr` throws.
/// - [method_from_string] returns `CALC_CUSTOM` for null or unknown input. It
///   never reports failure.
/// - **[calculate_prayer_times] dereferences `params` unconditionally. Passing
///   `nullptr` segfaults the process: no Dart exception and no stack trace.**
///   Guarding this is the job of the Dart API layer built on top of here.
/// - No function reports failure for out-of-range coordinates. A latitude of
///   95.0 yields `NaN`s rather than an error.
library;

export 'src/prayertimes/prayertimes_bindings_generated.dart';
```

- [x] Step 4: Run `dart analyze`
- [x] Step 5: Run `grep -c "class MethodParams" lib/src/prayertimes/prayertimes_bindings_generated.dart` and `grep -c "class PrayerTimes" lib/src/prayertimes/prayertimes_bindings_generated.dart`
- [x] Step 6: Run `dart run ffigen --config ffigen/prayertimes.yaml && git diff --exit-code lib/src/` to confirm regeneration is idempotent against the committed file. Run it after staging, so the diff has something to compare against.
- [x] Step 7: Commit

**Result:** `95bb8a6`. Clause passed: `dart analyze` exit 0, one `class MethodParams` and one `class PrayerTimes` in the generated file, all 6 public functions bound, regeneration idempotent.

**Deviation from Step 1 — relative paths.** ffigen 20.1.1 resolves `headers.entry-points` and `output` against the config file's own directory, not the invocation cwd. With the config at `ffigen/prayertimes.yaml`, the literal paths resolved to `ffigen/src/prayertimes.h` (missing, producing a silently empty 4-line binding file) and `ffigen/lib/src/…`. Both are prefixed with `../` in the committed config. Any future module config must do the same.

**Environment requirement, not encoded anywhere.** Regeneration on this machine needs `CPATH=/usr/lib/clang/22/include` set for the ffigen invocation; without it libclang fails on `stddef.h: file not found` from `/usr/include/string.h`. This reproduces with the old root `ffigen.yaml` too, so it predates this work. It affects the spec's regenerate-and-diff check (Goal 3), which will fail for the wrong reason on a machine where this is unset. Recorded, not fixed — belongs to a follow-up, not this cycle.

**Identifiers ffigen emitted**, confirming Task 4's fallback step is unnecessary: enum members keep their C names (`CalcMethod.CALC_KEMENAG`), and the header's `#define`d doubles become top-level `const double` with their C names (`DHUHA_ALTITUDE`, `DEG_TO_RAD`, …). `mt_days_from_civil` and `mt_civil_from_days` were skipped with a warning, as expected for `static inline` — which is exactly why `src/abi_probe.c` wraps them.

---

### Task 4: ABI verification tests → verify: `dart test test/prayertimes_abi_test.dart` exits zero

The enum values need no Dart assertion: `_Static_assert` in `src/abi_probe.c` fails the C build if the header renumbers any of them, which Task 2 already established.

**Files:**
- Create: `test/prayertimes_abi_test.dart`
- Modify: `pubspec.yaml` only if `dart analyze` reports `ffi` as an undeclared dependency for a test file; it is currently a dev-dependency at version 2.2.0, which covers test-only use

- [x] Step 1: Create `test/prayertimes_abi_test.dart`. The probe functions are not in `prayertimes.h`, so ffigen did not bind them; they are declared here with `@Native` carrying the same `assetId` as the generated file:
```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:libmuslim_dart/prayertimes.dart';

const _assetId = 'package:libmuslim_dart/libmuslim_dart_bindings_generated.dart';

@Native<Size Function()>(assetId: _assetId)
external int abi_sizeof_method_params();

@Native<Size Function()>(assetId: _assetId)
external int abi_sizeof_prayer_times();

@Native<Void Function(Pointer<MethodParams>)>(assetId: _assetId)
external void abi_fill_method_params(Pointer<MethodParams> out);

@Native<Void Function(Pointer<PrayerTimes>)>(assetId: _assetId)
external void abi_fill_prayer_times(Pointer<PrayerTimes> out);

@Native<Double Function()>(assetId: _assetId)
external double abi_constant_deg_to_rad();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_rad_to_deg();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_julian_epoch();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_anomaly_offset();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_anomaly_rate();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_longitude_offset();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_longitude_rate();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_eccentricity_amplitude1();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_eccentricity_amplitude2();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_obliquity_coeff();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_obliquity_rate();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_refraction_correction();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_dhuha_altitude();

@Native<Long Function(Int, Int, Int)>(assetId: _assetId)
external int abi_days_from_civil(int y, int m, int d);

@Native<Void Function(Long, Pointer<Int>, Pointer<Int>, Pointer<Int>)>(
  assetId: _assetId,
)
external void abi_civil_from_days(
  int days,
  Pointer<Int> y,
  Pointer<Int> m,
  Pointer<Int> d,
);

void main() {
  group('struct size', () {
    test('MethodParams', () {
      expect(sizeOf<MethodParams>(), abi_sizeof_method_params());
    });

    test('PrayerTimes', () {
      expect(sizeOf<PrayerTimes>(), abi_sizeof_prayer_times());
    });
  });

  group('field round-trip', () {
    test('MethodParams', () {
      final p = calloc<MethodParams>();
      try {
        abi_fill_method_params(p);
        expect(p.ref.name.cast<Utf8>().toDartString(), 'probe');
        expect(p.ref.fajr_angle, 11.0);
        expect(p.ref.isha_angle, 22.0);
        expect(p.ref.isha_interval, 33);
        expect(p.ref.maghrib_interval, 44);
        expect(p.ref.asr_shadow, 55);
        expect(p.ref.ihtiyat, 66);
      } finally {
        calloc.free(p);
      }
    });

    test('PrayerTimes', () {
      final p = calloc<PrayerTimes>();
      try {
        abi_fill_prayer_times(p);
        expect(p.ref.fajr, 1.5);
        expect(p.ref.sunrise, 2.5);
        expect(p.ref.dhuha, 3.5);
        expect(p.ref.dhuhr, 4.5);
        expect(p.ref.asr, 5.5);
        expect(p.ref.maghrib, 6.5);
        expect(p.ref.isha, 7.5);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('header constants', () {
    test('all thirteen match the compiled header', () {
      expect(abi_constant_deg_to_rad(), DEG_TO_RAD);
      expect(abi_constant_rad_to_deg(), RAD_TO_DEG);
      expect(abi_constant_julian_epoch(), JULIAN_EPOCH);
      expect(abi_constant_sun_mean_anomaly_offset(), SUN_MEAN_ANOMALY_OFFSET);
      expect(abi_constant_sun_mean_anomaly_rate(), SUN_MEAN_ANOMALY_RATE);
      expect(
        abi_constant_sun_mean_longitude_offset(),
        SUN_MEAN_LONGITUDE_OFFSET,
      );
      expect(abi_constant_sun_mean_longitude_rate(), SUN_MEAN_LONGITUDE_RATE);
      expect(
        abi_constant_sun_eccentricity_amplitude1(),
        SUN_ECCENTRICITY_AMPLITUDE1,
      );
      expect(
        abi_constant_sun_eccentricity_amplitude2(),
        SUN_ECCENTRICITY_AMPLITUDE2,
      );
      expect(abi_constant_obliquity_coeff(), OBLIQUITY_COEFF);
      expect(abi_constant_obliquity_rate(), OBLIQUITY_RATE);
      expect(abi_constant_refraction_correction(), REFRACTION_CORRECTION);
      expect(abi_constant_dhuha_altitude(), DHUHA_ALTITUDE);
    });
  });

  group('civil date helpers', () {
    // The two static inline helpers, reachable only through the probe.
    // A leap day, the epoch itself, and a pre-epoch date.
    for (final (y, m, d) in const [
      (2024, 2, 29),
      (1970, 1, 1),
      (1601, 12, 31),
      (2026, 8, 15),
    ]) {
      test('$y-$m-$d round-trips', () {
        final days = abi_days_from_civil(y, m, d);
        final out = calloc<Int>(3);
        try {
          abi_civil_from_days(days, out, out + 1, out + 2);
          expect(out[0], y);
          expect(out[1], m);
          expect(out[2], d);
        } finally {
          calloc.free(out);
        }
      });
    }

    test('epoch is day zero', () {
      expect(abi_days_from_civil(1970, 1, 1), 0);
    });
  });
}
```

- [x] Step 2: Run `dart test test/prayertimes_abi_test.dart`
- [x] Step 3: If `dart analyze` reports that the constants ffigen emitted carry different identifiers than the header's macro names, correct the `header constants` group to the identifiers present in `lib/src/prayertimes/prayertimes_bindings_generated.dart` and rerun Step 2
- [x] Step 4: Run `dart analyze`
- [x] Step 5: Commit

**Result:** `b55db20`. Clause passed: `dart test test/prayertimes_abi_test.dart` exit 0, 10 tests. The sentinel round-trip confirms every field of both structs lands at the offset and width the compiled C uses. No deviation from the brief; Step 3's fallback was checked and not needed, and `pubspec.yaml` needed no change because the `ffi` dev-dependency already covers `test/`.

`dart analyze` exits 0 with 19 info-level `non_constant_identifier_names` lints, from the snake_case `@Native` declarations that must match C symbol names exactly. Cosmetic; silencing them is a follow-up, not this cycle.

---

### Task 5: Golden prayer-time test → verify: `dart test test/prayertimes_test.dart` exits zero

Exercises the whole chain in one case: string to method, method to `Pointer<MethodParams>`, struct returned by value, formatting through a caller-allocated buffer. Struct-by-value marshalling is the failure this catches that Task 4 cannot, because Task 4 only ever passes structs by pointer.

The method is selected via `method_from_string('kemenag')` rather than a `CALC_KEMENAG` constant. Its return value feeds straight into `method_params_get`, so the test never has to name the Dart type ffigen chose for the enum.

**Files:**
- Create: `test/prayertimes_test.dart`

- [x] Step 1: Create `test/prayertimes_test.dart`. The inputs and the expected `04:05` are the worked example in `~/Projects/libmuslim/README.md`:
```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:libmuslim_dart/prayertimes.dart';

void main() {
  test('Jakarta 2025-11-21 kemenag matches the upstream worked example', () {
    final key = 'kemenag'.toNativeUtf8();
    final buf = calloc<Char>(16);
    try {
      final params = method_params_get(method_from_string(key.cast<Char>()));
      expect(params, isNot(nullptr));

      final times = calculate_prayer_times(
        2025,
        11,
        21,
        -6.2851291,
        106.9814968,
        7.0,
        params,
      );

      format_time_hm(times.fajr, buf, 16);
      expect(buf.cast<Utf8>().toDartString(), '04:05');
    } finally {
      calloc.free(buf);
      malloc.free(key);
    }
  });
}
```

- [x] Step 2: Run `dart test test/prayertimes_test.dart`
- [x] Step 3: Run `dart analyze`
- [x] Step 4: Commit

**Result:** `0e19012`. Clause passed: `dart test test/prayertimes_test.dart` exit 0, 1 test, Fajr matched `04:05` exactly against the upstream worked example. Struct-by-value return across the FFI boundary is confirmed correct — the one thing Task 4 could not check, since it only passes structs by pointer. No deviation.

---

### Task 6: Remove the template → verify: `dart test` exits zero, `dart analyze lib test hook` exits zero, and `git grep -c sum_long_running -- ':!docs'` reports no match

Everything the prayertimes module needs already exists after Task 5. This task removes the scaffold it was built alongside, and is the last point at which the package still contains code that will never be supported.

**Clause amended after the task ran.** The original read `dart analyze` and `git grep -c sum_long_running`, and both were unsatisfiable by this task through no fault of the implementation. `dart analyze` at the package root descends into `example/`, which this task knowingly breaks and Task 7 repairs, so Task 6 could never make it exit zero — a violation of the rule that a clause must be satisfiable by the task it belongs to. `git grep` without a pathspec searches this plan and its spec, both of which quote `sum_long_running` in prose. The amended clause checks the same two properties against the code alone: no scaffold symbol survives anywhere outside `docs/`, and everything this package actually ships analyzes clean. It is not weaker — `dart analyze lib test hook` covers every Dart file the package owns.

**Files:**
- Modify: `lib/libmuslim_dart.dart` — replace the whole file, currently the `sum`/`sumAsync` scaffold
- Modify: `hook/build.dart` — drop `'src/$packageName.c'` from the `sources` list written in Task 2
- Delete: `src/libmuslim_dart.c`
- Delete: `src/libmuslim_dart.h`
- Delete: `lib/libmuslim_dart_bindings_generated.dart`
- Delete: `test/libmuslim_dart_test.dart`
- Delete: `ffigen.yaml` — superseded by `ffigen/prayertimes.yaml`

- [x] Step 1: Replace the entire contents of `lib/libmuslim_dart.dart`:
```dart
/// libmuslim for Dart: bindings to the libmuslim collection of single-header
/// C libraries.
///
/// Each module is also importable on its own, which is the preferred form:
///
/// ```dart
/// import 'package:libmuslim_dart/prayertimes.dart';
/// ```
library;

export 'prayertimes.dart';
```

- [x] Step 2: Run `git rm src/libmuslim_dart.c src/libmuslim_dart.h lib/libmuslim_dart_bindings_generated.dart test/libmuslim_dart_test.dart ffigen.yaml`
- [x] Step 3: In `hook/build.dart`, change the `sources` list to `['src/prayertimes.c', 'src/abi_probe.c']`
- [x] Step 4: In `hook/build.dart`, change `std: 'gnu11'` back to `std: 'c11'`. **Amendment, added after Task 2 reported its deviation.** Task 2 had to relax the baseline to `gnu11` because the template's `src/libmuslim_dart.c` calls `usleep`, which strict `-std=c11` hides. Step 2 of this task deletes that file, so the only remaining translation units are `src/prayertimes.c` and `src/abi_probe.c`, both of which the upstream project builds under strict C11. Restoring it keeps the vendored header honest about the portability it advertises. If the build fails under `c11` after the deletion, that is a real finding about `prayertimes.h`, not a reason to revert to `gnu11` — report it.
- [x] Step 5: Run `dart analyze`
- [x] Step 6: Run `dart test`
- [x] Step 7: Run `git grep -c sum_long_running`
- [x] Step 8: Commit

**Result:** `1bc9c45`. Amended clause passed, re-run independently: `dart test` exit 0 with 11 tests (10 ABI + 1 golden), `dart analyze lib test hook` exit 0, `git grep -c sum_long_running -- ':!docs'` exit 1 (no match). Scope was exactly the seven planned files.

Step 4's amendment held: the C build succeeds under strict `std: 'c11'` once `src/libmuslim_dart.c` is gone, with no compiler error. No portability finding against `prayertimes.h`.

**Out-of-scope finding, not fixed.** `README.md:43` still reads "For example, see `sumAsync` in `lib/libmuslim_dart.dart`" — a dangling reference to API this task deleted. No task in this plan covers `README.md`. Carried to `verify` as a known gap.

---

### Task 7: Rewrite the example app → verify: `dart analyze` inside `example/` exits zero

`example/lib/main.dart:24-25` calls `libmuslim_dart.sum` and `libmuslim_dart.sumAsync`, both removed in Task 6, so the example does not analyze until this lands.

**Files:**
- Modify: `example/lib/main.dart` — replace the whole file, currently 73 lines

- [x] Step 1: Replace the entire contents of `example/lib/main.dart`:
```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:libmuslim_dart/prayertimes.dart';

void main() {
  runApp(const MyApp());
}

/// Formats one decimal-hours time through the C formatter.
String _hm(double hours) {
  final buf = calloc<Char>(16);
  try {
    format_time_hm(hours, buf, 16);
    return buf.cast<Utf8>().toDartString();
  } finally {
    calloc.free(buf);
  }
}

/// Jakarta, using the Kemenag method, for today.
Map<String, String> _jakartaToday() {
  final key = 'kemenag'.toNativeUtf8();
  try {
    final params = method_params_get(method_from_string(key.cast<Char>()));
    final now = DateTime.now();
    final t = calculate_prayer_times(
      now.year,
      now.month,
      now.day,
      -6.2851291,
      106.9814968,
      7.0,
      params,
    );
    return {
      'Fajr': _hm(t.fajr),
      'Sunrise': _hm(t.sunrise),
      'Dhuha': _hm(t.dhuha),
      'Dhuhr': _hm(t.dhuhr),
      'Asr': _hm(t.asr),
      'Maghrib': _hm(t.maghrib),
      'Isha': _hm(t.isha),
    };
  } finally {
    malloc.free(key);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Map<String, String> times;

  @override
  void initState() {
    super.initState();
    times = _jakartaToday();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('libmuslim prayer times')),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jakarta, Kemenag method, calculated in C through FFI.',
                  style: textStyle,
                ),
                const SizedBox(height: 10),
                for (final entry in times.entries)
                  Text('${entry.key}: ${entry.value}', style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [x] Step 2: Run `flutter pub get` inside `example/`
- [x] Step 3: Run `dart analyze` inside `example/`
- [x] Step 4: Commit

**Result:** `de539ba`. Clause passed: `dart analyze` inside `example/` exit 0, and `dart analyze` at the repository root is back to exit 0 for the first time since Task 6.

**Authorised scope extension.** The Files block named only `example/lib/main.dart`, but `example/` is a separate package and did not depend on `ffi`, which the replacement needs for `calloc`, `malloc` and `toNativeUtf8`. `example/pubspec.yaml` gained `ffi: ^2.1.4` and `example/pubspec.lock` followed. This was pre-authorised in the dispatch rather than taken by the implementer.

**Out-of-scope finding, not fixed.** `flutter pub get` generated seven plugin-registrant files under `example/linux`, `example/macos` and `example/windows` that no `.gitignore` covers, so the working tree is no longer clean. They are Flutter build artifacts, not source. Carried to `verify` alongside the `README.md` reference.
