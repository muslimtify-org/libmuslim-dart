import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:libmuslim_dart/prayertimes.dart';

void main() {
  test('Jakarta 2025-11-21 kemenag matches the upstream worked example', () {
    final key = 'kemenag'.toNativeUtf8();
    final buf = calloc<Char>(16);
    try {
      final params = method_params_get(method_from_string(key.cast<Char>()));
      expect(params, isNot(nullptr));

      final times = calculate_prayer_times(
        2025,
        11,
        21,
        -6.2851291,
        106.9814968,
        7.0,
        params,
      );

      format_time_hm(times.fajr, buf, 16);
      expect(buf.cast<Utf8>().toDartString(), '04:05');
    } finally {
      calloc.free(buf);
      malloc.free(key);
    }
  });
}
