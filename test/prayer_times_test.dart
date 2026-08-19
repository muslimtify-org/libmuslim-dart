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
    //   Expected: DateTime:<2025-05-16 22:54:00.000Z>
    //     Actual: DateTime:<2025-05-17 22:54:00.000Z>
    // Wrapping wholeHours alone does not, because minutes is computed from
    // decimalHours - wholeHours and absorbs the 24 back.

    test('an hour at or above 24 rolls forward', () {
      // C: calculate_prayer_times(2025, 4, 7, 64.15, -21.94, 0.0, MWL)
      // returns isha = 24.134988, which is 00:08:06 on 8 April, and the
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
      // C: calculate_prayer_times(2025, 5, 17, 69.65, 18.96, 1.0, MWL)
      // returns fajr = -0.104232, which is 23:53:45 local on 16 May. At
      // +01:00 that is 22:53:45 UTC, and the ceiling carries it to 22:54.
      final times = PrayerTimes.forDate(
        DateTime.utc(2025, 5, 17),
        latitude: 69.65,
        longitude: 18.96,
        utcOffset: const Duration(hours: 1),
      );
      expect(times.fajr, DateTime.utc(2025, 5, 16, 22, 54));
      expect(times.fajr.isBefore(times.dhuhr), isTrue);
    });
  });
}
