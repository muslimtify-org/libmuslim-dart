import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libmuslim_dart_example/main.dart';

void main() {
  testWidgets('renders one HH:MM row per prayer time', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Every row the example builds is "<Name>: HH:MM", one per field of the
    // C struct. Matching the shape rather than the values keeps this passing
    // as the date changes, while still failing if the FFI call returns
    // nothing, throws, or yields NaN.
    final row = RegExp(
      r'^(Fajr|Dhuhr|Asr|Maghrib|Isha): \d{2}:\d{2}$',
    );
    final rows = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && row.hasMatch(w.data!),
    );

    // struct PrayerTimes has seven fields; the example renders all of them.
    expect(rows, findsNWidgets(7));
  });
}
