import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:libmuslim_dart/prayertimes.dart';

void main() {
  runApp(const MyApp());
}

/// Formats one decimal-hours time through the C formatter.
String _hm(double hours) {
  final buf = calloc<Char>(16);
  try {
    format_time_hm(hours, buf, 16);
    return buf.cast<Utf8>().toDartString();
  } finally {
    calloc.free(buf);
  }
}

/// Jakarta, using the Kemenag method, for today.
Map<String, String> _jakartaToday() {
  final key = 'kemenag'.toNativeUtf8();
  try {
    final params = method_params_get(method_from_string(key.cast<Char>()));
    final now = DateTime.now();
    final t = calculate_prayer_times(
      now.year,
      now.month,
      now.day,
      -6.2851291,
      106.9814968,
      7.0,
      params,
    );
    return {
      'Fajr': _hm(t.fajr),
      'Sunrise': _hm(t.sunrise),
      'Dhuha': _hm(t.dhuha),
      'Dhuhr': _hm(t.dhuhr),
      'Asr': _hm(t.asr),
      'Maghrib': _hm(t.maghrib),
      'Isha': _hm(t.isha),
    };
  } finally {
    malloc.free(key);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Map<String, String> times;

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
                for (final entry in times.entries)
                  Text('${entry.key}: ${entry.value}', style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
