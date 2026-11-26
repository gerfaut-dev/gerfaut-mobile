import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/import_files.dart';

import 'core_fixtures.dart';

void main() {
  // The core's reference JSON names everything it reads from a file. A
  // kind it adds, or one it drops, has to change what the help line
  // under "Import a file" promises.
  test('names each kind of wallet material the core reads, once', () {
    final core = coreCases('RecognizedKind').keys.toList()..sort();
    final named = [
      for (final file in walletFiles)
        for (final kind in file.kinds) kind.id,
    ]..sort();
    expect(core, isNotEmpty);
    expect(named, core);
  });

  test('names each form of transaction the core reads', () {
    final core = coreCases('TxSource').keys.toSet();
    final named = {
      for (final file in transactionFiles)
        for (final source in file.kinds) source.id,
    };
    expect(core, isNotEmpty);
    expect(named, core);
  });
}
