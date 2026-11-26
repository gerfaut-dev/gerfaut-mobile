// The files a wallet is imported from, said under "Import a file".

import 'models.dart';

/// A kind of file "Import a file" opens for a wallet: what it holds,
/// the extensions it comes under, and what the core reads it as.
class WalletFile {
  const WalletFile({
    required this.holds,
    required this.extensions,
    required this.kinds,
  });

  /// What the file holds, as the help line says it.
  final String holds;
  final List<String> extensions;

  /// What the core recognizes such a file as.
  final List<RecognizedKind> kinds;
}

/// The files a wallet is imported from. The picker opens any file, as
/// Android gives most of these no media type of their own; the core
/// reads what is in it. The line under "Import a file" comes from here.
const List<WalletFile> walletFiles = [
  WalletFile(
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
  WalletFile(
    holds: 'a wallet export',
    extensions: ['.json'],
    kinds: [RecognizedKind.walletExport],
  ),
  WalletFile(
    holds: 'a BSMS record',
    extensions: ['.bsms'],
    kinds: [RecognizedKind.bsms],
  ),
];

/// The line under "Import a file": each content, then its extensions.
final String walletFileHint =
    'Reads ${_orList([for (final file in walletFiles) '${file.holds} (${file.extensions.join(', ')})'])}.';

/// "a, b, or c"; "a or b"; "a".
String _orList(List<String> items) {
  if (items.length < 3) return items.join(' or ');
  return '${items.sublist(0, items.length - 1).join(', ')}, or ${items.last}';
}
