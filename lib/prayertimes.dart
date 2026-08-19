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
    show AsrSchool, CalculationMethod, CalculationParameters, HighLatitudeRule;
export 'src/prayertimes/prayer.dart' show Prayer;
export 'src/prayertimes/prayer_times.dart' show PrayerTimes;
export 'src/prayertimes/prayer_times_unavailable.dart'
    show PrayerTimesUnavailable;
