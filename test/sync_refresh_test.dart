import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/lock_screen.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/sync_refresh.dart';
import 'package:gerfaut/src/window.dart';

import 'fakes.dart';

final _start = DateTime.utc(2026, 11, 18, 12);

SyncStamp _at(DateTime when) => SyncStamp(
  at: when.millisecondsSinceEpoch ~/ 1000,
  tipHeight: 100,
  backend: 'mempool.space',
);

/// A wallet whose last sync is an hour old when the test starts.
WalletMeta _old({String id = 'w1', Network network = Network.mainnet}) =>
    makeMeta(
      id: id,
      network: network,
      lastSync: _at(_start.subtract(const Duration(hours: 1))),
    );

/// A vault opened before, on [wallets], whose syncs of every wallet all
/// fail: no such sync makes a figure fresh, and only the spacing of the
/// tries is left. The network of each is kept in [asked].
FakeBridge _failing(List<WalletMeta> wallets, {List<Network?>? asked}) {
  return FakeBridge(
      wallets: wallets,
      settings: const Settings(
        preferences: kPreferences,
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'onboarding.seen': '1'},
      ),
    )
    ..onSyncAll = (network) {
      asked?.add(network);
      return SyncAllReport(
        reports: const [],
        failures: [
          for (final wallet in wallets)
            SyncFailure(walletId: wallet.id, message: 'timed out'),
        ],
      );
    };
}

/// The app on [bridge], its syncs timed by a clock the test moves along
/// with the timers.
class _Open {
  _Open(this.tester, this.bridge);

  final WidgetTester tester;
  final FakeBridge bridge;
  DateTime now = _start;

  Future<void> launch({List<Override> overrides = const []}) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          syncProvider.overrideWith(() => SyncController(clock: () => now)),
          ...overrides,
        ],
        child: const GerfautApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

  /// Lets [minutes] go by, a minute at a time, the clock with them.
  Future<void> wait(int minutes) async {
    for (var i = 0; i < minutes; i++) {
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
    }
  }

  int get syncs => bridge.syncAllCalls;
}

void main() {
  group('when an open app is due a sync of every wallet', () {
    final now = _start;
    WalletMeta synced(Duration ago, {String id = 'w1'}) =>
        makeMeta(id: id, lastSync: _at(now.subtract(ago)));
    bool due(
      List<WalletMeta> wallets, {
      WalletSyncs syncs = const WalletSyncs(),
      Network network = Network.mainnet,
    }) => syncRefreshDue(wallets, network: network, syncs: syncs, now: now);
    WalletSyncs endedAt(DateTime at, {Network network = Network.mainnet}) =>
        WalletSyncs(syncedAllAt: {network: at});

    test('once the least fresh wallet last synced ten minutes ago', () {
      final fresh = synced(Duration.zero, id: 'w2');
      expect(
        due([fresh, synced(const Duration(minutes: 9, seconds: 59))]),
        isFalse,
      );
      expect(due([fresh, synced(const Duration(minutes: 10))]), isTrue);
    });

    test('at once for a wallet that never synced', () {
      expect(due([synced(Duration.zero), makeMeta(id: 'w2')]), isTrue);
    });

    test('never with no wallet', () {
      expect(due(const []), isFalse);
    });

    test('ten minutes after the last one ended, not after it began', () {
      final old = [synced(const Duration(hours: 1))];
      expect(
        due(old, syncs: endedAt(now.subtract(const Duration(minutes: 9)))),
        isFalse,
      );
      expect(
        due(old, syncs: endedAt(now.subtract(const Duration(minutes: 10)))),
        isTrue,
      );
    });

    test('not while any sync of the wallets on screen runs', () {
      final old = [synced(const Duration(hours: 1))];
      const ticket = 1;
      final ofAll = nextSyncs(
        const WalletSyncs(),
        const SyncAllStarted(ticket),
      );
      final ofOne = nextSyncs(const WalletSyncs(), const SyncStarted('w1', 1));
      final told = nextSyncs(const WalletSyncs(), const CoreSyncStarted('w1'));
      final elsewhere = nextSyncs(
        const WalletSyncs(),
        const CoreSyncStarted('w9'),
      );
      expect(due(old, syncs: ofAll), isFalse);
      expect(due(old, syncs: ofOne), isFalse);
      expect(due(old, syncs: told), isFalse);
      // A wallet of another network syncing holds nothing back here.
      expect(due(old, syncs: elsewhere), isTrue);
    });

    test('a sync of another network holds nothing back', () {
      final old = [synced(const Duration(hours: 1))];
      expect(due(old, syncs: endedAt(now, network: Network.signet)), isTrue);
    });

    test('a clock set back does not stop it', () {
      // The last sync ended, by the clock now, an hour from now.
      expect(
        due([
          synced(const Duration(hours: 1)),
        ], syncs: endedAt(now.add(const Duration(hours: 1)))),
        isTrue,
      );
      // A wallet stamped an hour ahead of the clock.
      expect(due([synced(const Duration(hours: -1))]), isTrue);
    });
  });

  test('a sync of every wallet keeps when it ended, by network', () {
    final mainnetEnd = _start;
    final signetEnd = _start.add(const Duration(minutes: 3));
    var syncs = nextSyncs(const WalletSyncs(), const SyncAllStarted(1));
    syncs = nextSyncs(
      syncs,
      SyncAllEnded(1, const {}, Network.mainnet, mainnetEnd),
    );
    syncs = nextSyncs(syncs, const SyncAllStarted(2));
    // Still running: when the last one ended is unchanged.
    expect(syncs.syncedAllAt, {Network.mainnet: mainnetEnd});
    syncs = nextSyncs(
      syncs,
      SyncAllEnded(2, const {}, Network.signet, signetEnd),
    );
    expect(syncs.syncedAllAt, {
      Network.mainnet: mainnetEnd,
      Network.signet: signetEnd,
    });
  });

  test('a sync is as old as the clock is off from it, either way', () {
    final stamp = _at(_start);
    bool olderThanTen(Duration off) =>
        stamp.olderThan(const Duration(minutes: 10), now: _start.add(off));
    expect(olderThanTen(const Duration(minutes: 9)), isFalse);
    expect(olderThanTen(const Duration(minutes: 10)), isTrue);
    expect(olderThanTen(const Duration(minutes: -9)), isFalse);
    expect(olderThanTen(const Duration(minutes: -10)), isTrue);
  });

  group('an open app syncs its wallets on its own', () {
    testWidgets('a failure is tried again ten minutes on, not before', (
      tester,
    ) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      // The sync of the start, once per launch, whatever came before.
      expect(open.syncs, 1);

      await open.wait(9);
      expect(open.syncs, 1);
      await open.wait(2);
      expect(open.syncs, 2);

      await open.wait(8);
      expect(open.syncs, 2);
      await open.wait(3);
      expect(open.syncs, 3);
    });

    testWidgets('a long sync is followed by ten minutes, not another', (
      tester,
    ) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      final gate = open.bridge.syncAllGate = Completer<void>();
      await open.wait(11);
      expect(open.syncs, 2);
      // A server that takes a quarter of an hour to answer.
      await open.wait(15);
      expect(open.syncs, 2);

      gate.complete();
      await tester.pump();
      await open.wait(9);
      expect(open.syncs, 2);
      await open.wait(2);
      expect(open.syncs, 3);
    });

    testWidgets('waits for the least fresh wallet to be ten minutes old', (
      tester,
    ) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      await open.wait(5);

      // Live syncs the wallet meanwhile, and the list is read again.
      open.bridge.wallets = [makeMeta(lastSync: _at(open.now))];
      open.container.invalidate(walletsProvider);
      await tester.pump();

      // Ten minutes after the start, the figure is only five old.
      await open.wait(9);
      expect(open.syncs, 1);
      await open.wait(2);
      expect(open.syncs, 2);
    });

    testWidgets('waits for the sync of one wallet to end', (tester) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      await open.wait(9);

      final gate = open.bridge.syncGate = Completer<void>();
      final own = open.container.read(syncProvider.notifier).syncWallet('w1');
      await tester.pump();
      await open.wait(3);
      expect(open.syncs, 1);

      gate.complete();
      await own;
      await open.wait(2);
      expect(open.syncs, 2);
    });

    testWidgets('a sync asked by hand counts as a try', (tester) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      await open.wait(5);
      await tester.tap(find.byTooltip('Sync'));
      await tester.pump();
      expect(open.syncs, 2);

      await open.wait(9);
      expect(open.syncs, 2);
      await open.wait(2);
      expect(open.syncs, 3);
    });

    testWidgets('the network just switched to is not held back by the last', (
      tester,
    ) async {
      final asked = <Network?>[];
      final open = _Open(
        tester,
        _failing([
          _old(),
          _old(id: 'w2', network: Network.signet),
        ], asked: asked),
      );
      await open.launch();
      await open.wait(2);

      await open.bridge.setActiveNetwork(Network.signet);
      open.container.invalidate(settingsProvider);
      await tester.pumpAndSettle();
      await open.wait(2);
      expect(asked, [Network.mainnet, Network.signet]);
    });

    testWidgets('a list being read again is not decided on', (tester) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      await open.wait(9);

      // A sync of the wallet alone lands a fresh figure, and the list
      // that brings it is still on its way when the look comes.
      open.bridge.wallets = [makeMeta(lastSync: _at(open.now))];
      final reading = open.bridge.walletsGate = Completer<void>();
      await open.container.read(syncProvider.notifier).syncWallet('w1');
      await open.wait(2);
      expect(open.syncs, 1);

      reading.complete();
      await open.wait(5);
      expect(open.syncs, 1);
    });

    testWidgets('nothing out of sight, and a look the moment it is back', (
      tester,
    ) async {
      final open = _Open(tester, _failing([_old()]));
      await open.launch();
      final inFront = open.container.read(appInFrontProvider.notifier);

      inFront.put(false);
      await tester.pump();
      await open.wait(30);
      expect(open.syncs, 1);

      inFront.put(true);
      await tester.pump();
      expect(open.syncs, 2);
    });

    testWidgets('nothing behind the lock the app comes back to', (
      tester,
    ) async {
      final open = _Open(
        tester,
        _failing([_old()])
          ..lock = const AppLock(kind: LockKind.pin, biometric: false)
          ..lockSecret = '1234',
      );
      await open.launch(
        overrides: [
          biometricGateProvider.overrideWithValue(
            FakeBiometrics(available: false),
          ),
          windowGuardProvider.overrideWithValue(FakeWindowGuard()),
        ],
      );
      await unlockWithPin(tester, '1234');
      expect(open.syncs, 1);
      lockOnEveryTrip(open.container);

      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await open.wait(11);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await open.wait(2);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(open.syncs, 1);
    });

    testWidgets('nothing with no wallet', (tester) async {
      final open = _Open(tester, _failing(const []));
      await open.launch();
      await open.wait(30);
      expect(open.syncs, 0);
    });

    testWidgets('a wallet page over the home goes by the same rule', (
      tester,
    ) async {
      final meta = _old();
      final open = _Open(tester, _failing([meta]))
        ..bridge.snapshots['w1'] = makeSnapshot(meta: meta);
      await open.launch();
      await tester.tap(find.text('Cold storage'));
      await tester.pumpAndSettle();

      await open.wait(11);
      expect(open.syncs, 2);

      // The page stays open while the app is out of sight.
      final inFront = open.container.read(appInFrontProvider.notifier);
      inFront.put(false);
      await tester.pump();
      await open.wait(30);
      expect(open.syncs, 2);

      inFront.put(true);
      await tester.pump();
      expect(open.syncs, 3);
    });
  });
}
