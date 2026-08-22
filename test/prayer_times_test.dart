import 'package:test/test.dart';

import 'package:libmuslim/prayertimes.dart';

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
    expect(times.timeOf(Prayer.fajr), times.fajr);
    expect(times.timeOf(Prayer.isha), times.isha);
  });

  test('current and next report the surrounding window', () {
    final times = _jakarta();
    final betweenFajrAndDhuhr = times.fajr.add(const Duration(minutes: 1));
    expect(times.current(betweenFajrAndDhuhr), Prayer.fajr);
    expect(times.next(betweenFajrAndDhuhr), Prayer.dhuhr);
  });

  test('current is null before fajr and next is null after isha', () {
    final times = _jakarta();
    expect(
      times.current(times.fajr.subtract(const Duration(minutes: 1))),
      isNull,
    );
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
    expect(
      times.date,
      DateTime.utc(expected.year, expected.month, expected.day),
    );
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
      parameters: CalculationParameters.custom(fajrAngle: 20, ishaAngle: 18),
    );
    final byInterval = _jakarta(
      parameters: CalculationParameters.custom(fajrAngle: 20, ishaInterval: 90),
    );
    expect(
      byInterval.isha.difference(byInterval.maghrib),
      const Duration(minutes: 90),
    );
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

  group('times outside 0 to 24 hours land on the right calendar day', () {
    // The C library returns a decimal hour below 0 or at or above 24 when the
    // high-latitude substitution puts an event on an adjacent day, and the
    // double is the only thing carrying that offset. Reproducing C's field
    // wrapping here would silently move the event onto the wrong day, so these
    // pin both directions against values read straight out of the C header.
    //
    // Mutation record: wrapping the returned Duration, by changing the last
    // line of _minutesFrom to
    //   return Duration(minutes: (wholeHours * 60 + minutes) % 1440);
    // fails both tests, pasted verbatim from the terminal:
    //   Expected: DateTime:<2025-04-08 00:09:00.000Z>
    //     Actual: DateTime:<2025-04-07 00:09:00.000Z>
    //   Expected: DateTime:<2026-09-06 04:22:00.000Z>
    //     Actual: DateTime:<2026-09-07 04:22:00.000Z>
    // Wrapping wholeHours alone does not, because minutes is computed from
    // decimalHours - wholeHours and absorbs the 24 back.

    test('an hour at or above 24 rolls forward', () {
      // C: calculate_prayer_times(2025, 4, 7, 64.15, -21.94, 0.0, MWL)
      // returns isha = 24.135902, which is 00:08:09 on 8 April, and the
      // minute ceiling carries it to 00:09.
      final times = PrayerTimes.forDate(
        DateTime.utc(2025, 4, 7),
        latitude: 64.15,
        longitude: -21.94,
        utcOffset: Duration.zero,
      );
      expect(times.isha, DateTime.utc(2025, 4, 8, 0, 9));
      expect(times.isha.isAfter(times.maghrib), isTrue);
    });

    test('an hour below 0 rolls back', () {
      // C: calculate_prayer_times(2026, 9, 6, 82.50, -62.35, -5.0, MWL)
      // returns fajr = -0.649757, which is 23:21:00 local on 5 September. At
      // -05:00 that is 04:21:00 UTC on 6 September, and the ceiling carries
      // the minute to 04:22.
      //
      // This was Tromso, 2025-05-17, until libmuslim 2026.08.22. That case
      // held by six minutes of negative hour, and the six minutes came from a
      // twilight crossing the old solver reported on a day that has none, so
      // fixing libmuslim#79 moved fajr to +2.043258 and the case stopped
      // exercising this path rather than merely reporting the wrong instant.
      // Alert is the most negative fajr any settlement sees in 2026, at
      // thirty-nine minutes, and it is not an artifact of the fix: v0.2.1
      // returned -0.658336 for the same call.
      final times = PrayerTimes.forDate(
        DateTime.utc(2026, 9, 6),
        latitude: 82.50,
        longitude: -62.35,
        utcOffset: const Duration(hours: -5),
      );
      expect(times.fajr, DateTime.utc(2026, 9, 6, 4, 22));
      expect(times.fajr.isBefore(times.dhuhr), isTrue);
    });
  });

  group('the polar case follows the method, and the caller can override it', () {
    // Longyearbyen, 78.22N, inside the polar circle at midsummer.
    DateTime? fajrAt(CalculationParameters parameters) {
      try {
        return PrayerTimes.forDate(
          DateTime.utc(2026, 6, 21),
          latitude: 78.22,
          longitude: 15.65,
          utcOffset: const Duration(hours: 1),
          parameters: parameters,
        ).fajr;
      } on PrayerTimesUnavailable {
        return null;
      }
    }

    test('a method whose authority publishes a rule resolves', () {
      // MWL carries the reference latitude of 45 its own Fiqh Council decree
      // names, so every prescribed time resolves here.
      expect(
        fajrAt(const CalculationParameters.of(CalculationMethod.mwl)),
        DateTime.utc(2026, 6, 21, 0, 38),
      );
    });

    test('an unrelated override does not discard that rule', () {
      // The values here changed with libmuslim 2026.08.20, which solves the
      // whole polar day at the reference latitude rather than borrowing only
      // sunrise and sunset. Each is checked against the C library directly.
      //
      // Regression: the native copy taken for an asrSchool or ihtiyat override
      // did not carry high_lat_method or high_lat_ref, so asking for a
      // 2 minute ihtiyat silently turned MWL into a method with no polar rule
      // and this call threw PrayerTimesUnavailable.
      expect(
        fajrAt(
          const CalculationParameters.of(CalculationMethod.mwl, ihtiyat: 2),
        ),
        DateTime.utc(2026, 6, 21, 0, 40),
      );
    });

    test('a method whose authority is silent reports unavailable', () {
      // Kemenag publishes no high-latitude rule. The library declines to
      // invent one on that authority's behalf.
      expect(
        fajrAt(const CalculationParameters.of(CalculationMethod.kemenag)),
        isNull,
      );
    });

    test('the caller can supply the rule the authority did not', () {
      // The choice is the caller's, and it is recorded in the caller's code
      // rather than misattributed to Kemenag.
      expect(
        fajrAt(
          const CalculationParameters.of(
            CalculationMethod.kemenag,
            highLatitudeRule: HighLatitudeRule.angleBased,
            highLatitudeReferenceLatitude: 45.0,
          ),
        ),
        DateTime.utc(2026, 6, 21, 0, 6),
      );
    });

    test('a reference latitude outside 0 to 90 is rejected', () {
      expect(
        () => fajrAt(
          const CalculationParameters.of(
            CalculationMethod.kemenag,
            highLatitudeReferenceLatitude: 91.0,
          ),
        ),
        throwsArgumentError,
      );
    });
    test('asr is unavailable where the Sun casts no shadow', () {
      // libmuslim 2026.08.20 stopped reporting asr where no shadow can exist.
      // At Longyearbyen there is a narrow band, four days a year, where the
      // separation from the declination sits between 90 and 90.833 degrees:
      // the Sun is visible only by refraction, so sunrise exists and fajr,
      // maghrib and isha all resolve, but nothing casts a shadow.
      //
      // This class throws when any field is non-finite, so the whole day is
      // unavailable and the four valid times go with it. Pinned so the
      // behaviour is on record rather than accidental.
      expect(
        () => PrayerTimes.forDate(
          DateTime.utc(2026, 2, 16),
          latitude: 78.22,
          longitude: 15.65,
          utcOffset: const Duration(hours: 1),
        ),
        throwsA(
          isA<PrayerTimesUnavailable>().having((e) => e.prayers, 'prayers', [
            Prayer.asr,
          ]),
        ),
      );
    });
  });
}
