## Unreleased

* **Fixed.** An `asrSchool` or `ihtiyat` override silently discarded the method's high-latitude rule. `withNativeParams` copies the C table entry field by field when an override is present, and it did not copy `high_lat_method` or `high_lat_ref`, which were added upstream in libmuslim#62. At Longyearbyen on the solstice, `CalculationParameters.of(CalculationMethod.mwl)` returned a Fajr while `CalculationParameters.of(CalculationMethod.mwl, ihtiyat: 2)` threw `PrayerTimesUnavailable`, purely because of the unrelated override.

* **Added.** `HighLatitudeRule`, plus `highLatitudeRule` and `highLatitudeReferenceLatitude` on both `CalculationParameters` constructors. Inside the polar circle there is no sunrise or sunset, so the substitution rules have no night to measure and only MWL and Moonsighting carry a reference latitude. A caller serving a location the chosen authority is silent about can now supply one themselves, which keeps the choice in the caller's code rather than misattributing it to that authority ([libmuslim#51](https://github.com/muslimtify-org/libmuslim/issues/51)).

* **Breaking.** `PrayerTimes` carries the five prescribed prayers only. `sunrise` and `dhuha` are removed, along with the `Prayer.sunrise` and `Prayer.dhuha` enum members and the generated `DHUHA_ALTITUDE` constant. Sunrise is the end of the fajr window rather than a prayer, and dhuha is a voluntary prayer carried only by Indonesian timetables. Both are still computed inside the C library, because maghrib is sunset and every high-latitude substitution measures the night between sunset and sunrise, but neither is part of the contract ([libmuslim#63](https://github.com/muslimtify-org/libmuslim/pull/63)).

  This also removes the reason `PrayerTimesUnavailable` was most often thrown. A dhuha that never occurred used to make the whole day unavailable, which above roughly 62.5 degrees is most of the summer. `Prayer.values` is now exactly the set of prescribed prayers, so the separate obligatory-prayer list that `current` and `next` walked is gone.

* Synced the vendored `src/prayertimes.h` from libmuslim `main`, which fixes
  the C time formatters and corrects the ACCURACY check counts. No Dart change
  was needed. `_minutesFrom` converts through a `Duration` rather than
  reproducing C's field wrapping, so times outside 0 to 24 hours already
  resolved onto the correct calendar day in both directions.

## 0.0.1

Initial release.

* Dart FFI bindings for `prayertimes.h` from
  [libmuslim](https://github.com/muslimtify-org/libmuslim). The header is
  vendored at `src/prayertimes.h` and its ABI is pinned by
  `test/prayertimes_abi_test.dart`, so a changed C layout fails the tests
  rather than diverging silently.
* `PrayerTimes` returning whole-minute UTC instants, with `timeOf`, `current`,
  `next` and `timeUntilNext`.
* `CalculationMethod` and `CalculationParameters`, including custom angles,
  the hanafi asr school and an ihtiyat override.
* `Prayer` and `PrayerTimesUnavailable`.

### Vendored header

Synced to libmuslim `f3d30a7`. Prayer times are computed from a solar position
evaluated at each event's own instant. Earlier builds of this package evaluated
the Sun once at 0h UT and reused it for events up to 20 hours later, so times
above roughly 55 degrees of latitude differ from those builds, isha by up to
16 minutes. Equatorial results move by at most 1 minute.

Maghrib is measured against a JPL DE440 validated solver at 6.5966 seconds
worst case for `|latitude| <= 60`. Fajr and isha have no oracle behind them
upstream, tracked as
[libmuslim#52](https://github.com/muslimtify-org/libmuslim/issues/52).

That known issue about `dhuha` being NaN above roughly 62.5 degrees no longer applies, because the field is gone. See the breaking change at the top of this file.
