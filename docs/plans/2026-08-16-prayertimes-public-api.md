# prayertimes public Dart API — Implementation Plan

**Spec:** docs/specs/2026-08-16-prayertimes-public-api-design.md
**Goal:** Replace the raw-bindings public surface with a hand-written Dart API — `PrayerTimes.today` / `.forDate` returning UTC instants, a `CalculationMethod` enum, `CalculationParameters` for overrides — and seal the FFI layer inside `lib/src/`.
**Architecture:** Four new files under `lib/src/prayertimes/` hold the prayer enum, the failure type, the method catalogue and the calculation entry point. They import the generated bindings with the prefix `c`, so the public `PrayerTimes` class and the generated `PrayerTimes` struct coexist. `lib/prayertimes.dart` narrows from re-exporting the generated file to exporting only those four. The task order keeps `dart analyze` green at every commit: the new API is added and exported alongside the old surface first, and the old surface is removed only in the task that migrates its last three call sites.

## Global constraints

- `src/prayertimes.h`, `src/prayertimes.c`, `src/abi_probe.c`, `hook/build.dart`, `ffigen/prayertimes.yaml` and `lib/src/prayertimes/prayertimes_bindings_generated.dart` are not edited by any task here. This cycle adds a layer above them.
- The generated bindings are never hand-edited; `dart run tool/regen.dart` must leave the tree clean.
- Nothing under `lib/src/` may be re-exported from a top-level `lib/*.dart` file. There is no escape hatch to the FFI layer.
- The pointer `method_params_get` returns is C static storage shared process-wide. It is read and passed through; it is never written to.
- `HighLatMethod`, `MidnightMode` and the 13 astronomy constants are not part of the public API. `CalcMethod.CALC_CUSTOM` and `CalcMethod.CALC_COUNT` have no `CalculationMethod` counterpart.
- Spec Goal 7 (modularity — adding `hijri.h` changes nothing here) has no task. It cannot be observed without adding a second module, exactly as Goal 8 of the previous spec could not; the spec defers it to the hijri cycle. No task attempts to fake an observation of it.
- Observed toolchain, read from `pubspec.yaml` and `example/pubspec.yaml`: Dart SDK `^3.12.2`, `ffi: ^2.1.4`, `ffigen: ^20.1.1`, `test: ^1.28.0`, `flutter_lints: ^6.0.0`, and `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`.
- `parameters` is a non-nullable named argument whose default is `const CalculationParameters.of(CalculationMethod.mwl)`. A const constructor cannot throw, so `.of`'s validation happens where its values are consumed, while `.custom` is a non-const constructor that validates eagerly. Both raise `ArgumentError`, as the spec requires; only the timing differs.

---

### Task 1: Value types and the method catalogue → verify: `dart analyze lib test` exits zero and `dart test test/calculation_method_test.dart` exits zero

This task creates everything except the calculation itself: the prayer enum, the asr school, the method catalogue that reads its strings from the C table, the parameters class, and the failure type. Nothing is exported from `lib/prayertimes.dart` yet, so the existing public surface and its three call sites are untouched and keep compiling.

`package:ffi` moves from `dev_dependencies` to `dependencies` because `lib/` code now uses `Utf8` and `calloc` at runtime.

**Files:**
- Modify: `pubspec.yaml` — move the `ffi` entry from `dev_dependencies` to `dependencies`
- Create: `lib/src/prayertimes/prayer.dart`
- Create: `lib/src/prayertimes/prayer_times_unavailable.dart`
- Create: `lib/src/prayertimes/calculation_method.dart`
- Create: `test/calculation_method_test.dart`

- [x] Step 1: In `pubspec.yaml`, delete the line `  ffi: ^2.1.4` from the `dev_dependencies` block and add `  ffi: ^2.1.4` to the `dependencies` block, keeping that block alphabetically ordered so it reads `code_assets`, `ffi`, `hooks`, `logging`, `native_toolchain_c`.

- [x] Step 2: Create `lib/src/prayertimes/prayer.dart`:
```dart
/// One of the times `PrayerTimes` reports.
///
/// [sunrise] and [dhuha] are members so `PrayerTimes.timeOf` can return them,
/// but they are not prayers: `PrayerTimes.current` and `PrayerTimes.next` skip
/// both.
///
/// This lives in its own file because `PrayerTimesUnavailable` names it and is
/// created before `PrayerTimes` is.
enum Prayer { fajr, sunrise, dhuha, dhuhr, asr, maghrib, isha }
```

- [x] Step 3: Create `lib/src/prayertimes/prayer_times_unavailable.dart`:
```dart
import 'prayer.dart';

/// Thrown when the C library cannot produce a finite time for one or more
/// prayers on the requested date and location.
///
/// The overwhelmingly common cause is a high-latitude location where the sun
/// never reaches the depression angle the method requires — in high summer
/// there is no true Fajr in Tromsø, and no arithmetic can invent one. The
/// exception names the affected prayers and the latitude so a caller can tell
/// that apart from a bad argument, which throws [ArgumentError] instead.
final class PrayerTimesUnavailable implements Exception {
  PrayerTimesUnavailable({
    required this.prayers,
    required this.latitude,
    required this.longitude,
    required this.date,
  });

  /// The prayers the C library returned a non-finite time for.
  final List<Prayer> prayers;

  final double latitude;
  final double longitude;

  /// The civil date the calculation was requested for.
  final DateTime date;

  @override
  String toString() {
    final names = prayers.map((p) => p.name).join(', ');
    final day =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return 'PrayerTimesUnavailable: no $names on $day at latitude '
        '$latitude, longitude $longitude';
  }
}
```

- [x] Step 4: Create `lib/src/prayertimes/calculation_method.dart`:
```dart
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'prayertimes_bindings_generated.dart' as c;

/// Which shadow length marks the start of Asr.
enum AsrSchool {
  /// Asr begins when an object's shadow equals its own length. Every method in
  /// the C table uses this unless a caller overrides it.
  standard(1),

  /// Asr begins when an object's shadow is twice its own length.
  hanafi(2);

  const AsrSchool(this._shadowFactor);

  final int _shadowFactor;
}

/// A published prayer-time calculation method.
///
/// The C library's `CALC_CUSTOM` and `CALC_COUNT` have no member here.
/// `COUNT` is a sentinel rather than a method, and a custom method is
/// expressed by [CalculationParameters.custom] rather than by an enum value.
enum CalculationMethod {
  mwl(c.CalcMethod.CALC_MWL),
  makkah(c.CalcMethod.CALC_MAKKAH),
  isna(c.CalcMethod.CALC_ISNA),
  egypt(c.CalcMethod.CALC_EGYPT),
  karachi(c.CalcMethod.CALC_KARACHI),
  turkey(c.CalcMethod.CALC_TURKEY),
  singapore(c.CalcMethod.CALC_SINGAPORE),
  jakim(c.CalcMethod.CALC_JAKIM),
  kemenag(c.CalcMethod.CALC_KEMENAG),
  france(c.CalcMethod.CALC_FRANCE),
  russia(c.CalcMethod.CALC_RUSSIA),
  dubai(c.CalcMethod.CALC_DUBAI),
  qatar(c.CalcMethod.CALC_QATAR),
  kuwait(c.CalcMethod.CALC_KUWAIT),
  jordan(c.CalcMethod.CALC_JORDAN),
  gulf(c.CalcMethod.CALC_GULF),
  tunisia(c.CalcMethod.CALC_TUNISIA),
  algeria(c.CalcMethod.CALC_ALGERIA),
  morocco(c.CalcMethod.CALC_MOROCCO),
  portugal(c.CalcMethod.CALC_PORTUGAL),
  moonsighting(c.CalcMethod.CALC_MOONSIGHTING);

  const CalculationMethod(this._native);

  final c.CalcMethod _native;

  /// The method's full name, for example `KEMENAG, Indonesia`.
  ///
  /// Read from the C table on each access rather than duplicated here, so
  /// there is exactly one source of truth for these strings.
  String get displayName =>
      _table(this).ref.name.cast<Utf8>().toDartString();

  /// The method's short key, for example `kemenag`.
  String get key =>
      c.method_to_string(_native).cast<Utf8>().toDartString();
}

/// The parameter set a calculation runs with.
final class CalculationParameters {
  /// A published [method], optionally with the two adjustments practitioners
  /// actually vary.
  ///
  /// Leaving both overrides null passes the C library's own parameter table
  /// through untouched, with no allocation.
  const CalculationParameters.of(
    CalculationMethod method, {
    AsrSchool? asrSchool,
    int? ihtiyat,
  }) : _method = method,
       _asrSchool = asrSchool,
       _ihtiyat = ihtiyat,
       _fajrAngle = null,
       _ishaAngle = null,
       _ishaInterval = null,
       _maghribInterval = 0;

  /// A method built from scratch.
  ///
  /// Exactly one of [ishaAngle] and [ishaInterval] must be given. In C an
  /// `isha_angle` of zero silently means "use the interval instead", so a
  /// caller who passed a literal zero angle would switch modes without
  /// noticing; requiring exactly one makes the choice explicit.
  CalculationParameters.custom({
    required double fajrAngle,
    double? ishaAngle,
    int? ishaInterval,
    int maghribInterval = 0,
    AsrSchool asrSchool = AsrSchool.standard,
    int ihtiyat = 0,
  }) : _method = null,
       _fajrAngle = fajrAngle,
       _ishaAngle = ishaAngle,
       _ishaInterval = ishaInterval,
       _maghribInterval = maghribInterval,
       _asrSchool = asrSchool,
       _ihtiyat = ihtiyat {
    if ((ishaAngle == null) == (ishaInterval == null)) {
      throw ArgumentError(
        'give exactly one of ishaAngle and ishaInterval, not '
        '${ishaAngle == null ? 'neither' : 'both'}',
      );
    }
    checkAngle(fajrAngle, 'fajrAngle');
    if (ishaAngle != null) checkAngle(ishaAngle, 'ishaAngle');
    if (ishaInterval != null) {
      checkNonNegative(ishaInterval, 'ishaInterval');
    }
    checkNonNegative(maghribInterval, 'maghribInterval');
    checkNonNegative(ihtiyat, 'ihtiyat');
  }

  final CalculationMethod? _method;
  final AsrSchool? _asrSchool;
  final int? _ihtiyat;
  final double? _fajrAngle;
  final double? _ishaAngle;
  final int? _ishaInterval;
  final int _maghribInterval;
}

/// Throws [ArgumentError] unless [value] is a finite angle in 0..90 degrees.
void checkAngle(double value, String name) {
  if (!value.isFinite || value < 0 || value > 90) {
    throw ArgumentError.value(
      value,
      name,
      'must be a finite angle between 0 and 90 degrees',
    );
  }
}

/// Throws [ArgumentError] unless [value] is zero or more.
void checkNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

ffi.Pointer<c.MethodParams> _table(CalculationMethod method) {
  final params = c.method_params_get(method._native);
  if (params == ffi.nullptr) {
    throw StateError(
      'the C method table has no entry for ${method.name}; the generated '
      'bindings and the compiled library are out of step',
    );
  }
  return params;
}

/// Calls [body] with a `MethodParams` matching [parameters].
///
/// When [CalculationParameters.of] carries no overrides this hands over the
/// pointer C already owns and allocates nothing. Every other case copies into
/// a fresh allocation and frees it before returning, because the pointer
/// `method_params_get` returns is static storage shared by the whole process:
/// writing to it would corrupt the method table for every later caller.
T withNativeParams<T>(
  CalculationParameters parameters,
  T Function(ffi.Pointer<c.MethodParams>) body,
) {
  final method = parameters._method;
  final asrSchool = parameters._asrSchool;
  final ihtiyat = parameters._ihtiyat;

  if (method != null) {
    final table = _table(method);
    if (asrSchool == null && ihtiyat == null) return body(table);
    if (ihtiyat != null) checkNonNegative(ihtiyat, 'ihtiyat');

    final copy = calloc<c.MethodParams>();
    try {
      copy.ref
        ..name = table.ref.name
        ..fajr_angle = table.ref.fajr_angle
        ..isha_angle = table.ref.isha_angle
        ..isha_interval = table.ref.isha_interval
        ..maghrib_interval = table.ref.maghrib_interval
        ..asr_shadow = asrSchool?._shadowFactor ?? table.ref.asr_shadow
        ..midnight_modeAsInt = table.ref.midnight_modeAsInt
        ..ihtiyat = ihtiyat ?? table.ref.ihtiyat;
      return body(copy);
    } finally {
      calloc.free(copy);
    }
  }

  final custom = c.method_params_get(c.CalcMethod.CALC_CUSTOM);
  final copy = calloc<c.MethodParams>();
  try {
    copy.ref
      ..name = custom.ref.name
      ..fajr_angle = parameters._fajrAngle!
      ..isha_angle = parameters._ishaAngle ?? 0.0
      ..isha_interval = parameters._ishaInterval ?? 0
      ..maghrib_interval = parameters._maghribInterval
      ..asr_shadow = asrSchool!._shadowFactor
      ..midnight_modeAsInt = c.MidnightMode.MIDNIGHT_STANDARD.value
      ..ihtiyat = ihtiyat!;
    return body(copy);
  } finally {
    calloc.free(copy);
  }
}
```

- [x] Step 5: Create `test/calculation_method_test.dart`:
```dart
import 'package:test/test.dart';

import 'package:libmuslim_dart/src/prayertimes/calculation_method.dart';

void main() {
  group('CalculationMethod', () {
    test('reads its display name and key from the C table', () {
      expect(CalculationMethod.kemenag.displayName, 'KEMENAG, Indonesia');
      expect(CalculationMethod.kemenag.key, 'kemenag');
      expect(CalculationMethod.mwl.displayName, 'Muslim World League');
    });

    test('every member resolves to a non-empty name and key', () {
      for (final method in CalculationMethod.values) {
        expect(method.displayName, isNotEmpty, reason: method.name);
        expect(method.key, isNotEmpty, reason: method.name);
      }
    });

    test('keys are distinct, so no two members alias the same C entry', () {
      final keys = CalculationMethod.values.map((m) => m.key).toSet();
      expect(keys, hasLength(CalculationMethod.values.length));
    });
  });

  group('CalculationParameters.custom', () {
    test('rejects neither isha angle nor interval', () {
      expect(
        () => CalculationParameters.custom(fajrAngle: 18),
        throwsArgumentError,
      );
    });

    test('rejects both isha angle and interval', () {
      expect(
        () => CalculationParameters.custom(
          fajrAngle: 18,
          ishaAngle: 17,
          ishaInterval: 90,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an out-of-range or non-finite angle', () {
      expect(
        () => CalculationParameters.custom(fajrAngle: 95, ishaAngle: 17),
        throwsArgumentError,
      );
      expect(
        () =>
            CalculationParameters.custom(fajrAngle: double.nan, ishaAngle: 17),
        throwsArgumentError,
      );
    });

    test('rejects a negative interval or ihtiyat', () {
      expect(
        () =>
            CalculationParameters.custom(fajrAngle: 18, ishaInterval: -1),
        throwsArgumentError,
      );
      expect(
        () => CalculationParameters.custom(
          fajrAngle: 18,
          ishaAngle: 17,
          ihtiyat: -1,
        ),
        throwsArgumentError,
      );
    });

    test('accepts exactly one isha mode', () {
      expect(
        CalculationParameters.custom(fajrAngle: 18, ishaAngle: 17),
        isA<CalculationParameters>(),
      );
      expect(
        CalculationParameters.custom(fajrAngle: 18, ishaInterval: 90),
        isA<CalculationParameters>(),
      );
    });
  });
}
```

- [x] Step 6: Run `dart pub get`
- [x] Step 7: Run `dart test test/calculation_method_test.dart`
- [x] Step 8: Run `dart analyze lib test`
- [x] Step 9: Commit

**Result:** `cf09368`. Clause passed, re-run independently: `dart analyze lib test` exit 0, `dart test test/calculation_method_test.dart` exit 0. Scope was exactly the five planned files. No deviation from the amended brief.

Recorded, not repaired: `dart analyze` now reports three `prefer_initializing_formals` infos against `CalculationParameters`. They are false positives — an initializing formal cannot give a public parameter name to a private field — but they leave the analyzer no longer silent, which the previous cycle's history shows this repo treats as worth suppressing with a stated reason.

---

### Task 2: The `PrayerTimes` value class → verify: `dart analyze lib test` exits zero and `dart test` exits zero

This task adds the calculation itself and starts exporting the new API. `lib/prayertimes.dart` gains the four new exports while **keeping** the generated export, so the remaining call sites still compile and Task 3 can remove it in the same commit that migrates them.

Two names have to be got out of the way first. The generated file declares its own `AsrSchool` and its own `PrayerTimes` struct, so exporting it alongside the new API makes both names ambiguous and `lib/prayertimes.dart` stops compiling — an error at the export directive, whether or not anything references them. The transitional export therefore carries a `hide` clause, which Task 3 deletes along with the whole line. `test/prayertimes_abi_test.dart` is the one file that genuinely needs the hidden `PrayerTimes` struct, so its import moves to `lib/src/` here rather than in Task 3.

The decimal-hours-to-instant conversion reproduces `format_time_hm`'s arithmetic exactly — truncate the hour, round the remaining minutes up — because that is the convention the library's own published example was computed under. It deliberately omits C's `hours %= 24`: a time past midnight rolls into the next day rather than wrapping backwards onto the same one.

**Files:**
- Create: `lib/src/prayertimes/prayer_times.dart`
- Create: `test/prayer_times_test.dart`
- Modify: `test/prayertimes_abi_test.dart` — its import of `package:libmuslim_dart/prayertimes.dart`
- Modify: `lib/prayertimes.dart` — add four export directives and a `hide` clause on the existing one

- [ ] Step 1: Create `lib/src/prayertimes/prayer_times.dart`:
```dart
import 'dart:ffi' as ffi;

import 'calculation_method.dart';
import 'prayer.dart';
import 'prayer_times_unavailable.dart';
import 'prayertimes_bindings_generated.dart' as c;

const _obligatory = [
  Prayer.fajr,
  Prayer.dhuhr,
  Prayer.asr,
  Prayer.maghrib,
  Prayer.isha,
];

/// The prayer times for one civil day at one location.
///
/// Every time is a UTC instant. A `DateTime` built in the device's local zone
/// would be wrong whenever that zone differs from the location asked about,
/// which is exactly what a location-taking API exists to serve; call
/// [DateTime.toLocal] when device-local rendering is what you want.
///
/// Times carry whole minutes only, rounded up, matching the C library's
/// convention.
final class PrayerTimes {
  PrayerTimes._({
    required this.date,
    required this.latitude,
    required this.longitude,
    required this.utcOffset,
    required this.fajr,
    required this.sunrise,
    required this.dhuha,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  /// Prayer times for the civil date of [date] at the given location.
  ///
  /// Only [date]'s year, month and day are read; the C library takes a civil
  /// date rather than an instant, so the zone [date] carries does not matter.
  ///
  /// [utcOffset] is the location's fixed offset from UTC — `Duration(hours: 7)`
  /// for Jakarta. It is not read from the device.
  ///
  /// Throws [ArgumentError] for a coordinate outside its range, a non-finite
  /// argument, or an implausible offset. Throws [PrayerTimesUnavailable] when
  /// the sun never reaches an angle the method needs.
  factory PrayerTimes.forDate(
    DateTime date, {
    required double latitude,
    required double longitude,
    required Duration utcOffset,
    CalculationParameters parameters = const CalculationParameters.of(
      CalculationMethod.mwl,
    ),
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'must be a finite value between -90 and 90 degrees',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'must be a finite value between -180 and 180 degrees',
      );
    }
    if (utcOffset.inMinutes.abs() > 18 * 60) {
      throw ArgumentError.value(
        utcOffset,
        'utcOffset',
        'must be between -18 and +18 hours',
      );
    }

    final midnightUtc = DateTime.utc(date.year, date.month, date.day);
    final offsetHours = utcOffset.inMicroseconds /
        Duration.microsecondsPerHour;

    final times = withNativeParams(
      parameters,
      (params) => c.calculate_prayer_times(
        date.year,
        date.month,
        date.day,
        latitude,
        longitude,
        offsetHours,
        params,
      ),
    );

    final hours = <Prayer, double>{
      Prayer.fajr: times.fajr,
      Prayer.sunrise: times.sunrise,
      Prayer.dhuha: times.dhuha,
      Prayer.dhuhr: times.dhuhr,
      Prayer.asr: times.asr,
      Prayer.maghrib: times.maghrib,
      Prayer.isha: times.isha,
    };

    final unavailable = [
      for (final entry in hours.entries)
        if (!entry.value.isFinite) entry.key,
    ];
    if (unavailable.isNotEmpty) {
      throw PrayerTimesUnavailable(
        prayers: unavailable,
        latitude: latitude,
        longitude: longitude,
        date: midnightUtc,
      );
    }

    DateTime at(Prayer prayer) =>
        midnightUtc.add(_minutesFrom(hours[prayer]!)).subtract(utcOffset);

    return PrayerTimes._(
      date: midnightUtc,
      latitude: latitude,
      longitude: longitude,
      utcOffset: utcOffset,
      fajr: at(Prayer.fajr),
      sunrise: at(Prayer.sunrise),
      dhuha: at(Prayer.dhuha),
      dhuhr: at(Prayer.dhuhr),
      asr: at(Prayer.asr),
      maghrib: at(Prayer.maghrib),
      isha: at(Prayer.isha),
    );
  }

  /// Prayer times for today at the given location.
  ///
  /// "Today" is the civil date at [utcOffset], not on the device: a caller in
  /// London asking about Jakarta gets Jakarta's today.
  factory PrayerTimes.today({
    required double latitude,
    required double longitude,
    required Duration utcOffset,
    CalculationParameters parameters = const CalculationParameters.of(
      CalculationMethod.mwl,
    ),
  }) => PrayerTimes.forDate(
    DateTime.now().toUtc().add(utcOffset),
    latitude: latitude,
    longitude: longitude,
    utcOffset: utcOffset,
    parameters: parameters,
  );

  /// The civil date these times were calculated for, as UTC midnight.
  final DateTime date;

  final double latitude;
  final double longitude;

  /// The offset the times were calculated at.
  final Duration utcOffset;

  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuha;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  /// The time of [prayer], including [Prayer.sunrise] and [Prayer.dhuha].
  DateTime timeOf(Prayer prayer) => switch (prayer) {
    Prayer.fajr => fajr,
    Prayer.sunrise => sunrise,
    Prayer.dhuha => dhuha,
    Prayer.dhuhr => dhuhr,
    Prayer.asr => asr,
    Prayer.maghrib => maghrib,
    Prayer.isha => isha,
  };

  /// The prayer whose window [at] falls in, or null before Fajr.
  ///
  /// Null after Isha as well — these are one day's times, and the answer past
  /// Isha belongs to the next day's object.
  Prayer? current([DateTime? at]) {
    final instant = (at ?? DateTime.now()).toUtc();
    Prayer? found;
    for (final prayer in _obligatory) {
      if (!timeOf(prayer).isAfter(instant)) found = prayer;
    }
    return found;
  }

  /// The next prayer after [at], or null once Isha has passed.
  Prayer? next([DateTime? at]) {
    final instant = (at ?? DateTime.now()).toUtc();
    for (final prayer in _obligatory) {
      if (timeOf(prayer).isAfter(instant)) return prayer;
    }
    return null;
  }

  /// How long until [next], or null once Isha has passed.
  Duration? timeUntilNext([DateTime? at]) {
    final instant = (at ?? DateTime.now()).toUtc();
    final upcoming = next(instant);
    return upcoming == null ? null : timeOf(upcoming).difference(instant);
  }

  @override
  String toString() =>
      'PrayerTimes(${date.year}-${date.month}-${date.day} at '
      '$latitude, $longitude)';
}

/// Converts decimal hours to whole minutes the way `format_time_hm` does:
/// truncate the hour, then round the remaining minutes up.
///
/// C's own `hours %= 24` is deliberately not reproduced. Wrapping would move a
/// time past midnight backwards onto the same day; adding the duration lets it
/// roll into the next one, which is what an instant should do.
Duration _minutesFrom(double decimalHours) {
  final wholeHours = decimalHours.truncate();
  final minutes = ((decimalHours - wholeHours) * 60).ceil();
  return Duration(minutes: wholeHours * 60 + minutes);
}
```

- [ ] Step 2: Create `test/prayer_times_test.dart`:
```dart
import 'package:test/test.dart';

import 'package:libmuslim_dart/prayertimes.dart';

/// Jakarta, the location the upstream worked example uses.
const _latitude = -6.2851291;
const _longitude = 106.9814968;
const _offset = Duration(hours: 7);

PrayerTimes _jakarta({
  CalculationParameters parameters = const CalculationParameters.of(
    CalculationMethod.kemenag,
  ),
}) => PrayerTimes.forDate(
  DateTime.utc(2025, 11, 21),
  latitude: _latitude,
  longitude: _longitude,
  utcOffset: _offset,
  parameters: parameters,
);

void main() {
  test('matches the upstream worked example through the public API', () {
    // 04:05 local at +07:00 is 21:05 UTC on the previous day.
    expect(_jakarta().fajr, DateTime.utc(2025, 11, 20, 21, 5));
  });

  test('every time is a whole-minute UTC instant in order', () {
    final times = _jakarta();
    final ordered = [
      times.fajr,
      times.sunrise,
      times.dhuha,
      times.dhuhr,
      times.asr,
      times.maghrib,
      times.isha,
    ];
    for (final time in ordered) {
      expect(time.isUtc, isTrue);
      expect(time.second, 0);
      expect(time.millisecond, 0);
      expect(time.microsecond, 0);
    }
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i].isAfter(ordered[i - 1]), isTrue, reason: '$i');
    }
  });

  test('timeOf returns the field for every member of Prayer', () {
    final times = _jakarta();
    for (final prayer in Prayer.values) {
      expect(times.timeOf(prayer), isA<DateTime>());
    }
    expect(times.timeOf(Prayer.sunrise), times.sunrise);
    expect(times.timeOf(Prayer.isha), times.isha);
  });

  test('current and next skip sunrise and dhuha', () {
    final times = _jakarta();
    final justAfterSunrise = times.sunrise.add(const Duration(minutes: 1));
    expect(times.current(justAfterSunrise), Prayer.fajr);
    expect(times.next(justAfterSunrise), Prayer.dhuhr);
  });

  test('current is null before fajr and next is null after isha', () {
    final times = _jakarta();
    expect(times.current(times.fajr.subtract(const Duration(minutes: 1))),
        isNull);
    expect(times.next(times.isha.add(const Duration(minutes: 1))), isNull);
    expect(
      times.timeUntilNext(times.isha.add(const Duration(minutes: 1))),
      isNull,
    );
  });

  test('timeUntilNext measures to the next prayer', () {
    final times = _jakarta();
    final at = times.dhuhr.subtract(const Duration(minutes: 30));
    expect(times.timeUntilNext(at), const Duration(minutes: 30));
  });

  test('today uses the civil date at the offset, not the device', () {
    final times = PrayerTimes.today(
      latitude: _latitude,
      longitude: _longitude,
      utcOffset: _offset,
    );
    final expected = DateTime.now().toUtc().add(_offset);
    expect(times.date,
        DateTime.utc(expected.year, expected.month, expected.day));
  });

  test('the hanafi asr school moves asr later', () {
    final standard = _jakarta();
    final hanafi = _jakarta(
      parameters: const CalculationParameters.of(
        CalculationMethod.kemenag,
        asrSchool: AsrSchool.hanafi,
      ),
    );
    expect(hanafi.asr.isAfter(standard.asr), isTrue);
    // The override must not leak into the shared C table.
    expect(_jakarta().asr, standard.asr);
  });

  test('an ihtiyat override shifts every prayer', () {
    final base = _jakarta(
      parameters: const CalculationParameters.of(
        CalculationMethod.kemenag,
        ihtiyat: 0,
      ),
    );
    final padded = _jakarta(
      parameters: const CalculationParameters.of(
        CalculationMethod.kemenag,
        ihtiyat: 10,
      ),
    );
    expect(padded.dhuhr.difference(base.dhuhr), const Duration(minutes: 10));
  });

  test('custom parameters produce times', () {
    final byAngle = _jakarta(
      parameters: CalculationParameters.custom(
        fajrAngle: 20,
        ishaAngle: 18,
      ),
    );
    final byInterval = _jakarta(
      parameters: CalculationParameters.custom(
        fajrAngle: 20,
        ishaInterval: 90,
      ),
    );
    expect(byInterval.isha.difference(byInterval.maghrib),
        const Duration(minutes: 90));
    expect(byAngle.isha, isNot(byInterval.isha));
  });

  test('the default method is used when parameters are omitted', () {
    final times = PrayerTimes.forDate(
      DateTime.utc(2025, 11, 21),
      latitude: _latitude,
      longitude: _longitude,
      utcOffset: _offset,
    );
    expect(times.fajr, isNot(_jakarta().fajr));
  });

  group('argument validation', () {
    test('rejects an out-of-range latitude', () {
      expect(
        () => PrayerTimes.forDate(
          DateTime.utc(2025, 11, 21),
          latitude: 95,
          longitude: _longitude,
          utcOffset: _offset,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-finite longitude', () {
      expect(
        () => PrayerTimes.forDate(
          DateTime.utc(2025, 11, 21),
          latitude: _latitude,
          longitude: double.nan,
          utcOffset: _offset,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an implausible offset', () {
      expect(
        () => PrayerTimes.forDate(
          DateTime.utc(2025, 11, 21),
          latitude: _latitude,
          longitude: _longitude,
          utcOffset: const Duration(hours: 30),
        ),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] Step 3: In `test/prayertimes_abi_test.dart`, replace the line `import 'package:libmuslim_dart/prayertimes.dart';` with:
```dart
// This test verifies the generated structs against the compiled C, so it
// imports them directly. They are not part of the package's public API.
import 'package:libmuslim_dart/src/prayertimes/prayertimes_bindings_generated.dart';
```

- [ ] Step 4: In `lib/prayertimes.dart`, replace the line `export 'src/prayertimes/prayertimes_bindings_generated.dart';` with:
```dart
export 'src/prayertimes/calculation_method.dart'
    show AsrSchool, CalculationMethod, CalculationParameters;
export 'src/prayertimes/prayer.dart' show Prayer;
export 'src/prayertimes/prayer_times.dart' show PrayerTimes;
export 'src/prayertimes/prayer_times_unavailable.dart'
    show PrayerTimesUnavailable;

// Transitional, deleted whole in Task 3. The `hide` clause is what keeps this
// file compiling: the generated library declares its own `AsrSchool` and its
// own `PrayerTimes` struct, and exporting both spellings of a name from one
// library is an error at the directive.
export 'src/prayertimes/prayertimes_bindings_generated.dart'
    hide AsrSchool, PrayerTimes;
```

- [ ] Step 5: Run `dart test`
- [ ] Step 6: Run `dart analyze lib test`
- [ ] Step 7: Commit

**Note for the implementer:** the exports at Step 4 use `show` clauses, which is what keeps `checkAngle`, `checkNonNegative` and `withNativeParams` — public within `lib/src/` so `prayer_times.dart` can call them — out of the package's public API. If a symbol is missing at the call sites in Task 3, add it to the `show` list rather than removing the clause.

---

### Task 3: Seal the FFI layer and migrate every call site → verify: `git grep -n "^export .*src/prayertimes/prayertimes_bindings_generated" -- 'lib/*.dart'` reports no match, `git grep -n "dart:ffi\|package:ffi" -- example/` reports no match, `dart test` exits zero, `dart analyze` exits zero, and `flutter test` inside `example/` exits zero

This is the task the user asked for by name: after it, no FFI symbol is reachable through `package:libmuslim_dart/...`. It removes the generated export and moves all three dependants in the same commit, so no commit leaves the tree un-analyzable.

`test/prayertimes_abi_test.dart` already imports the generated file from `lib/src/` directly, moved there in Task 2 when the transitional `hide` clause took the struct out of the public export. Nothing more is needed for it here.

`test/prayertimes_test.dart` is deleted rather than migrated: its Jakarta golden already exists in `test/prayer_times_test.dart` from Task 2, expressed through the public API, which is what spec Goal 6 asked for.

`example/test/widget_test.dart` is **not** modified. The rewritten example still renders `"<Name>: HH:MM"` rows, so that test keeps measuring the same property against the new API.

**Files:**
- Modify: `lib/prayertimes.dart` — delete the generated export line and rewrite the library doc comment
- Delete: `test/prayertimes_test.dart`
- Modify: `example/lib/main.dart` — replace everything above `class MyApp`, and the one line inside `build` that reads `times.entries`
- Modify: `example/pubspec.yaml` — remove the `ffi` dependency
- Modify: `README.md` — the `## Usage` section and the paragraph following it

- [ ] Step 1: Replace the entire contents of `lib/prayertimes.dart` with:
```dart
/// Prayer times for a date and location, across 21 published calculation
/// methods.
///
/// ```dart
/// final times = PrayerTimes.today(
///   latitude: -6.2851291,
///   longitude: 106.9814968,
///   utcOffset: const Duration(hours: 7),
///   parameters: const CalculationParameters.of(CalculationMethod.kemenag),
/// );
/// print(times.fajr.toLocal());
/// print(times.next());
/// ```
///
/// Every time is a UTC instant carrying whole minutes, rounded up to match the
/// C library's convention. Call [DateTime.toLocal] to render in the device's
/// zone — but note that the device's zone and the location asked about are
/// unrelated, which is why [PrayerTimes] never reads the device offset.
///
/// The FFI bindings this is built on are deliberately not exported. They live
/// under `lib/src/` and are an implementation detail: their names, their
/// structs and their failure modes come from C and change when the vendored
/// header changes.
library;

export 'src/prayertimes/calculation_method.dart'
    show AsrSchool, CalculationMethod, CalculationParameters;
export 'src/prayertimes/prayer.dart' show Prayer;
export 'src/prayertimes/prayer_times.dart' show PrayerTimes;
export 'src/prayertimes/prayer_times_unavailable.dart'
    show PrayerTimesUnavailable;
```

- [ ] Step 2: Delete `test/prayertimes_test.dart`

- [ ] Step 3: In `example/lib/main.dart`, replace everything above the line `class MyApp extends StatefulWidget {` with:
```dart
import 'package:flutter/material.dart';
import 'package:libmuslim_dart/prayertimes.dart';

void main() {
  runApp(const MyApp());
}

/// Jakarta, using the Kemenag method, for today.
PrayerTimes _jakartaToday() => PrayerTimes.today(
  latitude: -6.2851291,
  longitude: 106.9814968,
  utcOffset: const Duration(hours: 7),
  parameters: const CalculationParameters.of(CalculationMethod.kemenag),
);

/// Renders one time in Jakarta's own offset, which is where it means
/// something — not in whatever zone this device happens to be in.
String _hm(DateTime time) {
  final local = time.add(const Duration(hours: 7));
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

const _labels = {
  Prayer.fajr: 'Fajr',
  Prayer.sunrise: 'Sunrise',
  Prayer.dhuha: 'Dhuha',
  Prayer.dhuhr: 'Dhuhr',
  Prayer.asr: 'Asr',
  Prayer.maghrib: 'Maghrib',
  Prayer.isha: 'Isha',
};

```

- [ ] Step 4: In `example/lib/main.dart`, change the field declaration `late Map<String, String> times;` to:
```dart
  late PrayerTimes times;
```

- [ ] Step 5: In `example/lib/main.dart`, replace the two lines
```dart
                for (final entry in times.entries)
                  Text('${entry.key}: ${entry.value}', style: textStyle),
```
with:
```dart
                for (final entry in _labels.entries)
                  Text(
                    '${entry.value}: ${_hm(times.timeOf(entry.key))}',
                    style: textStyle,
                  ),
```

- [ ] Step 6: In `example/pubspec.yaml`, delete the line `  ffi: ^2.1.4` and the blank line following it from the `dependencies` block

- [ ] Step 7: In `README.md`, replace the fenced `dart` block under `## Usage` and the paragraph immediately after it (the one beginning "These are the raw generated bindings") with:
````markdown
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
````

- [ ] Step 8: Run `flutter pub get` inside `example/`
- [ ] Step 9: Run `dart test`
- [ ] Step 10: Run `dart analyze`
- [ ] Step 11: Run `flutter test` inside `example/`
- [ ] Step 12: Commit
