/// One of the times `PrayerTimes` reports.
///
/// [sunrise] and [dhuha] are members so `PrayerTimes.timeOf` can return them,
/// but they are not prayers: `PrayerTimes.current` and `PrayerTimes.next` skip
/// both.
///
/// This lives in its own file because `PrayerTimesUnavailable` names it and is
/// created before `PrayerTimes` is.
enum Prayer { fajr, sunrise, dhuha, dhuhr, asr, maghrib, isha }
