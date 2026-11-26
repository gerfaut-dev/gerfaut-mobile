// What the app keeps of a wallet outside the vault, taken away once the
// vault has removed it. The core carries off its own records; what is
// left here is on screen, in memory, in the cache, or on the home screen.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'live.dart';
import 'notifications.dart';
import 'share.dart';
import 'state.dart';

/// Forgets [walletId] everywhere the app holds it, once the vault no
/// longer does.
///
/// - Notifications still up for it, and only those.
/// - Histories and backups shared into the cache, which name the wallet
///   or hold it, whatever their age.
/// - What the screens read of it: its snapshot, policy, coins, addresses
///   and transactions, where its sync stood, and the broadcasts the
///   core dropped with it, which the Broadcast screen lists.
/// - The home-screen widgets, which are written again from the wallets
///   the vault lists, so a removed name leaves them as the list is read.
///
/// Takes the [container] rather than a ref, since the screen that asks
/// may be left before the last step. A step that fails is no reason to
/// say the removal failed: the wallet is gone from the vault.
Future<void> forgetRemovedWallet(
  ProviderContainer container,
  String walletId,
) async {
  container.read(syncProvider.notifier).forget(walletId);
  container
    ..invalidate(snapshotProvider(walletId))
    ..invalidate(policyProvider(walletId))
    ..invalidate(utxosProvider(walletId))
    ..invalidate(addressListProvider(walletId))
    ..invalidate(walletCoverageProvider(walletId))
    // Keyed by more than the wallet: all of them are read again.
    ..invalidate(txDetailProvider)
    ..invalidate(receiveProvider)
    // The core drops the broadcasts that touch the wallet: the list read
    // before still shows them.
    ..invalidate(recentBroadcastsProvider)
    // Last: its new value is what the widgets are written from.
    ..invalidate(walletsProvider);
  Future<void> quietly(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // Nothing to reach, as in a test, or a platform that refused.
    }
  }

  await quietly(
    () => container.read(notificationServiceProvider).cancelForWallet(walletId),
  );
  // Not waited for: the disk is slow to list, and the removal is done.
  unawaited(quietly(() => container.read(sharedCopiesProvider).sweepAll()));
}
