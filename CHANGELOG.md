## Unreleased

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

Known issue: `dhuha` is NaN above roughly 62.5 degrees of latitude on the days
the Sun never reaches the dhuha altitude, with no error and no sentinel. At
Reykjavik that is 40 days a year. Sunrise and dhuhr solve normally on those
same days, so only this one field is affected
([libmuslim#51](https://github.com/muslimtify-org/libmuslim/issues/51)).
