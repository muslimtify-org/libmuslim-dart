import 'dart:io';

/// Regenerates the ffigen bindings for every module under `ffigen/`.
///
/// This exists because libclang does not always locate its own resource
/// directory. When it does not, parsing `/usr/include/string.h` fails with
/// `stddef.h: file not found` and ffigen exits 1 having written nothing
/// useful. Supplying the directory through CPATH fixes it, and asking clang
/// for the path rather than hardcoding one keeps this working across clang
/// versions and machines.
///
/// Run it with `dart run tool/regen.dart`.
Future<void> main() async {
  final environment = <String, String>{};

  final probe = await Process.run('clang', ['-print-resource-dir']);
  if (probe.exitCode == 0) {
    final include = '${(probe.stdout as String).trim()}/include';
    final existing = Platform.environment['CPATH'];
    environment['CPATH'] = (existing == null || existing.isEmpty)
        ? include
        : '$include${Platform.isWindows ? ';' : ':'}$existing';
  } else {
    stderr.writeln(
      'warning: `clang -print-resource-dir` failed; running ffigen without '
      'CPATH. If generation fails on a missing stddef.h, this is why.',
    );
  }

  final configs =
      Directory('ffigen')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (configs.isEmpty) {
    stderr.writeln('no ffigen configs found under ffigen/');
    exit(1);
  }

  for (final config in configs) {
    stdout.writeln('regenerating from ${config.path}');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ffigen',
      '--config',
      config.path,
    ], environment: environment);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) exit(result.exitCode);
  }
}
