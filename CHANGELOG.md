## 0.1.0

First published release. Versions `0.0.1` and the entries previously filed
under `Unreleased` were never published to pub.dev; their content is folded in
here.

* Dart FFI bindings for `prayertimes.h` from
  [libmuslim](https://github.com/muslimtify-org/libmuslim). The header is
  vendored at `src/prayertimes.h` and its ABI is pinned by
  `test/prayertimes_abi_test.dart`, so a changed C layout fails the tests
  rather than diverging silently.
* `PrayerTimes` returning whole-minute UTC instants, with `timeOf`, `current`,
  `next` and `timeUntilNext`. It carries the five prescribed prayers only.
  Sunrise is the end of the fajr window rather than a prayer, and dhuha is a
  voluntary prayer carried only by Indonesian timetables. Both are still
  computed inside the C library, because maghrib is sunset and every
  high-latitude substitution measures the night between sunset and sunrise,
  but neither is part of the contract
  ([libmuslim#63](https://github.com/muslimtify-org/libmuslim/pull/63)).
  `Prayer.values` is therefore exactly the set of prescribed prayers.
* `CalculationMethod` and `CalculationParameters`, including custom angles,
  the hanafi asr school and an ihtiyat override.
* `HighLatitudeRule`, plus `highLatitudeRule` and
  `highLatitudeReferenceLatitude` on both `CalculationParameters` constructors.
  Inside the polar circle there is no sunrise or sunset, so the substitution
  rules have no night to measure, and only MWL and Moonsighting carry a
  reference latitude. A caller serving a location the chosen authority is
  silent about can supply one themselves, which keeps the choice in the
  caller's code rather than misattributing it to that authority
  ([libmuslim#51](https://github.com/muslimtify-org/libmuslim/issues/51)).
* `Prayer` and `PrayerTimesUnavailable`.

### Vendored header

Synced to `prayertimes.h` `v0.2.1`, libmuslim release
[2026.08.20](https://github.com/muslimtify-org/libmuslim/releases/tag/2026.08.20).

Prayer times are computed from a solar position evaluated at each event's own
instant. Maghrib is measured against a JPL DE440 validated solver at 6.5966
seconds worst case for `|latitude| <= 60`. Fajr and isha have no oracle behind
them upstream, tracked as
[libmuslim#52](https://github.com/muslimtify-org/libmuslim/issues/52).

Inside the polar circle the whole day is solved at the reference latitude
rather than borrowing only sunrise and sunset. Each value in the tests is
checked against the C library directly.

### Known issue

`PrayerTimes.forDate` throws `PrayerTimesUnavailable` with `[Prayer.asr]` on a
narrow band of days at high latitude. At Longyearbyen that is four days a year,
where the separation from the declination sits between 90 and 90.833 degrees:
the Sun is visible only by refraction, so sunrise exists and fajr, maghrib and
isha all resolve, but nothing casts a shadow. Four valid times are withheld
with the impossible one. That is the same shape as the dhuha problem
libmuslim#63 solved upstream by removing the field; asr cannot be removed, so
whether it should become nullable is open.
