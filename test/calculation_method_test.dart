import 'package:test/test.dart';

import 'package:libmuslim_dart/src/prayertimes/calculation_method.dart';

void main() {
  group('CalculationMethod', () {
    test('reads its display name and key from the C table', () {
      expect(CalculationMethod.kemenag.displayName, 'KEMENAG, Indonesia');
      expect(CalculationMethod.kemenag.key, 'kemenag');
      expect(CalculationMethod.mwl.displayName, 'Muslim World League');
    });

    test('every member resolves to a non-empty name and key', () {
      for (final method in CalculationMethod.values) {
        expect(method.displayName, isNotEmpty, reason: method.name);
        expect(method.key, isNotEmpty, reason: method.name);
      }
    });

    test('keys are distinct, so no two members alias the same C entry', () {
      final keys = CalculationMethod.values.map((m) => m.key).toSet();
      expect(keys, hasLength(CalculationMethod.values.length));
    });
  });

  group('CalculationParameters.custom', () {
    test('rejects neither isha angle nor interval', () {
      expect(
        () => CalculationParameters.custom(fajrAngle: 18),
        throwsArgumentError,
      );
    });

    test('rejects both isha angle and interval', () {
      expect(
        () => CalculationParameters.custom(
          fajrAngle: 18,
          ishaAngle: 17,
          ishaInterval: 90,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an out-of-range or non-finite angle', () {
      expect(
        () => CalculationParameters.custom(fajrAngle: 95, ishaAngle: 17),
        throwsArgumentError,
      );
      expect(
        () =>
            CalculationParameters.custom(fajrAngle: double.nan, ishaAngle: 17),
        throwsArgumentError,
      );
    });

    test('rejects a negative interval or ihtiyat', () {
      expect(
        () =>
            CalculationParameters.custom(fajrAngle: 18, ishaInterval: -1),
        throwsArgumentError,
      );
      expect(
        () => CalculationParameters.custom(
          fajrAngle: 18,
          ishaAngle: 17,
          ihtiyat: -1,
        ),
        throwsArgumentError,
      );
    });

    test('accepts exactly one isha mode', () {
      expect(
        CalculationParameters.custom(fajrAngle: 18, ishaAngle: 17),
        isA<CalculationParameters>(),
      );
      expect(
        CalculationParameters.custom(fajrAngle: 18, ishaInterval: 90),
        isA<CalculationParameters>(),
      );
    });
  });
}
