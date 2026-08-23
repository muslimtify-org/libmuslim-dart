## 0.1.1

### Vendored header

Synced to `prayertimes.h` `v0.2.3`, libmuslim releases
[2026.08.21](https://github.com/muslimtify-org/libmuslim/releases/tag/2026.08.21)
and
[2026.08.22](https://github.com/muslimtify-org/libmuslim/releases/tag/2026.08.22).
No API change: every type and member in this package is unchanged, and code
written against `0.1.0` compiles against this release.

`refine_event` is gone
([libmuslim#85](https://github.com/muslimtify-org/libmuslim/pull/85), closing
[libmuslim#79](https://github.com/muslimtify-org/libmuslim/issues/79)). Fajr,
isha, sunrise and sunset are now solved the same way, by bisecting true solar
altitude between local noon and local midnight, so whether an event exists is
decided at the event rather than at 0h UT. The twilight grazing residual that
motivated the change is gone with it: the worst angular error over the flagged
points falls from 30.1964 arcmin to 0.1970.

**Times move at high latitude, and what you see depends on the method.**
Measured directly against the `2026.08.21` header over latitude -70 to 70 in
steps of 5, longitude 0, every day of 2026, all five prayers, 52925 values:

| | MWL | Kemenag |
| --- | --- | --- |
| values changing the displayed minute | 14 | 13 |
| prayers becoming unavailable | 0 | 3 |

Every changed value is a day on which the twilight event does not exist and the
old solver reported a crossing near midnight anyway. Under a method that
publishes a high-latitude rule, MWL and Moonsighting, the substitution now runs
instead, which moves isha by up to 1 hour 54 minutes and never removes a time.
Under the other 20 methods there is no rule to fall back on, so
`PrayerTimesUnavailable` is thrown where `0.1.0` returned a wrong time. On this
grid that is latitude 70 on 2026-05-16, where Kemenag now reports
`[Prayer.fajr, Prayer.maghrib, Prayer.isha]` as unavailable and `0.1.0`
returned 00:07, 23:33 and 23:49.

Every other value on the grid moves by at most 0.0003 seconds, far below the
whole-minute resolution this package returns.

Existence was then checked upstream against JPL DE440 over the same grid, 42340
decisions across sunrise, sunset, fajr and isha. Two disagree, both a single
day at latitude -70 in November where the low precision solar model and DE440
differ by 0.0035 degrees on a 0.0013 degree margin. That is the sun model's own
noise rather than the solver's.

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
