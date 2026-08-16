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
