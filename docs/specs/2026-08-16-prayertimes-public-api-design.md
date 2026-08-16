# prayertimes public Dart API — Design

**Status:** approved
**Supersedes nothing.** Builds on `docs/specs/2026-08-15-prayertimes-ffi-bindings-design.md`, whose raw binding layer stays exactly as it is.

## Problem

`lib/prayertimes.dart` currently re-exports the generated bindings verbatim. A
caller who wants Fajr in Jakarta must allocate a UTF-8 key, call
`method_from_string`, call `method_params_get`, pass the resulting pointer into
`calculate_prayer_times`, receive decimal-hour doubles, allocate a `Char` buffer,
call `format_time_hm`, decode it, and free two allocations — and if they get the
params pointer wrong the process segfaults with no Dart stack trace.

Two things are wrong with shipping that as the public surface:

1. It is not a Dart API. It is C spelled in Dart, with C naming
   (`calculate_prayer_times`), C failure modes (`NaN` for a bad latitude, a
   segfault for a null pointer) and C memory rules the caller must hold in their
   head.
2. Every symbol in it is a compatibility commitment. `MethodParams` and
   `PrayerTimes` are `ffi.Struct` views onto native memory; the 13 astronomy
   constants are implementation details of the C algorithm. Regenerating the
   bindings after an upstream header change silently changes the package's
   public API.

## Goals

1. A caller gets today's prayer times for a location in one expression, with no
   `dart:ffi` import, no allocation, and no `package:ffi` dependency.
2. The times are correct instants, comparable and arithmetic-safe, not decimal
   hours and not `DateTime`s that lie about their zone.
3. No FFI symbol is reachable from `package:libmuslim_dart/...`. The generated
   bindings stay under `lib/src/`, where the analyzer's `implementation_imports`
   lint stops external packages importing them.
4. The common case is one enum. The uncommon case — a custom angle, a Hanafi
   asr, a different ihtiyat — is reachable without dropping to FFI.
5. Every C failure mode becomes a Dart failure mode: a thrown error with a
   message naming what was wrong, never a segfault and never a silent `NaN`.
6. The published golden (Jakarta, 2025-11-21, Kemenag, Fajr `04:05`) still holds
   through the public API, not only through the raw layer.
7. The layout stays modular: adding `hijri.h` later adds `lib/hijri.dart` plus
   `lib/src/hijri/`, and changes nothing designed here.

## Non-goals

- Real timezones. See *Accepted breaking change* below.
- Qibla, hijri dates, or anything not in `prayertimes.h`.
- Any change to `src/`, `hook/build.dart`, `ffigen/`, or the generated file.
  This cycle adds a layer; it does not touch the one underneath.
- Widget or provider integration. This is a Dart package API; Flutter callers
  wire it into their own state management.

## Accepted breaking change

`utcOffset` is a fixed `Duration`. A fixed offset cannot express a real
timezone across a DST transition, and upstream libmuslim ships `timezone.h`
(IANA name → offset, DST applied) as a module intended to be bound later. When
that lands, callers will want `timezone: 'Asia/Jakarta'`.

This is accepted rather than designed around: the package is pre-1.0, and
designing a timezone abstraction now against a header that is not yet bound
would be speculation. One hedge is taken — the parameter is named `utcOffset`
and not `timezone`, so the timezone module can add a *separate* named parameter
additively rather than forcing a rename of this one.

## Design

### Files

| Path | Role |
| --- | --- |
| `lib/prayertimes.dart` | public entry point; exports only the hand-written API |
| `lib/src/prayertimes/prayer_times.dart` | `PrayerTimes`, `Prayer` |
| `lib/src/prayertimes/calculation_method.dart` | `CalculationMethod`, `AsrSchool`, `CalculationParameters` |
| `lib/src/prayertimes/prayer_times_unavailable.dart` | `PrayerTimesUnavailable` |
| `lib/src/prayertimes/prayertimes_bindings_generated.dart` | unchanged, no longer exported |

The generated `PrayerTimes` struct and the public `PrayerTimes` class share a
name. That is deliberate — the public one deserves the good name — and is
resolved by importing the bindings with a prefix (`as c`) in the two
implementation files that need them. Nothing else in the package imports them.

### The seven times

```dart
enum Prayer { fajr, sunrise, dhuha, dhuhr, asr, maghrib, isha }
```

`sunrise` and `dhuha` are members so `timeOf` can return them, but they are not
prayers: `current` and `next` skip both.

```dart
final class PrayerTimes {
  factory PrayerTimes.forDate(
    DateTime date, {
    required double latitude,
    required double longitude,
    required Duration utcOffset,
    CalculationParameters parameters,
  });

  factory PrayerTimes.today({
    required double latitude,
    required double longitude,
    required Duration utcOffset,
    CalculationParameters parameters,
  });

  final DateTime fajr, sunrise, dhuha, dhuhr, asr, maghrib, isha;

  DateTime timeOf(Prayer prayer);
  Prayer? current([DateTime? at]);
  Prayer? next([DateTime? at]);
  Duration? timeUntilNext([DateTime? at]);
}
```

Decisions embedded here, each with its reason:

- **The seven fields are `DateTime` in UTC.** A `DateTime` constructed in local
  time is wrong whenever the device's zone differs from the requested location —
  which is exactly the case a location-taking API exists to serve. A UTC instant
  is unambiguous, and `.toLocal()` is one call away when the caller genuinely
  wants device-local rendering.

- **Seconds and microseconds are always zero; times round *up* to the whole
  minute.** This is `format_time_hm`'s Kemenag convention, and the reason Goal 6
  is achievable: an un-rounded instant of 04:04:31 would render as `04:04` and
  contradict the library's own published `04:05`. Rounding is applied uniformly,
  including to `sunrise`, because that is what the C formatter does.

- **`date` is read for its year, month and day only**, in whatever zone the
  passed `DateTime` carries. The C function takes a civil date, not an instant.

- **`PrayerTimes.today` derives the civil date from `utcOffset`, not the
  device.** `DateTime.now().toUtc().add(utcOffset)` — so a caller in London
  asking for Jakarta gets Jakarta's today, not London's.

- **`current` and `next` are nullable.** Before Fajr, `current` is null; after
  Isha, `next` is null. The alternative — wrapping to the neighbouring day —
  would require computing a second day's times inside an accessor, and would
  return a time this object does not represent. Callers who want a rolling view
  construct the adjacent day themselves.

- **`at` defaults to `DateTime.now()`** and is compared as an instant, so a
  caller can pass any zone.

### Methods and parameters

```dart
enum AsrSchool { standard, hanafi }

enum CalculationMethod {
  mwl, makkah, isna, egypt, karachi, turkey, singapore, jakim, kemenag,
  france, russia, dubai, qatar, kuwait, jordan, gulf, tunisia, algeria,
  morocco, portugal, moonsighting;

  /// e.g. "KEMENAG, Indonesia" — read from the C table, not duplicated here.
  String get displayName;

  /// e.g. "kemenag" — the key `method_from_string` accepts.
  String get key;
}
```

`CALC_CUSTOM` and `CALC_COUNT` are deliberately absent. `COUNT` is a sentinel,
not a method. `CUSTOM` is not a method either — it is the C API's way of saying
"the caller supplied their own params", which in Dart is expressed by
constructing `CalculationParameters.custom` and needs no enum member.

`displayName` and `key` are read through `method_params_get(...).ref.name` and
`method_to_string` respectively, so the strings live in exactly one place: the C
table. Hand-copying 21 display names into Dart would be a second source of truth
that goes stale silently.

`HighLatMethod` is **not** exposed. It is bound as a Dart enum, but
`MethodParams` has no high-latitude field — the C `calculate_prayer_times`
takes no such argument and there is no way to select one. Exposing it would be
a lever wired to nothing.

`MidnightMode` is likewise not exposed: the struct carries it, but the header
defines exactly one value (`MIDNIGHT_STANDARD`), so a Dart enum with one member
is noise.

```dart
final class CalculationParameters {
  /// A published method, optionally with the two adjustments practitioners
  /// actually vary.
  const CalculationParameters.of(
    CalculationMethod method, {
    AsrSchool? asrSchool,
    int? ihtiyat,
  });

  /// Everything from scratch. Exactly one of [ishaAngle] and [ishaInterval].
  const CalculationParameters.custom({
    required double fajrAngle,
    double? ishaAngle,
    int? ishaInterval,
    int maghribInterval = 0,
    AsrSchool asrSchool = AsrSchool.standard,
    int ihtiyat = 0,
  });
}
```

The default is `CalculationParameters.of(CalculationMethod.mwl)` — MWL is the C
table's index 0 and the most widely applicable default.

**`ishaAngle` / `ishaInterval` are mutually exclusive and both nullable, rather
than one field with a magic zero.** In C, `isha_angle = 0` means "use the
interval instead" — a caller who passes an isha angle of literally zero
silently switches modes. Requiring exactly one, and throwing `ArgumentError`
otherwise, makes the mode explicit and the mistake impossible.

`asrSchool` maps to `asr_shadow`: `standard` → 1, `hanafi` → 2. The C field is
a raw shadow factor; the enum names what the numbers mean.

### Memory

`method_params_get` returns a pointer into **C static storage**, shared by every
caller for the process lifetime. Mutating what it returns would corrupt the
method table for the whole program.

So:

- `CalculationParameters.of(method)` with **no** overrides passes the C pointer
  through untouched. No allocation.
- Any override, and every `.custom`, allocates a fresh `MethodParams` with
  `calloc`, copies the table entry in (or fills it from scratch), applies the
  overrides, calls, and frees in a `finally`. The C table is never written to.

This is the whole of the package's manual memory management, and it lives in one
private function.

### Failures

| Condition | Result |
| --- | --- |
| latitude outside −90..90, longitude outside −180..180 | `ArgumentError` |
| any non-finite `double` argument | `ArgumentError` |
| `utcOffset` outside −18h..+18h | `ArgumentError` |
| neither or both of `ishaAngle` / `ishaInterval` | `ArgumentError` |
| `fajrAngle` or `ishaAngle` outside 0..90, negative interval or ihtiyat | `ArgumentError` |
| any computed time non-finite | `PrayerTimesUnavailable` |

```dart
final class PrayerTimesUnavailable implements Exception {
  final List<Prayer> prayers;   // which came back non-finite
  final double latitude;
  final double longitude;
  final DateTime date;
}
```

Its `toString` names the affected prayers and the latitude, because the
overwhelmingly common cause is a high-latitude location where the sun never
reaches the required depression angle — and the C library's high-latitude
fallbacks are, per the previous cycle's record, never exercised. A message that
says "no Fajr at latitude 68.5" tells the caller what to do; a bare `NaN` does
not.

Validating the arguments also closes the null-`params` segfault by
construction: the caller never supplies a pointer, and the one code path that
builds one cannot produce null.

### What stops being public

`format_time_hm`, `format_time_hms`, `method_params_get`, `method_from_string`,
`method_to_string`, `calculate_prayer_times`, `CalcMethod`, `AsrSchool` (the C
one), `HighLatMethod`, `MidnightMode`, `MethodParams`, the `PrayerTimes` struct,
and all 13 astronomy constants. None is re-exported; all remain in `lib/src/`.

There is **no escape hatch**. A caller who needs the raw layer is a caller whose
use case belongs in this API instead.

### Call-site migration

Three files depend on the current surface and all three must move:

- `test/prayertimes_test.dart` — the Jakarta golden moves to the public API and
  asserts an instant, satisfying Goal 6.
- `test/prayertimes_abi_test.dart` — it declares its own `@Native` probe symbols
  and only needs the generated file for the struct types. It imports
  `package:libmuslim_dart/src/prayertimes/prayertimes_bindings_generated.dart`
  directly, which is legal within the package and is what `lib/src` is for.
- `example/lib/main.dart` — rewritten to the public API, dropping its
  `dart:ffi` and `package:ffi` imports entirely. It keeps rendering
  `"<Name>: HH:MM"` rows, so `example/test/widget_test.dart` stays valid
  unchanged and continues to measure that real times reach the screen.

`example/pubspec.yaml`'s `ffi` dependency becomes unused and is removed — an
example that still needs `package:ffi` would be evidence Goal 1 failed.

## Verification

Each goal, and how it is observed:

1. **One expression, no ffi.** `git grep -n "dart:ffi\|package:ffi" -- example/`
   reports no match, and `example/lib/main.dart` obtains its times in a single
   `PrayerTimes.today(...)` call.
2. **Correct instants.** A test asserts every returned field `isUtc`, has
   `second == 0` and `microsecond == 0`, and that `fajr.isBefore(sunrise)`
   through to `maghrib.isBefore(isha)`.
3. **FFI unreachable.** Two observations, both mechanical:
   `git grep -n "^export .*src/" -- 'lib/*.dart'` reports no match (no top-level
   library re-exports anything under `src/`), and a file that imports **only**
   `package:libmuslim_dart/prayertimes.dart` and references
   `calculate_prayer_times` fails to analyze. The second is checked by
   `dart analyze` on a throwaway file rather than committed, since a committed
   file that must fail analysis would break the repo-wide `dart analyze` gate.
4. **Common and uncommon cases.** Tests cover `PrayerTimes.today` with only the
   three required arguments; `.of(kemenag, asrSchool: hanafi)` producing a
   *different* asr than standard; and `.custom` producing times at all.
5. **Failures are Dart failures.** Tests assert `ArgumentError` for latitude 95,
   for a non-finite longitude, and for `.custom` with both/neither isha field.
6. **Golden holds.** `PrayerTimes.forDate(DateTime.utc(2025, 11, 21), latitude:
   -6.2851291, longitude: 106.9814968, utcOffset: Duration(hours: 7),
   parameters: CalculationParameters.of(CalculationMethod.kemenag))` yields a
   `fajr` equal to `DateTime.utc(2025, 11, 20, 21, 5)` — 04:05 at +07:00.
7. **Modularity.** Unobservable without adding a second module; deferred to the
   hijri cycle exactly as Goal 8 of the previous spec was.

Whole-change gates: `dart test` exit 0, `dart analyze` exit 0, `flutter test`
in `example/` exit 0, `flutter build linux` exit 0, and
`env -u CPATH dart run tool/regen.dart && git diff --exit-code lib/src/`
exit 0 — the last proving this cycle did not hand-edit generated code.

## Risks

- **`displayName` reads a C pointer on every access.** Cheap, but it means the
  enum getters touch FFI. Accepted: the alternative is a stale hand-copied
  table.
- **Rounding up is the C convention, not universally the right one.** Rounding
  sunrise *up* moves it later, which for a "don't pray after sunrise" reading is
  the unsafe direction. Following C is chosen over silently diverging from the
  library this package binds; a caller needing exact instants is a future
  request, not a guess made now.
- **Only Kemenag is ever calculated against a published golden.** Inherited from
  the previous cycle and not fixed here: the Hanafi asr test asserts only that
  the value *differs*, not that it matches an authority.
- **The three inherited risks stand** — untested interval-based Isha, unexercised
  high-latitude fallbacks, and ABI verified on x86-64 Linux only.
