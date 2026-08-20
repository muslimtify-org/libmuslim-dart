# libmuslim

[![pub package](https://img.shields.io/pub/v/libmuslim.svg)](https://pub.dev/packages/libmuslim)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Dart FFI bindings for [libmuslim](https://github.com/muslimtify-org), a
collection of stb-style single-header C libraries for Muslim applications.

Currently bound: `prayertimes.h`, giving prayer times for a date and location
across 21 published calculation methods.

## Installation

```sh
dart pub add libmuslim
```

```sh
flutter pub add libmuslim
```

Either command adds the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  libmuslim: ^0.1.0
```

Then import the module you want. There is no separate initialisation step:

```dart
import 'package:libmuslim/prayertimes.dart';
```

### Requirements

The C library is compiled from source when your project builds, so there is
nothing to download and no prebuilt binary to match against your platform.
That does mean a C toolchain has to be present:

* **Dart SDK 3.12.2 or newer.** The build hook uses the stable `hooks` and
  `code_assets` APIs.
* **A host C compiler** for command-line and desktop targets: clang or gcc on
  Linux and macOS, MSVC on Windows.
* **Nothing extra for Flutter mobile targets.** The Android NDK and Xcode
  toolchains already ship with the platform SDKs.

On Flutter 3.44 and newer, native assets are enabled by default. On an older
Flutter you need to turn them on once:

```sh
flutter config --enable-native-assets
```

## Usage

### Today's times

```dart
import 'package:libmuslim/prayertimes.dart';

final times = PrayerTimes.today(
  latitude: -6.2851291,    // negative = South
  longitude: 106.9814968,  // positive = East
  utcOffset: const Duration(hours: 7),
  parameters: const CalculationParameters.of(CalculationMethod.kemenag),
);

print(times.fajr);     // 2026-08-19 21:42:00.000Z
print(times.dhuhr);    // 2026-08-20 04:58:00.000Z
print(times.asr);      // 2026-08-20 08:19:00.000Z
print(times.maghrib);  // 2026-08-20 10:56:00.000Z
print(times.isha);     // 2026-08-20 12:06:00.000Z
```

`utcOffset` is the offset of the **location you are asking about**, not the
device's. A caller in London asking about Jakarta passes `Duration(hours: 7)`
and gets Jakarta's today. `PrayerTimes` never reads the device clock's zone,
because the device and the location are unrelated.

`parameters` is optional and defaults to `CalculationMethod.mwl`.

### Every time is a UTC instant

Times carry whole minutes, rounded up, matching the C library's convention.
Call `toLocal()` when you want to render in the device's zone:

```dart
print(times.maghrib);            // 2026-08-20 10:56:00.000Z
print(times.maghrib.toLocal());  // whatever that instant is where you are
```

### Iterating the prayers

`Prayer` is exactly the five prescribed prayers, and `timeOf` maps one to its
time:

```dart
for (final prayer in Prayer.values) {
  print('${prayer.name}: ${times.timeOf(prayer)}');
}
// fajr: 2026-08-19 21:42:00.000Z
// dhuhr: 2026-08-20 04:58:00.000Z
// ...
```

### What is next

```dart
times.current();        // Prayer.fajr, the window we are in, or null before Fajr
times.next();           // Prayer.dhuhr, or null once Isha has passed
times.timeUntilNext();  // 0:33:30.036154, or null once Isha has passed
```

All three take an optional instant, so they are testable without waiting:

```dart
times.next(DateTime.utc(2026, 8, 20, 9));  // Prayer.maghrib
```

Each object holds one civil day. `current` and `next` return null past Isha
rather than reaching into tomorrow; build the next day's object for that.

### A specific date

```dart
final times = PrayerTimes.forDate(
  DateTime(2026, 12, 25),
  latitude: 21.4225,
  longitude: 39.8262,
  utcOffset: const Duration(hours: 3),
  parameters: const CalculationParameters.of(CalculationMethod.makkah),
);
```

Only the year, month and day of the `DateTime` are read, so the zone it
carries does not matter.

### Choosing a method

All 21 members of `CalculationMethod` carry the authority's own naming, read
from the C table rather than duplicated in Dart:

```dart
for (final method in CalculationMethod.values) {
  print('${method.key}: ${method.displayName}');
}
// mwl: Muslim World League
// makkah: Umm al-Qura, Makkah
// kemenag: KEMENAG, Indonesia
// ...
```

Two adjustments that practitioners actually vary can be layered onto a
published method without leaving it:

```dart
const CalculationParameters.of(
  CalculationMethod.karachi,
  asrSchool: AsrSchool.hanafi,  // shadow twice the object's length
  ihtiyat: 2,                   // precautionary minutes added to each time
);
```

For a timetable no published method describes, build one from scratch. Exactly
one of `ishaAngle` and `ishaInterval` must be given, because in C an isha angle
of zero silently means "use the interval instead":

```dart
CalculationParameters.custom(
  fajrAngle: 18.0,
  ishaInterval: 90,  // minutes after Maghrib, instead of an angle
  asrSchool: AsrSchool.hanafi,
  ihtiyat: 2,
);
```

### High latitudes

At high latitude the sun may never reach the depression angle a method
asks for, so Fajr and Isha have no true solution. Each method carries its
authority's own substitution rule, which is what you get by default. Override
it only when serving a location the chosen authority is silent about:

```dart
const CalculationParameters.of(
  CalculationMethod.mwl,
  highLatitudeRule: HighLatitudeRule.oneSeventh,
  highLatitudeReferenceLatitude: 45.0,
);
```

`HighLatitudeRule.none` disables substitution, which makes the impossible case
observable rather than silently approximated.

### Handling failure

Bad input throws `ArgumentError`. A time that genuinely does not exist throws
`PrayerTimesUnavailable`, which names the affected prayers so you can tell the
two apart:

```dart
try {
  PrayerTimes.forDate(
    DateTime(2026, 6, 21),
    latitude: 64.1466,   // Reykjavik, midsummer
    longitude: -21.9426,
    utcOffset: const Duration(hours: 0),
    parameters: const CalculationParameters.of(
      CalculationMethod.mwl,
      highLatitudeRule: HighLatitudeRule.none,
    ),
  );
} on PrayerTimesUnavailable catch (e) {
  print(e.prayers);  // [Prayer.fajr, Prayer.isha]
  print(e);          // PrayerTimesUnavailable: no fajr, isha on 2026-06-21 at
                     // latitude 64.1466, longitude -21.9426
}
```

The same call without `highLatitudeRule: none` succeeds, because MWL's own
substitution rule then applies. The exception is all-or-nothing for the day: if
any prayer is unavailable, no `PrayerTimes` is returned.

## Platform support

| Platform | Supported | Minimum |
| -------- | --------- | ------- |
| Android  | yes       | Flutter's minimum SDK |
| iOS      | yes       | Flutter's minimum version |
| Linux    | yes       | clang or gcc on the host |
| macOS    | yes       | Xcode command line tools |
| Windows  | yes       | MSVC |
| Web      | no        | there is no C runtime to compile into |

The C sources are compiled per target by `hook/build.dart`, which is why the
list follows whatever `native_toolchain_c` can drive rather than a set of
binaries shipped in the package.

One caveat worth stating plainly: this repository has no CI matrix yet, and
Linux x64 is the only target the test suite has actually been run on. The other
four are supported by the build hook rather than verified on hardware.

## API summary

| Type | Purpose |
| ---- | ------- |
| `PrayerTimes` | One civil day at one location. `today`, `forDate`, `timeOf`, `current`, `next`, `timeUntilNext` |
| `Prayer` | The five prescribed prayers: `fajr`, `dhuhr`, `asr`, `maghrib`, `isha` |
| `CalculationMethod` | 21 published methods, each with `key` and `displayName` |
| `CalculationParameters` | `of` for a published method, `custom` for your own |
| `AsrSchool` | `standard` or `hanafi` |
| `HighLatitudeRule` | Substitution when the sun never reaches the angle |
| `PrayerTimesUnavailable` | Thrown when a time has no solution |

The FFI bindings underneath are not exported. They live in `lib/src/` because
their names, structs and failure modes come from C and change when the vendored
header changes.

## Project structure

Each module is one vendored header, one translation unit that instantiates it,
one ffigen config, and one public entry point.

* `src/` holds the vendored single-header libraries and the `.c` files that
  define their `*_IMPLEMENTATION` macro, plus `abi_probe.c`, which exports the
  header's own `sizeof` and constants so the tests can verify the Dart structs
  against the compiled C.

* `ffigen/` holds one config per module. Paths inside are relative to this
  directory, and every config pins the same `asset-id` so all generated files
  resolve against the single shared library.

* `lib/<module>.dart` is the public entry point per module.
  `lib/src/<module>/` holds its generated bindings, which are never hand-edited.

* `hook/build.dart` compiles every listed `.c` into one shared library.

## Regenerating the bindings

```sh
dart run tool/regen.dart
```

This runs every config in `ffigen/`. Do not invoke `ffigen` directly unless
`CPATH` already points at clang's resource include directory, because libclang
does not always find it and the failure surfaces as a missing `stddef.h`.

## Testing

```sh
dart test              # ABI verification and a published golden
cd example && flutter test
```

## License

MIT. The vendored `src/prayertimes.h` is MIT as well, copyright
2025-2026 muslimtify-org. See [LICENSE](LICENSE).
