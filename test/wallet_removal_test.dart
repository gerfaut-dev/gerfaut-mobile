import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/home_widgets.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/share.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

/// The notifications up on the screen, each with the wallet it was
/// posted for.
class _Screen implements NotificationService {
  final List<({int id, String body, String? walletId})> up = [];

  @override
  Future<void> show(
    int id,
    String title,
    String body, {
    String? walletId,
  }) async => up.add((id: id, body: body, walletId: walletId));

  @override
  Future<void> cancelForWallet(String walletId) async =>
      up.removeWhere((notice) => notice.walletId == walletId);

  @override
  Future<void> cancelAll() async => up.clear();

  @override
  Future<bool> deliverable() async => true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;
}

/// A vault that, like the core, drops the transactions sent that touch a
/// wallet when it removes the wallet.
class _Core extends FakeBridge {
  _Core({super.wallets, super.snapshots, super.settings});

  @override
  Future<void> removeWallet(String id) async {
    await super.removeWallet(id);
    keptBroadcasts.clear();
  }
}

const _sent = RecentBroadcast(
  txid: 'aa',
  network: Network.mainnet,
  hex: '0200000001deadbeef',
  backend: 'mempool.space',
  at: 1755000000,
);

/// A cache that records the call to clear it, where the real one reads
/// the disk.
class _Cache extends SharedCopySweeper {
  int cleared = 0;

  @override
  Future<int> sweepAll() async => cleared++;
}

void main() {
  testWidgets('removing a wallet leaves nothing of it that the app holds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cold = makeMeta(id: 'w1', name: 'Cold storage');
    final spending = makeMeta(id: 'w2', name: 'Spending');
    final bridge = _Core(
      wallets: [cold, spending],
      snapshots: {
        'w1': makeSnapshot(meta: cold),
        'w2': makeSnapshot(meta: spending),
      },
      settings: const Settings(
        preferences: kPreferences,
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'onboarding.seen': '1'},
      ),
    )..keptBroadcasts.add(_sent);
    final screen = _Screen();
    final cache = _Cache();
    final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          notificationServiceProvider.overrideWithValue(screen),
          sharedCopiesProvider.overrideWithValue(cache),
          widgetBoardProvider.overrideWithValue(board),
          widgetSchedulerProvider.overrideWithValue((wanted) async {}),
        ],
        child: creditedApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const SettingsScreen(section: SettingsSection.wallets),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    container.read(widgetFeedProvider);
    await tester.pumpAndSettle();

    // What the app holds of both wallets before one goes.
    final announcer = NewTxAnnouncer(screen, bridge);
    await announcer.announce(
      const [
        LiveTx(
          walletId: 'w1',
          txid: 'a',
          netSats: 5000,
          stage: TxStage.mempool,
        ),
        LiveTx(
          walletId: 'w2',
          txid: 'b',
          netSats: 7000,
          stage: TxStage.mempool,
        ),
      ],
      const NoticeContext(
        names: {'w1': 'Cold storage', 'w2': 'Spending'},
        unit: AmountUnit.btc,
        masked: false,
        details: true,
      ),
    );
    await container.read(snapshotProvider('w1').future);
    await container.read(snapshotProvider('w2').future);
    expect(
      await container.read(recentBroadcastsProvider(Network.mainnet).future),
      [_sent],
    );
    container
        .read(syncProvider.notifier)
        .syncedElsewhere('w1', failure: 'unreachable');
    container.read(syncProvider.notifier).syncedElsewhere('w2');
    expect(board.data[WidgetKeys.balanceRowName(1)], 'Cold storage');
    expect(screen.up.map((n) => n.walletId), unorderedEquals(['w1', 'w2']));

    await tester.tap(find.text('Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove wallet'));
    await tester.pumpAndSettle();
    expect(bridge.wallets.map((w) => w.id), ['w2']);

    // The notifications of that wallet are off the screen, the other
    // wallet's still up.
    expect(screen.up.map((n) => n.walletId), ['w2']);
    // Its copies in the cache are gone.
    expect(cache.cleared, 1);
    // Nothing of it is kept in memory; the other wallet is left alone.
    // Read again, it asks the vault, which no longer knows it.
    await expectLater(
      container.read(snapshotProvider('w1').future),
      throwsA(isA<BridgeException>()),
    );
    expect((await container.read(snapshotProvider('w2').future)).meta.id, 'w2');
    expect(container.read(syncProvider).wallets.keys, ['w2']);
    expect(container.read(syncErrorsProvider), isEmpty);
    // The broadcasts the vault dropped with it are not listed from the
    // list read before.
    expect(
      await container.read(recentBroadcastsProvider(Network.mainnet).future),
      isEmpty,
    );
    // The widget is written again from the wallets that are left.
    expect(board.data[WidgetKeys.balanceRowName(1)], 'Spending');
    expect(board.data[WidgetKeys.balanceRowName(2)], isNull);
    expect(board.data.values, isNot(contains('Cold storage')));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test(
    'the shared copies of histories and backups all go, young or old',
    () async {
      final cache = Directory.systemTemp.createTempSync('gerfaut-share-');
      addTearDown(() => cache.deleteSync(recursive: true));
      final folder = Directory('${cache.path}/$sharedFolder/one')
        ..createSync(recursive: true);
      File('${folder.path}/Cold storage-transactions.csv')
          .writeAsStringSync('x');
      File('${cache.path}/old-transactions.csv').writeAsStringSync('x');
      File('${cache.path}/all.gerfaut').writeAsStringSync('x');
      File('${cache.path}/unrelated.txt').writeAsStringSync('x');
      final sweeper = SharedCopySweeper(cache: cache);
      addTearDown(sweeper.cancel);

      // Every copy is minutes old: the hour has not passed.
      expect(await sweeper.sweep(), 0);
      expect(await sweeper.sweepAll(), 3);
      expect(File('${cache.path}/unrelated.txt').existsSync(), isTrue);
      expect(folder.existsSync(), isFalse);
    },
  );
}
