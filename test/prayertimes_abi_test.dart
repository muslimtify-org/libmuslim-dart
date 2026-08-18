import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

// This test verifies the generated structs against the compiled C, so it
// imports them directly. They are not part of the package's public API.
import 'package:libmuslim_dart/src/prayertimes/prayertimes_bindings_generated.dart';

// The `@Native` declarations below must be spelled exactly as the C symbols
// they bind, so lowerCamelCase is not available to them. ffigen's own generated
// bindings suppress the same rule for the same reason.
// ignore_for_file: non_constant_identifier_names

const _assetId = 'package:libmuslim_dart/libmuslim_dart_bindings_generated.dart';

@Native<Size Function()>(assetId: _assetId)
external int abi_sizeof_method_params();

@Native<Size Function()>(assetId: _assetId)
external int abi_sizeof_prayer_times();

@Native<Void Function(Pointer<MethodParams>)>(assetId: _assetId)
external void abi_fill_method_params(Pointer<MethodParams> out);

@Native<Void Function(Pointer<PrayerTimes>)>(assetId: _assetId)
external void abi_fill_prayer_times(Pointer<PrayerTimes> out);

@Native<Double Function()>(assetId: _assetId)
external double abi_constant_deg_to_rad();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_rad_to_deg();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_julian_epoch();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_anomaly_offset();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_anomaly_rate();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_longitude_offset();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_mean_longitude_rate();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_eccentricity_amplitude1();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_sun_eccentricity_amplitude2();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_obliquity_coeff();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_obliquity_rate();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_refraction_correction();
@Native<Double Function()>(assetId: _assetId)
external double abi_constant_dhuha_altitude();

@Native<Long Function(Int, Int, Int)>(assetId: _assetId)
external int abi_days_from_civil(int y, int m, int d);

@Native<Void Function(Long, Pointer<Int>, Pointer<Int>, Pointer<Int>)>(
  assetId: _assetId,
)
external void abi_civil_from_days(
  int days,
  Pointer<Int> y,
  Pointer<Int> m,
  Pointer<Int> d,
);

void main() {
  group('struct size', () {
    test('MethodParams', () {
      expect(sizeOf<MethodParams>(), abi_sizeof_method_params());
    });

    test('PrayerTimes', () {
      expect(sizeOf<PrayerTimes>(), abi_sizeof_prayer_times());
    });
  });

  group('field round-trip', () {
    test('MethodParams', () {
      final p = calloc<MethodParams>();
      try {
        abi_fill_method_params(p);
        expect(p.ref.name.cast<Utf8>().toDartString(), 'probe');
        expect(p.ref.fajr_angle, 11.0);
        expect(p.ref.isha_angle, 22.0);
        expect(p.ref.isha_interval, 33);
        expect(p.ref.maghrib_interval, 44);
        expect(p.ref.asr_shadow, 55);
        expect(p.ref.ihtiyat, 66);
      } finally {
        calloc.free(p);
      }
    });

    test('PrayerTimes', () {
      final p = calloc<PrayerTimes>();
      try {
        abi_fill_prayer_times(p);
        expect(p.ref.fajr, 1.5);
        expect(p.ref.sunrise, 2.5);
        expect(p.ref.dhuha, 3.5);
        expect(p.ref.dhuhr, 4.5);
        expect(p.ref.asr, 5.5);
        expect(p.ref.maghrib, 6.5);
        expect(p.ref.isha, 7.5);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('header constants', () {
    test('all thirteen match the compiled header', () {
      expect(abi_constant_deg_to_rad(), DEG_TO_RAD);
      expect(abi_constant_rad_to_deg(), RAD_TO_DEG);
      expect(abi_constant_julian_epoch(), JULIAN_EPOCH);
      expect(abi_constant_sun_mean_anomaly_offset(), SUN_MEAN_ANOMALY_OFFSET);
      expect(abi_constant_sun_mean_anomaly_rate(), SUN_MEAN_ANOMALY_RATE);
      expect(
        abi_constant_sun_mean_longitude_offset(),
        SUN_MEAN_LONGITUDE_OFFSET,
      );
      expect(abi_constant_sun_mean_longitude_rate(), SUN_MEAN_LONGITUDE_RATE);
      expect(
        abi_constant_sun_eccentricity_amplitude1(),
        SUN_ECCENTRICITY_AMPLITUDE1,
      );
      expect(
        abi_constant_sun_eccentricity_amplitude2(),
        SUN_ECCENTRICITY_AMPLITUDE2,
      );
      expect(abi_constant_obliquity_coeff(), OBLIQUITY_COEFF);
      expect(abi_constant_obliquity_rate(), OBLIQUITY_RATE);
      expect(abi_constant_refraction_correction(), REFRACTION_CORRECTION);
      expect(abi_constant_dhuha_altitude(), DHUHA_ALTITUDE);
    });
  });

  group('civil date helpers', () {
    // The two static inline helpers, reachable only through the probe.
    // A leap day, the epoch itself, and a pre-epoch date.
    for (final (y, m, d) in const [
      (2024, 2, 29),
      (1970, 1, 1),
      (1601, 12, 31),
      (2026, 8, 15),
    ]) {
      test('$y-$m-$d round-trips', () {
        final days = abi_days_from_civil(y, m, d);
        final out = calloc<Int>(3);
        try {
          abi_civil_from_days(days, out, out + 1, out + 2);
          expect(out[0], y);
          expect(out[1], m);
          expect(out[2], d);
        } finally {
          calloc.free(out);
        }
      });
    }

    test('epoch is day zero', () {
      expect(abi_days_from_civil(1970, 1, 1), 0);
    });
  });
}
