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

## Flutter help

For help getting started with Flutter, view our
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
