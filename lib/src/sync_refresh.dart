// The sync an open app runs on its own: the figures on screen stay
// recent without anyone pulling the list down.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'disguise.dart';
import 'lock.dart';
import 'models.dart';
import 'state.dart';

/// How often the wallets are synced again while the app is open on
/// them. Live hears only what moves, and not always every wallet: an
/// open app that waited on it alone would show figures hours old.
const Duration syncRefreshEvery = Duration(minutes: 10);

/// How often the rule is looked at while the app stays open: a due
/// sync starts within this much of falling due.
const Duration _lookEvery = Duration(minutes: 1);

/// Whether [wallets], those of [network] on screen, are due a sync of
/// them all at [now], as [syncs] stand: one of them last synced
/// [syncRefreshEvery] ago or more, or never; no sync covers any of
/// them, of one wallet or of every wallet; and the last sync of every
/// wallet of [network] ended [syncRefreshEvery] ago or more, whoever
/// asked for it and whatever came of it. Counted from its end, a pass
/// that took longer than the spacing still waits the whole of it: a
/// failure is tried again no sooner than a success, and a slow server
/// is never synced back to back. A clock set back counts the gap by
/// its size, as [SyncStamp.olderThan] does.
bool syncRefreshDue(
  List<WalletMeta> wallets, {
  required Network network,
  required WalletSyncs syncs,
  required DateTime now,
}) {
  if (syncs.syncingAnyOf(wallets.map((wallet) => wallet.id))) return false;
  final ended = syncs.syncedAllAt[network];
  if (ended != null && now.difference(ended).abs() < syncRefreshEvery) {
    return false;
  }
  return wallets.any((wallet) {
    final stamp = wallet.lastSync;
    return stamp == null || stamp.olderThan(syncRefreshEvery, now: now);
  });
}

/// Syncs every wallet of the network on screen when [syncRefreshDue]
/// says so, as the sync button would. Looked at as soon as the app is
/// on screen, then every minute while it stays there; out of sight, no
/// clock runs and nothing reaches the core.
///
/// The home listens to it for as long as it is mounted, under the
/// pages pushed over it too: their figures are the same.
class SyncRefresh extends Notifier<void> {
  @override
  void build() {
    if (!ref.watch(appInFrontProvider)) return;
    final timer = Timer.periodic(_lookEvery, (_) => _look());
    ref.onDispose(timer.cancel);
    // At once, but off the build: starting a sync moves provider state,
    // which a build in progress must not. A clock stopped meanwhile, the
    // app gone again, takes the look with it.
    scheduleMicrotask(() {
      if (timer.isActive) _look();
    });
  }

  void _look() {
    // Asked here and not left to the home leaving the tree: back on
    // screen, the lock closes a beat before the home goes, and this
    // look may come in between. The gate shows nothing but its startup
    // screen until the lock and the disguise are known.
    final lock = ref.read(lockProvider);
    if (!lock.loaded || lock.locked || !ref.read(disguiseProvider).loaded) {
      return;
    }
    // A list or settings being read again still hold the old ones: the
    // figures from before a sync, the wallets of the network just left.
    // The next look has the new ones.
    final settings = ref.read(settingsProvider);
    final wallets = ref.read(walletsProvider);
    if (settings.isLoading || wallets.isLoading) return;
    final network = settings.value?.activeNetwork;
    final listed = wallets.value;
    if (network == null || listed == null) return;
    final sync = ref.read(syncProvider.notifier);
    final due = syncRefreshDue(
      listed,
      network: network,
      syncs: ref.read(syncProvider),
      now: sync.clock(),
    );
    if (!due) return;
    // A sync of every wallet that did not answer at all leaves each
    // wallet as the core said it stands, as it does from the button,
    // and ends all the same: the next one waits its ten minutes.
    unawaited(sync.syncAll(network).then((_) {}, onError: (Object _) {}));
  }
}

final syncRefreshProvider = NotifierProvider.autoDispose<SyncRefresh, void>(
  SyncRefresh.new,
);
