import 'package:test/test.dart';

import 'package:libmuslim_dart/libmuslim_dart.dart';

void main() {
  test('invoke native function', () {
    expect(sum(24, 18), 42);
  });

  test('invoke async native callback', () async {
    expect(await sumAsync(24, 18), 42);
  });
}
