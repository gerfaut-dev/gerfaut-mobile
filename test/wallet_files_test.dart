import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/wallet_files.dart';

import 'core_fixtures.dart';

void main() {
  // The core's reference JSON names every kind of material it reads.
  // A kind it adds, or one it drops, has to change what the help line
  // under "Import a file" promises.
  test('names each kind the core reads, once', () {
    final core = coreCases('RecognizedKind').keys.toList()..sort();
    final named = [
      for (final file in walletFiles)
        for (final kind in file.kinds) kind.id,
    ]..sort();
    expect(core, isNotEmpty);
    expect(named, core);
  });
}
