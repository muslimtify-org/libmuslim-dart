/// One of the five prescribed prayers `PrayerTimes` reports.
///
/// Sunrise and dhuha were members until libmuslim v0.2.0 removed them from
/// `struct PrayerTimes`. Sunrise is the end of the fajr window rather than a
/// prayer, and dhuha is a voluntary prayer carried only by Indonesian
/// timetables.
///
/// This lives in its own file because `PrayerTimesUnavailable` names it and is
/// created before `PrayerTimes` is.
enum Prayer { fajr, dhuhr, asr, maghrib, isha }
