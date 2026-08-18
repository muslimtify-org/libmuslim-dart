import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';

// A build hook's stdout IS its log: `dart build` and `flutter build` surface
// what it prints. Routing this through a logging package would hide it.
// ignore_for_file: avoid_print

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Flutter runs this hook with no asset types requested on `flutter run`'s
    // hot-reload path, and the input it sends then carries no `extensions`
    // object at all. Reading `input.config.code` in that state dereferences
    // null inside CodeConfig and takes the whole build down with it, so there
    // is nothing to build here and saying so early is the whole fix.
    if (!input.config.buildCodeAssets) return;

    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: ['src/prayertimes.c', 'src/abi_probe.c'],
      // _Static_assert in abi_probe.c needs an explicit C11 baseline rather
      // than whatever the host compiler defaults to.
      std: 'c11',
      // prayertimes.h uses sin/cos/atan2 from libm. Windows folds the math
      // functions into the CRT and has no separate libm to link.
      libraries: input.config.code.targetOS == OS.windows ? const [] : const ['m'],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = .ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
