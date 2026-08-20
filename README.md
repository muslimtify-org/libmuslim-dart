# libmuslim_dart

Dart FFI bindings for [libmuslim](https://github.com/muslimtify-org), a
collection of stb-style single-header C libraries for Muslim applications.

Currently bound: `prayertimes.h` — prayer times for a date and location across
21 calculation methods.

## Usage

```dart
import 'package:libmuslim_dart/prayertimes.dart';

final times = PrayerTimes.today(
  latitude: -6.2851291,    // negative = South
  longitude: 106.9814968,  // positive = East
  utcOffset: const Duration(hours: 7),
  parameters: const CalculationParameters.of(CalculationMethod.kemenag),
);

print(times.fajr);          // a UTC instant
print(times.next());        // Prayer.dhuhr, say
print(times.timeUntilNext());
```

Every time is a UTC instant carrying whole minutes, rounded up to match the C
library's convention. Bad coordinates raise `ArgumentError`; a latitude where
the sun never reaches the required angle raises `PrayerTimesUnavailable`.

The FFI bindings underneath are not exported. They live in `lib/src/` because
their names, structs and failure modes come from C and change when the vendored
header changes.

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

## Platforms

Android, iOS, Linux, macOS and Windows. The C library is compiled from source
by `hook/build.dart`, so there is no web support.

## License

MIT. The vendored `src/prayertimes.h` is MIT as well, copyright
2025-2026 muslimtify-org. See [LICENSE](LICENSE).
