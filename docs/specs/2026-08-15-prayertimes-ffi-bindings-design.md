---
title: prayertimes raw FFI bindings
date: 2026-08-15
status: approved
---

# prayertimes raw FFI bindings — Design

## Problem

`libmuslim_dart` is currently the unmodified output of `flutter create
--template=plugin_ffi`: `src/libmuslim_dart.c` exposes `sum()` and
`sum_long_running()`, and `lib/libmuslim_dart.dart` wraps them. The real payload,
`src/prayertimes.h`, is vendored into the repo but nothing compiles it and
nothing binds it.

`prayertimes.h` is an stb-style single-header library: its implementation only
exists in a translation unit that defines `PRAYERTIMES_IMPLEMENTATION`. No such
TU exists in this package, so none of its symbols are in the built shared object.

`libmuslim` upstream is three independent single-header libraries —
`prayertimes.h`, `hijri.h`, `timezone.h` — not one. Whatever layout this change
establishes is inherited by the other two, so it has to be modular from the
start rather than retrofitted.

## Goals

Each goal states what must be observably true when the change is done.

1. `dart test` passes with `src/prayertimes.c` compiled into the package's shared
   object, proving `PRAYERTIMES_IMPLEMENTATION` is instantiated exactly once and
   the prayer-time symbols are linkable.
2. `lib/src/prayertimes/prayertimes_bindings_generated.dart` is produced by
   `dart run ffigen --config ffigen/prayertimes.yaml` and binds all five public
   functions (`format_time_hm`, `format_time_hms`, `method_params_get`,
   `method_from_string`, `method_to_string`, `calculate_prayer_times`), both
   structs and all four enums.
3. `dart run ffigen --config ffigen/prayertimes.yaml && git diff --exit-code
   lib/src/` exits zero on a clean tree — the committed bindings are not stale
   relative to the header.
4. `test/prayertimes_abi_test.dart` passes: struct sizes match `abi_sizeof_*()`,
   every field of `MethodParams` and `struct PrayerTimes` round-trips its
   sentinel value, the 13 `abi_constant_*` doubles match ffigen's emitted
   constants, and `abi_days_from_civil`/`abi_civil_from_days` round-trip.
5. `test/prayertimes_test.dart` passes the upstream README golden: 2025-11-21,
   latitude `-6.2851291`, longitude `106.9814968`, timezone `7.0`, method
   `kemenag` yields Fajr `04:05` through `format_time_hm`.
6. `src/libmuslim_dart.c` and `src/libmuslim_dart.h` no longer exist, and no
   `sum` or `sum_long_running` symbol remains anywhere in the package.
7. `dart run example/lib/main.dart`-equivalent (the Flutter example app) builds
   and displays prayer times rather than `sum(1, 2)`.
8. Adding a second module later requires only: a new `src/<module>.c`, a new
   `ffigen/<module>.yaml`, a new `lib/<module>.dart`, and one entry appended to
   `hook/build.dart`'s `sources` list. No existing file changes shape.

## Non-goals

- **Any idiomatic Dart API.** No Dart `enum`s, no `DateTime` conversion, no
  `PrayerTimes` value class, no named constructors. This change produces the raw
  generated bindings and a public entry point that re-exports them; the
  Flutter-convention layer is a separate brainstorm/plan/implementation cycle on
  top of `lib/prayertimes.dart`.
- **`hijri.h` and `timezone.h`.** Build order is prayertimes → hijri →
  timezone. Each gets its own cycle. This change only has to leave room for
  them.
- **Null-safety guards over the C API.** The raw layer adds no validation; see
  Constraints.
- **Publishing to pub.dev**, CHANGELOG or version bump.
- **Any modification to `src/prayertimes.h`.** It is vendored upstream code and
  stays byte-identical.

## Constraints

- `prayertimes.h` is vendored and must not be edited. Every accommodation
  happens on the Dart or wrapper-C side.
- `PRAYERTIMES_IMPLEMENTATION` must be defined in exactly one TU. Two would be a
  duplicate-symbol link error.
- The package builds via `hook/build.dart` and `native_toolchain_c`'s
  `CBuilder.library`, which produces **one** shared object. Every module's
  bindings must resolve against that single library.
- ffigen runs in `ffi-native` mode. Multiple generated files can share one
  library only by setting the same `ffi-native: {asset-id: ...}` in each config;
  ffigen 20.1.1 supports this (`config_types.dart:425`).
- `assetName` in `hook/build.dart` and `asset-id` in every ffigen config must be
  the same string. It is a library identity, not a filename.
- `prayertimes.h` needs libm; the build must link `-lm` on non-Windows targets.
- `dart:ffi` exposes `sizeOf<T>()` but **no `offsetOf` and no `alignOf`**. The
  Rust probe's field-offset and alignment comparisons cannot be ported
  literally; see Approach.
- `mt_days_from_civil` and `mt_civil_from_days` are `static inline` in the
  header. ffigen cannot bind them — they have no external linkage. They are
  reachable only through wrapper functions.
- `calculate_prayer_times` dereferences its `params` argument unconditionally.
  Passing `nullptr` from Dart segfaults the process: no exception, no stack
  trace. The raw layer documents this; guarding it belongs to the API layer.

## Approach

Chosen after four decision points with the user, recorded here with what was
rejected and why.

### Layout: one native library, one Dart entry point per module

Mirrors `~/Projects/libmuslim-rs`, which solved this same problem for Rust.

| libmuslim-rs | libmuslim_dart |
|---|---|
| `include/prayertimes.h` + `include/prayertimes.c` | `src/prayertimes.h` + `src/prayertimes.c` |
| `include/abi_probe.c` | `src/abi_probe.c` |
| `src/prayertimes/ffi.rs` (raw, `pub(crate)`) | `lib/src/prayertimes/prayertimes_bindings_generated.dart` (ffigen) |
| `src/prayertimes/mod.rs` (safe API) | `lib/src/prayertimes/prayertimes.dart` (later cycle) |
| `src/lib.rs` (module list only) | `lib/libmuslim_dart.dart` + `lib/prayertimes.dart` |
| `links = "prayertimes"`, one `cc` build | one `CBuilder.library`, one shared object |
| `docs/specs/`, `docs/plans/` | same |

`src/` rather than Rust's `include/`: it is where the Dart FFI plugin template
and the existing `hook/build.dart` already look, and the header is already
there.

Target file layout:

```
src/prayertimes.h                  vendored, unmodified
src/prayertimes.c                  #define PRAYERTIMES_IMPLEMENTATION
                                   #include "prayertimes.h"
src/abi_probe.c                    compiled into the same library
ffigen/prayertimes.yaml            one config per module
lib/src/prayertimes/prayertimes_bindings_generated.dart   generated, do not edit
lib/prayertimes.dart               public entry point; today re-exports bindings
lib/libmuslim_dart.dart            exports 'prayertimes.dart' (mirrors lib.rs)
hook/build.dart                    compiles the explicit source list
docs/specs/, docs/plans/
```

Deleted: `src/libmuslim_dart.c`, `src/libmuslim_dart.h`,
`test/libmuslim_dart_test.dart`.

`#include "prayertimes.h"` with quotes, not `<prayertimes.h>`: the header sits
beside `prayertimes.c`, so quoted include needs no `-I` and no build-hook
change.

`hook/build.dart`'s `sources` becomes an explicit list (`['src/prayertimes.c',
'src/abi_probe.c']`) rather than the template's `'src/$packageName.c'`. The
interpolated form names a file that will not exist, and would not extend to a
second module.

### Bind the header directly; no flattening shim

ffigen binds `struct PrayerTimes` returned by value and `const MethodParams *`
without help — both are fully supported by Dart FFI. A C shim flattening the API
into out-parameters would be code written to avoid a problem that does not
exist.

### ABI verification: `abi_probe.c`, with sentinel round-trip for offsets

Ported from `libmuslim-rs`. Kept unchanged from the Rust version:

- The `_Static_assert` block pinning all 22 `CalcMethod` values plus
  `AsrSchool`, `HighLatMethod` and `MidnightMode`. Compile-time, C-side, free —
  a header that renumbers `CALC_KEMENAG` fails the build.
- `abi_sizeof_method_params()` / `abi_sizeof_prayer_times()`, compared against
  Dart's `sizeOf<T>()`.
- The 13 `abi_constant_*` doubles, compared against ffigen's emitted constants.
- `abi_days_from_civil` / `abi_civil_from_days`, the only route to the two
  `static inline` helpers.

Changed for Dart, because `dart:ffi` has no `offsetOf` or `alignOf`: the
per-field `abi_offsetof_*` comparisons are replaced by a **sentinel
round-trip**. `abi_probe.c` fills a struct with distinct known values through
the C field names; the Dart test reads each field through the generated struct
and asserts the value.

```c
void abi_fill_method_params(MethodParams *out) {
  out->name = "probe"; out->fajr_angle = 11.0; out->isha_angle = 22.0;
  out->isha_interval = 33; out->maghrib_interval = 44; out->asr_shadow = 55;
  out->midnight_mode = MIDNIGHT_STANDARD; out->ihtiyat = 66;
}
```

```dart
expect(p.ref.ihtiyat, 66);   // wrong offset or wrong width -> wrong number
```

This catches every offset error, every field width error and any reordering, one
assertion per field. It does not catch trailing padding no field reads, which
the `abi_sizeof_*` check covers instead.

The probe symbols ship in the release library, as they do in `libmuslim-rs`.

### Staleness, which `abi_probe.c` only partly covers

The generated Dart is committed. Editing `src/prayertimes.h` without rerunning
ffigen leaves the committed bindings stale while `hook/build.dart` rebuilds the
shared object from the new header.

`abi_probe.c` catches the dangerous half of this on its own: it is compiled from
the edited header, so a changed struct size, a moved field or a changed constant
makes the ABI test fail against the stale generated Dart. What it cannot see is
staleness with no layout consequence — a function added, renamed or given a new
parameter — because the probe asserts nothing about the function set. The
regenerate-and-diff check covers that remainder and reports every kind of
staleness as one clear failure rather than as a surprising assertion:

```sh
dart run ffigen --config ffigen/prayertimes.yaml && git diff --exit-code lib/src/
```

### Ownership rules across the boundary

Three shapes of memory, three rules, all documented on `lib/prayertimes.dart`:

1. `method_params_get(CALC_KEMENAG)` → `Pointer<MethodParams>` into C static
   storage. Never freed, valid for process lifetime.
2. `calculate_prayer_times(...)` → `PrayerTimes` **by value**. Dart copies it out
   of the return registers; nothing to free.
3. `format_time_hm(hours, buf, len)` → writes into a buffer the Dart caller
   allocates and frees (`malloc<Char>(16)` / `malloc.free`).
   `MethodParams.name` and `method_to_string()` return `Pointer<Char>` into C
   static storage — read, never free.

`package:ffi` stays a dev-dependency: the generated bindings need only
`dart:ffi`, which is built in. It is promoted when the Dart API layer needs
`malloc`/`Utf8` at runtime.

### Error handling: none added

The raw layer documents C's behaviour rather than changing it.

- `method_params_get` returns `nullptr` for an out-of-range method; `.ref` on
  the result throws in Dart.
- `method_from_string` returns `CALC_CUSTOM` for null or unknown input. Never
  fails, silently falls back.
- `calculate_prayer_times` with `nullptr` params segfaults the process. This is
  the single most important thing the future API layer owes its callers, and is
  written into the entry point's doc comment now so it is not rediscovered
  later.
- No function reports failure for absurd coordinates; `lat=95.0` returns `NaN`s.

### User decisions recorded

- **Pushback** (offered): skip `abi_probe.c` entirely, since ffigen generates
  Dart structs *from* the header and the hand-written-drift failure mode Rust
  faces cannot occur; rely on the regenerate-and-diff check alone. **User chose
  the larger framing** — `abi_probe.c` is included. Both checks ship.
- Delete the `sum`/`sum_long_running` template rather than keeping it
  alongside.
- New `src/prayertimes.c` as the implementation TU rather than putting the two
  lines in `src/libmuslim_dart.c`.
- Raw bindings only in this cycle; Flutter-convention API built on top
  afterwards.

## Alternatives considered

**Flattening C shim** (`pt_calculate(..., struct PrayerTimes *out)`) so Dart
never touches `MethodParams` or struct-return. Rejected: Dart FFI supports both
natively, so the shim is maintenance for no gain.

**One ffigen config listing all three headers as entry-points**, output to a
single generated file. Rejected: no module boundary in Dart, one very large
generated file, and every consumer imports all three libraries including the
OS-coupled `timezone.h`.

**Separate packages per module** (`libmuslim_prayertimes`, `libmuslim_hijri`) in
a monorepo. Rejected: triples the build infrastructure — three pubspecs, three
build hooks, three native libraries — to isolate three dependency-free headers
that ship from one repo.

**Keeping the `sum` template alongside the new bindings.** Rejected: it would be
bound into the generated file and exported from the public API, shipping a
surface that will never be supported.

**Byte-scanning from Dart to recover field offsets**, reproducing the Rust
`offsetof` test literally. Rejected in favour of the sentinel round-trip, which
gives the same guarantee with materially less code.

**Building the full Dart API in this cycle.** Rejected: the user scoped this to
the FFI layer, and API decisions (enum naming, `DateTime` vs decimal hours,
error types) deserve their own design pass.

## Testing

`test/prayertimes_abi_test.dart` — four groups:

1. `sizeOf<MethodParams>()` and `sizeOf<PrayerTimes>()` against
   `abi_sizeof_method_params()` / `abi_sizeof_prayer_times()`.
2. Sentinel round-trip: every field of both structs, via
   `abi_fill_method_params` and `abi_fill_prayer_times`.
3. The 13 `abi_constant_*` doubles against ffigen's emitted constants.
4. `abi_days_from_civil` / `abi_civil_from_days` round-trip across a set of
   dates including a leap day and a pre-epoch date.

Enum values need no Dart test: the `_Static_assert` block fails the C build.

`test/prayertimes_test.dart` — the upstream README golden. 2025-11-21, latitude
`-6.2851291`, longitude `106.9814968`, timezone `7.0`, method `kemenag` →
Fajr `04:05` via `format_time_hm`. One case exercising the whole chain: enum →
`method_params_get` → struct-by-value return → buffer formatting. If
struct-by-value marshalling is wrong, this fails.

Regeneration check, run in CI and locally before commit:

```sh
dart run ffigen --config ffigen/prayertimes.yaml && git diff --exit-code lib/src/
```

`example/lib/main.dart` is rewritten to display Jakarta prayer times through the
raw bindings, replacing the `sum(1, 2)` demo. It is a manual check, not
automated.

## Open questions

None blocking. One item to resolve during planning rather than design: whether
`CBuilder.library` on this `native_toolchain_c` version needs `-lm` passed
explicitly via `flags`, or links libm by default on the Linux/Android toolchains.
Either way the fix is one line in `hook/build.dart`; it does not change any
interface above.
