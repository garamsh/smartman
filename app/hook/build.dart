import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await const FlutterRustBridgeNativeAssetsBuilder(
      // The bindings live in the study domain (docs/architecture/adr/0004-*).
      assetName: 'study/src/rust/frb_generated.io.dart',
      cratePath: 'rust',
    ).run(input: input, output: output);
  });
}
