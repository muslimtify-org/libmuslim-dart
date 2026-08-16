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
