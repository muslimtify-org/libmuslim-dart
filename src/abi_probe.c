#include <stddef.h>
#include "prayertimes.h"

_Static_assert(CALC_MWL == 0, "CALC_MWL");
_Static_assert(CALC_MAKKAH == 1, "CALC_MAKKAH");
_Static_assert(CALC_ISNA == 2, "CALC_ISNA");
_Static_assert(CALC_EGYPT == 3, "CALC_EGYPT");
_Static_assert(CALC_KARACHI == 4, "CALC_KARACHI");
_Static_assert(CALC_TURKEY == 5, "CALC_TURKEY");
_Static_assert(CALC_SINGAPORE == 6, "CALC_SINGAPORE");
_Static_assert(CALC_JAKIM == 7, "CALC_JAKIM");
_Static_assert(CALC_KEMENAG == 8, "CALC_KEMENAG");
_Static_assert(CALC_FRANCE == 9, "CALC_FRANCE");
_Static_assert(CALC_RUSSIA == 10, "CALC_RUSSIA");
_Static_assert(CALC_DUBAI == 11, "CALC_DUBAI");
_Static_assert(CALC_QATAR == 12, "CALC_QATAR");
_Static_assert(CALC_KUWAIT == 13, "CALC_KUWAIT");
_Static_assert(CALC_JORDAN == 14, "CALC_JORDAN");
_Static_assert(CALC_GULF == 15, "CALC_GULF");
_Static_assert(CALC_TUNISIA == 16, "CALC_TUNISIA");
_Static_assert(CALC_ALGERIA == 17, "CALC_ALGERIA");
_Static_assert(CALC_MOROCCO == 18, "CALC_MOROCCO");
_Static_assert(CALC_PORTUGAL == 19, "CALC_PORTUGAL");
_Static_assert(CALC_MOONSIGHTING == 20, "CALC_MOONSIGHTING");
_Static_assert(CALC_CUSTOM == 21, "CALC_CUSTOM");
_Static_assert(CALC_COUNT == 22, "CALC_COUNT");
_Static_assert(ASR_STANDARD == 1 && ASR_HANAFI == 2, "AsrSchool");
_Static_assert(HIGHLAT_NONE == 0 && HIGHLAT_MIDDLE_OF_NIGHT == 1 &&
                   HIGHLAT_ONE_SEVENTH == 2 && HIGHLAT_ANGLE_BASED == 3,
               "HighLatMethod");
_Static_assert(MIDNIGHT_STANDARD == 0, "MidnightMode");

size_t abi_sizeof_method_params(void) { return sizeof(MethodParams); }
size_t abi_sizeof_prayer_times(void) { return sizeof(struct PrayerTimes); }

/* Field-offset verification for Dart.
 *
 * dart:ffi has no offsetOf, so the Rust binding's per-field offsetof
 * comparison cannot be ported literally. Instead these write a distinct
 * sentinel through each C field name; the Dart test reads each field through
 * the generated struct and asserts the value. A wrong offset or a wrong field
 * width yields a wrong number, so the assertion fails. */
void abi_fill_method_params(MethodParams *out) {
  out->name = "probe";
  out->fajr_angle = 11.0;
  out->isha_angle = 22.0;
  out->isha_interval = 33;
  out->maghrib_interval = 44;
  out->asr_shadow = 55;
  out->midnight_mode = MIDNIGHT_STANDARD;
  out->ihtiyat = 66;
}

void abi_fill_prayer_times(struct PrayerTimes *out) {
  out->fajr = 1.5;
  out->sunrise = 2.5;
  out->dhuha = 3.5;
  out->dhuhr = 4.5;
  out->asr = 5.5;
  out->maghrib = 6.5;
  out->isha = 7.5;
}

double abi_constant_deg_to_rad(void) { return DEG_TO_RAD; }
double abi_constant_rad_to_deg(void) { return RAD_TO_DEG; }
double abi_constant_julian_epoch(void) { return JULIAN_EPOCH; }
double abi_constant_sun_mean_anomaly_offset(void) { return SUN_MEAN_ANOMALY_OFFSET; }
double abi_constant_sun_mean_anomaly_rate(void) { return SUN_MEAN_ANOMALY_RATE; }
double abi_constant_sun_mean_longitude_offset(void) { return SUN_MEAN_LONGITUDE_OFFSET; }
double abi_constant_sun_mean_longitude_rate(void) { return SUN_MEAN_LONGITUDE_RATE; }
double abi_constant_sun_eccentricity_amplitude1(void) { return SUN_ECCENTRICITY_AMPLITUDE1; }
double abi_constant_sun_eccentricity_amplitude2(void) { return SUN_ECCENTRICITY_AMPLITUDE2; }
double abi_constant_obliquity_coeff(void) { return OBLIQUITY_COEFF; }
double abi_constant_obliquity_rate(void) { return OBLIQUITY_RATE; }
double abi_constant_refraction_correction(void) { return REFRACTION_CORRECTION; }
double abi_constant_dhuha_altitude(void) { return DHUHA_ALTITUDE; }

/* mt_days_from_civil and mt_civil_from_days are static inline in the header,
 * so they have no external linkage and ffigen cannot bind them. These wrappers
 * are the only route to them from Dart. */
long abi_days_from_civil(int y, int m, int d) {
  return mt_days_from_civil(y, m, d);
}

void abi_civil_from_days(long days, int *y, int *m, int *d) {
  mt_civil_from_days(days, y, m, d);
}
