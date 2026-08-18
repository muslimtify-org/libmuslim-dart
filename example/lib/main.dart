import 'package:flutter/material.dart';
import 'package:libmuslim_dart/prayertimes.dart';

void main() {
  runApp(const MyApp());
}

/// Jakarta's UTC offset, used both to calculate today's prayer times and to
/// render them back in local time.
const _jakartaUtcOffset = Duration(hours: 7);

/// Jakarta, using the Kemenag method, for today.
PrayerTimes _jakartaToday() => PrayerTimes.today(
  latitude: -6.2851291,
  longitude: 106.9814968,
  utcOffset: _jakartaUtcOffset,
  parameters: const CalculationParameters.of(CalculationMethod.kemenag),
);

/// Renders one time in Jakarta's own offset, which is where it means
/// something — not in whatever zone this device happens to be in.
String _hm(DateTime time) {
  final local = time.add(_jakartaUtcOffset);
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

const _labels = {
  Prayer.fajr: 'Fajr',
  Prayer.sunrise: 'Sunrise',
  Prayer.dhuha: 'Dhuha',
  Prayer.dhuhr: 'Dhuhr',
  Prayer.asr: 'Asr',
  Prayer.maghrib: 'Maghrib',
  Prayer.isha: 'Isha',
};

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late PrayerTimes times;

  @override
  void initState() {
    super.initState();
    times = _jakartaToday();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('libmuslim prayer times')),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jakarta, Kemenag method, calculated in C through FFI.',
                  style: textStyle,
                ),
                const SizedBox(height: 10),
                for (final entry in _labels.entries)
                  Text(
                    '${entry.value}: ${_hm(times.timeOf(entry.key))}',
                    style: textStyle,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
