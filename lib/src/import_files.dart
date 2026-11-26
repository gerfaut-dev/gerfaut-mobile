// The files the "Import a file" buttons open, said under each of them.

import 'models.dart';

/// A kind of file an "Import a file" button opens: what it holds, the
/// extensions it comes under, and what the core reads it as.
class ImportFile<K> {
  const ImportFile({
    required this.holds,
    required this.extensions,
    required this.kinds,
  });

  /// What the file holds, as the help line says it.
  final String holds;
  final List<String> extensions;

  /// What the core reads such a file as.
  final List<K> kinds;
}

/// The line under an "Import a file" button: each content, then its
/// extensions.
String hintOf<K>(List<ImportFile<K>> files) =>
    'Reads ${_orList([for (final file in files) '${file.holds} (${file.extensions.join(', ')})'])}.';

/// "a, b, or c"; "a or b"; "a".
String _orList(List<String> items) {
  if (items.length < 3) return items.join(' or ');
  return '${items.sublist(0, items.length - 1).join(', ')}, or ${items.last}';
}

// The pickers open any file, as Android gives most of these no media
// type of their own; the core reads what is in it. The lists below give
// the line under each button.

/// The files a wallet is imported from.
const List<ImportFile<RecognizedKind>> walletFiles = [
  ImportFile(
    holds: 'a descriptor, extended public key or address',
    extensions: ['.txt', '.desc'],
    kinds: [
      RecognizedKind.descriptor,
      RecognizedKind.descriptorPair,
      RecognizedKind.multipathDescriptor,
      RecognizedKind.extendedKey,
      RecognizedKind.address,
    ],
  ),
  ImportFile(
    holds: 'a wallet export',
    extensions: ['.json'],
    kinds: [RecognizedKind.walletExport],
  ),
  ImportFile(
    holds: 'a BSMS record',
    extensions: ['.bsms'],
    kinds: [RecognizedKind.bsms],
  ),
];

final String walletFileHint = hintOf(walletFiles);

/// The files a transaction to broadcast is imported from: binary as
/// signers save them, or written out as text. The core tells a PSBT
/// from a transaction by what the file holds, never by its name.
const List<ImportFile<TxSource>> transactionFiles = [
  ImportFile(holds: 'a PSBT', extensions: ['.psbt'], kinds: [TxSource.psbt]),
  ImportFile(
    holds: 'a signed transaction',
    extensions: ['.txn', '.tx'],
    kinds: [TxSource.rawTransaction],
  ),
  ImportFile(
    holds: 'either one as text',
    extensions: ['.txt', '.hex'],
    kinds: [TxSource.psbt, TxSource.rawTransaction],
  ),
];

final String transactionFileHint = hintOf(transactionFiles);
