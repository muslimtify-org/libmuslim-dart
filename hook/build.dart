import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: ['src/prayertimes.c', 'src/abi_probe.c', 'src/$packageName.c'],
      // _Static_assert in abi_probe.c needs an explicit C11 baseline rather
      // than whatever the host compiler defaults to. gnu11 (not strict c11)
      // keeps the POSIX/GNU extension macros (e.g. usleep in the template's
      // libmuslim_dart.c) visible, which strict c11 hides.
      std: 'gnu11',
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
