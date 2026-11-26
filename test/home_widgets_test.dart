import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings/widgets_section.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/home_widgets.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/setting_switch.dart';

import 'fakes.dart';

const int _syncedAt = 1755000000;

/// Two hours after the most recent sync of the fixtures.
final DateTime _now = DateTime.fromMillisecondsSinceEpoch(
  (_syncedAt + 7200) * 1000,
);

/// [t] in unix seconds. Tests build their moments in local time, so a
/// day stays the same day in whatever zone they run.
int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Empty balance and network payloads, for a write about the price.
final BalancePayload _noBalance = BalancePayload.of(
  const [],
  unit: AmountUnit.btc,
  masked: true,
);
final NetworkPayload _noNetwork = NetworkPayload.of(
  const [],
  network: Network.mainnet,
);

SyncStamp _stamp(int at, {int tipHeight = 912345}) =>
    SyncStamp(at: at, tipHeight: tipHeight, backend: 'mempool.space');

const PriceQuote _quote = PriceQuote(
  rate: 50000,
  currency: FiatCurrency('eur'),
  source: PriceSource.mempoolSpace,
  at: _syncedAt,
);

/// A vault opened before, on mainnet, with two synced wallets.
FakeBridge _bridge({List<WalletMeta>? wallets}) {
  return FakeBridge(
    wallets:
        wallets ??
        [
          makeMeta(
            id: 'a',
            name: 'Cold storage',
            totalSats: 100000000,
            lastSync: _stamp(_syncedAt - 60),
          ),
          makeMeta(
            id: 'b',
            name: 'Spending',
            totalSats: 50000,
            lastSync: _stamp(_syncedAt),
          ),
        ],
    settings: const Settings(
      preferences: kPreferences,
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
  );
}

/// A container with the feed running against fakes, its providers
/// settled, so a test reads the board rather than a race.
Future<({ProviderContainer container, WidgetFeed feed})> _running(
  FakeBridge bridge,
  FakeWidgetBoard board, {
  List<bool>? scheduled,
}) async {
  final container = ProviderContainer(
    retry: noRetry,
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      widgetBoardProvider.overrideWithValue(board),
      widgetSchedulerProvider.overrideWithValue(
        (wanted) async => scheduled?.add(wanted),
      ),
    ],
  );
  addTearDown(container.dispose);
  final feed = container.read(widgetFeedProvider);
  await container.read(walletsProvider.future);
  await container.read(widgetPriceProvider.future);
  await feed.publish();
  return (container: container, feed: feed);
}

void main() {
  group('the price widget', () {
    test('states one bitcoin in the currency and the clock time', () {
      final payload = PricePayload.of(
        _quote,
        kPriceTable,
        now: DateTime.fromMillisecondsSinceEpoch(_syncedAt * 1000),
      );
      expect(payload.figure, '€50 000');
      expect(payload.asOf, 'as of ${formatClock(_syncedAt)}');
      expect(payload.asOfNarrow, isNull);
      // The core carries no daily change yet: the line stays hidden.
      expect(payload.toData()[WidgetKeys.priceChange], isNull);
      expect(payload.toData()[WidgetKeys.priceAt], '$_syncedAt');
      expect(payload.toData().keys, PricePayload.keys);
      // mempool.space asks for no credit: the line stays hidden.
      expect(payload.toData()[WidgetKeys.priceCredit], isNull);
      expect(payload.toData()[WidgetKeys.priceSource], 'mempool_space');
    });

    test('carries the credit its source asks for, word for word', () {
      const quote = PriceQuote(
        rate: 7738073,
        currency: FiatCurrency('inr'),
        source: PriceSource.coingecko,
        at: _syncedAt,
      );
      final data = PricePayload.of(quote, kPriceTable).toData();
      expect(data[WidgetKeys.priceCredit], 'Powered by CoinGecko');
      expect(data[WidgetKeys.priceSource], 'coingecko');
    });

    test('a quote from today says its time alone', () {
      final at = _secs(DateTime(2026, 10, 3, 9, 41));
      for (final now in [
        DateTime(2026, 10, 3, 9, 41),
        DateTime(2026, 10, 3, 23, 59),
      ]) {
        expect(priceAsOf(at, now: now), (full: 'as of 09:41', narrow: null));
      }
    });

    test('a quote from another day says its day, and its time where it '
        'fits', () {
      final at = _secs(DateTime(2026, 10, 3, 9, 41));
      final yesterday = (full: 'as of Oct 03, 09:41', narrow: 'as of Oct 03');
      expect(priceAsOf(at, now: DateTime(2026, 10, 4, 0, 1)), yesterday);
      expect(priceAsOf(at, now: DateTime(2026, 12, 31, 23, 59)), yesterday);
      final data = PricePayload.of(
        PriceQuote(
          rate: 50000,
          currency: FiatCurrency('eur'),
          source: PriceSource.coingecko,
          at: at,
        ),
        kPriceTable,
        now: DateTime(2026, 10, 4, 8),
      ).toData();
      expect(data[WidgetKeys.priceAsOf], 'as of Oct 03, 09:41');
      expect(data[WidgetKeys.priceAsOfNarrow], 'as of Oct 03');
    });

    test('a quote from another year says its year in place of the time', () {
      // The year is never the part a narrow widget drops: "as of Dec 31"
      // would read as this year's.
      final at = _secs(DateTime(2025, 12, 31, 23, 50));
      expect(priceAsOf(at, now: DateTime(2026, 1, 1, 0, 5)), (
        full: 'as of Dec 31, 2025',
        narrow: null,
      ));
    });

    test('a euro quote drops its cents, as the app does', () {
      // The widget once said "€66,741.00" beside an app saying "€66,394":
      // the cents of a five-figure price are noise on both.
      const quote = PriceQuote(
        rate: 66741.37,
        currency: FiatCurrency('eur'),
        source: PriceSource.mempoolSpace,
        at: _syncedAt,
      );
      expect(PricePayload.of(quote, kPriceTable).figure, '€66 741');
      expect(formatFiatPrice(66741.37, FiatCurrency('eur')), '€66 741');
      expect(formatFiatPrice(9876543.2, FiatCurrency('jpy')), '¥9 876 543');
      // Under a hundred the currency keeps its own decimals.
      expect(formatFiatPrice(42.5, FiatCurrency('eur')), '€42.50');
    });

    test('the clock is the reader\'s, on 24 hours', () {
      final local = DateTime.fromMillisecondsSinceEpoch(_syncedAt * 1000)
          .toLocal();
      final expected =
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
      expect(formatClock(_syncedAt), expected);
      expect(formatClock(_syncedAt), matches(RegExp(r'^\d\d:\d\d$')));
    });
  });

  group('the balance widget', () {
    final wallets = [
      makeMeta(id: 'a', name: 'Cold storage', totalSats: 100000000),
      makeMeta(
        id: 'b',
        name: 'Spending',
        totalSats: 50000,
        lastSync: _stamp(_syncedAt),
      ),
    ];

    test('totals the wallets in the display unit', () {
      final btc = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        now: _now,
      );
      expect(btc.total, '1.00050000 BTC');
      expect(btc.rows, [
        (name: 'Cold storage', figure: '1.00000000 BTC'),
        (name: 'Spending', figure: '0.00050000 BTC'),
      ]);

      final sats = BalancePayload.of(
        wallets,
        unit: AmountUnit.sats,
        masked: false,
        now: _now,
      );
      expect(sats.total, formatSats(100050000));
      expect(sats.rows.first.figure, formatSats(100000000));
    });

    test('under an app lock, no name and no figure', () {
      final payload = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        locked: true,
        now: _now,
      );
      expect(payload.total, maskedValue);
      expect(payload.rows, isEmpty);
      final data = payload.toData();
      expect(data[WidgetKeys.balanceRowName(1)], isNull);
      expect(data[WidgetKeys.balanceRowFigure(1)], isNull);
      // When it was last brought up to date still shows.
      expect(payload.synced, isNotEmpty);
    });

    test('masked, the names stay and every figure goes', () {
      final payload = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: true,
        now: _now,
      );
      expect(payload.total, maskedValue);
      expect(payload.rows.map((row) => row.name), ['Cold storage', 'Spending']);
      expect(payload.rows.every((row) => row.figure == maskedValue), isTrue);

      // The mask changes the figures and nothing else: as many rows as
      // unmasked, every name written, and the freshness line with them.
      final open = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        now: _now,
      );
      expect(payload.rows, hasLength(open.rows.length));
      final data = payload.toData();
      expect(data[WidgetKeys.balanceRowName(1)], 'Cold storage');
      expect(data[WidgetKeys.balanceRowFigure(1)], maskedValue);
      expect(data[WidgetKeys.balanceRowName(2)], 'Spending');
      expect(data[WidgetKeys.balanceRowFigure(2)], maskedValue);
      expect(data[WidgetKeys.balanceSynced], 'Synced 2 h ago');
      expect(payload.synced, open.synced);
    });

    test('lists four wallets at most; the total counts them all', () {
      final many = [
        for (var i = 0; i < 6; i++)
          makeMeta(id: 'w$i', name: 'Wallet $i', totalSats: 1000),
      ];
      final payload = BalancePayload.of(
        many,
        unit: AmountUnit.sats,
        masked: false,
      );
      expect(payload.rows, hasLength(BalancePayload.maxRows));
      expect(payload.rows.last.name, 'Wallet 3');
      expect(payload.total, formatSats(6000));
      // Every row key is written, the unused ones as absent.
      final data = payload.toData();
      expect(data.keys, BalancePayload.keys);
      expect(data[WidgetKeys.balanceRowName(4)], 'Wallet 3');
      final two = BalancePayload.of(
        wallets,
        unit: AmountUnit.sats,
        masked: false,
      ).toData();
      expect(two[WidgetKeys.balanceRowName(3)], isNull);
      expect(two[WidgetKeys.balanceRowFigure(4)], isNull);
    });

    test('a wallet in its first sync shows a dash, and the total counts '
        'the others', () {
      // "Cold storage" has never synced, and its first sync runs.
      final syncing = nextSyncs(
        const WalletSyncs(),
        const CoreSyncStarted('a'),
      );
      final payload = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        syncs: syncing,
        now: _now,
      );
      expect(payload.rows, [
        (name: 'Cold storage', figure: '—'),
        (name: 'Spending', figure: '0.00050000 BTC'),
      ]);
      expect(payload.total, '0.00050000 BTC');
      // Another wallet has synced: the line dates that sync.
      expect(payload.synced, 'Synced 2 h ago');

      // Read again after the sync ended, the dash holds until it lands.
      final reading = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        refreshing: true,
        now: _now,
      );
      expect(reading.rows.first.figure, '—');

      // A first sync that failed says the vault's figure once it is over.
      final settled = nextSyncs(
        const WalletSyncs(),
        const CoreSyncSettled('a', 'refused'),
      );
      final failed = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        syncs: settled,
        now: _now,
      );
      expect(failed.rows.first.figure, '1.00000000 BTC');
      expect(failed.total, '1.00050000 BTC');

      // Tried again, it has no figure yet: the dash is back.
      final retried = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        syncs: nextSyncs(settled, const CoreSyncStarted('a')),
        now: _now,
      );
      expect(retried.rows.first.figure, '—');
      expect(retried.total, '0.00050000 BTC');

      // The mask and the lock go first too.
      final masked = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: true,
        syncs: syncing,
        now: _now,
      );
      expect(masked.rows.first.figure, maskedValue);
      expect(masked.total, maskedValue);
      final locked = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        locked: true,
        syncs: syncing,
        now: _now,
      );
      expect(locked.rows, isEmpty);
      expect(locked.total, maskedValue);
    });

    test('with every wallet in its first sync, the total is a dash and '
        'the line says the sync runs', () {
      final fresh = [
        makeMeta(id: 'a', name: 'Cold storage'),
        makeMeta(id: 'b', name: 'Spending'),
      ];
      final everyWallet = nextSyncs(
        const WalletSyncs(),
        const SyncAllStarted(1),
      );
      final payload = BalancePayload.of(
        fresh,
        unit: AmountUnit.sats,
        masked: false,
        syncs: everyWallet,
        now: _now,
      );
      expect(payload.total, '—');
      expect(payload.rows.map((row) => row.figure), ['—', '—']);
      expect(payload.synced, 'Syncing…');
      expect(
        NetworkPayload.of(
          fresh,
          network: Network.signet,
          syncs: everyWallet,
          now: _now,
        ).footer,
        'Signet · syncing…',
      );

      // Nothing runs: the zeros are the vault's, said as not synced yet.
      final idle = BalancePayload.of(
        fresh,
        unit: AmountUnit.sats,
        masked: false,
        now: _now,
      );
      expect(idle.total, formatSats(0));
      expect(idle.synced, 'Not synced yet');
      // No wallet at all is a known zero.
      expect(
        BalancePayload.of(
          const [],
          unit: AmountUnit.sats,
          masked: false,
          syncs: everyWallet,
        ).total,
        formatSats(0),
      );
    });

    test('dates the wallet synced longest ago, as the home screen does', () {
      // One wallet synced an hour before the other: the total adds both
      // up, so the older sync is the age of the total.
      final payload = BalancePayload.of(
        [
          makeMeta(
            id: 'a',
            name: 'Cold storage',
            lastSync: _stamp(_syncedAt - 3600),
          ),
          makeMeta(id: 'b', name: 'Spending', lastSync: _stamp(_syncedAt)),
        ],
        unit: AmountUnit.sats,
        masked: false,
        now: _now,
      );
      expect(payload.synced, 'Synced 3 h ago');
    });

    test('with no wallet, the line says so', () {
      final payload = BalancePayload.of(
        const [],
        unit: AmountUnit.sats,
        masked: false,
        now: _now,
      );
      expect(payload.synced, 'No wallets yet');
    });
  });

  group('the network widget', () {
    test('takes the height the latest sync saw', () {
      final wallets = [
        // Synced later but from a shorter chain view: the later stamp
        // wins, whatever its height.
        makeMeta(
          id: 'a',
          name: 'A',
          lastSync: _stamp(_syncedAt - 3600, tipHeight: 912400),
        ),
        makeMeta(id: 'b', name: 'B', lastSync: _stamp(_syncedAt)),
      ];
      final payload = NetworkPayload.of(
        wallets,
        network: Network.mainnet,
        now: _now,
      );
      expect(payload.height, groupThousands('912345'));
      // The footer dates the sync the height comes from, not the older.
      expect(payload.footer, 'Synced 2 h ago');
      // The height and its freshness, nothing else: no fee rate ever
      // reaches the launcher.
      expect(payload.toData().keys, NetworkPayload.keys);
      expect(NetworkPayload.keys, [
        WidgetKeys.networkHeight,
        WidgetKeys.networkFooter,
      ]);
    });

    test('names a network that is not the chain', () {
      final payload = NetworkPayload.of(
        [makeMeta(id: 'a', name: 'A', network: Network.signet)],
        network: Network.signet,
        now: _now,
      );
      expect(payload.height, '—');
      expect(payload.footer, 'Signet · not synced yet');
    });
  });

  group('the feed', () {
    test('writes every placed widget and asks it to redraw', () async {
      final board = FakeWidgetBoard(
        installed: {
          HomeWidgets.price,
          HomeWidgets.balance,
          HomeWidgets.network,
        },
      );
      await _running(_bridge(), board);

      // Fiat display is off in the app: the widget fetched its own quote
      // in the preferred currency all the same.
      expect(board.data[WidgetKeys.priceFigure], '€50 000');
      expect(board.data[WidgetKeys.priceAsOf], startsWith('as of '));
      expect(board.data.containsKey(WidgetKeys.priceChange), isFalse);
      // Masked until the widget preference says otherwise.
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
      expect(board.data[WidgetKeys.balanceRowName(1)], 'Cold storage');
      expect(board.data[WidgetKeys.balanceRowFigure(1)], maskedValue);
      expect(board.data[WidgetKeys.balanceSynced], startsWith('Synced '));
      expect(board.data[WidgetKeys.networkHeight], groupThousands('912345'));
      expect(board.data[WidgetKeys.networkFooter], startsWith('Synced '));
      expect(board.updates.toSet(), {
        HomeWidgets.price,
        HomeWidgets.balance,
        HomeWidgets.network,
      });
    });

    test('shows the balances once the preference is on, and hides them '
        'again while the app hides amounts', () async {
      final bridge = _bridge();
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      final (:container, :feed) = await _running(bridge, board);

      container.read(widgetBalancesProvider.notifier).set(true);
      await feed.publish();
      expect(bridge.appPrefs['widgets.balances'], '1');
      expect(board.data[WidgetKeys.balanceTotal], '1.00050000 BTC');
      expect(board.data[WidgetKeys.balanceRowFigure(2)], '0.00050000 BTC');

      container.read(maskedProvider.notifier).toggle();
      await feed.publish();
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);

      container.read(maskedProvider.notifier).toggle();
      container.read(unitProvider.notifier).set(AmountUnit.sats);
      await feed.publish();
      expect(board.data[WidgetKeys.balanceTotal], formatSats(100050000));
    });

    test('a first sync in the open app writes a dash until its wallet is '
        'read back', () async {
      final spending = makeMeta(
        id: 'b',
        name: 'Spending',
        totalSats: 50000,
        lastSync: _stamp(_syncedAt),
      );
      final bridge = _bridge(
        wallets: [
          makeMeta(id: 'a', name: 'Cold storage'),
          spending,
        ],
      );
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      final (:container, :feed) = await _running(bridge, board);
      container.read(widgetBalancesProvider.notifier).set(true);
      await feed.publish();
      expect(board.data[WidgetKeys.balanceRowFigure(1)], '0.00000000 BTC');

      final gate = Completer<void>();
      bridge.syncGate = gate;
      final sync = container.read(syncProvider.notifier).syncWallet('a');
      await feed.publish();
      expect(board.data[WidgetKeys.balanceRowFigure(1)], '—');
      expect(board.data[WidgetKeys.balanceTotal], '0.00050000 BTC');

      // The sync ends; the list it fetched is still being read.
      bridge.wallets = [
        makeMeta(id: 'a', name: 'Cold storage', totalSats: 100000000),
        spending,
      ];
      final reading = Completer<void>();
      bridge.walletsGate = reading;
      gate.complete();
      await sync;
      await feed.publish();
      expect(board.data[WidgetKeys.balanceRowFigure(1)], '—');

      reading.complete();
      await container.read(walletsProvider.future);
      await feed.publish();
      expect(board.data[WidgetKeys.balanceRowFigure(1)], '1.00000000 BTC');
      expect(board.data[WidgetKeys.balanceTotal], '1.00050000 BTC');
    });

    test('only a first sync that starts is worth a write of its own', () async {
      final bridge = _bridge(
        wallets: [
          makeMeta(id: 'a', name: 'Cold storage'),
          makeMeta(
            id: 'b',
            name: 'Spending',
            totalSats: 50000,
            lastSync: _stamp(_syncedAt),
          ),
        ],
      );
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      final (:container, feed: _) = await _running(bridge, board);
      await pumpEventQueue();
      final quiet = board.updates.length;

      // A wallet that has synced before keeps its figure while it syncs
      // again: nothing the widgets say moves.
      final gate = Completer<void>();
      bridge.syncGate = gate;
      final again = container.read(syncProvider.notifier).syncWallet('b');
      await pumpEventQueue();
      expect(board.updates.length, quiet);

      // A first sync that starts trades a zero for a dash.
      final first = container.read(syncProvider.notifier).syncWallet('a');
      await pumpEventQueue();
      expect(board.updates.length, greaterThan(quiet));

      gate.complete();
      await again;
      await first;
      await pumpEventQueue();
    });

    test(
      'a widget nobody placed gets nothing, and its keys are cleared',
      () async {
        final board = FakeWidgetBoard(installed: {HomeWidgets.price});
        board.data[WidgetKeys.balanceTotal] = 'stale';
        final bridge = _bridge();
        await _running(bridge, board);

        expect(board.data.containsKey(WidgetKeys.balanceTotal), isFalse);
        expect(board.data.containsKey(WidgetKeys.networkHeight), isFalse);
        expect(board.updates, everyElement(HomeWidgets.price));
      },
    );

    test(
      'a quote that could not be fetched leaves the last one standing',
      () async {
        final bridge = _bridge();
        final board = FakeWidgetBoard(installed: {HomeWidgets.price});
        final (:container, :feed) = await _running(bridge, board);
        final before = board.data[WidgetKeys.priceFigure];
        expect(before, isNotNull);

        bridge.onFetchPrice = (_, _) =>
            throw const BridgeException('sync', 'no answer');
        container.invalidate(widgetPriceProvider);
        await expectLater(
          container.read(widgetPriceProvider.future),
          throwsA(isA<BridgeException>()),
        );
        await feed.publish();
        expect(board.data[WidgetKeys.priceFigure], before);
      },
    );

    test('with no new quote, the line is said again for the day it is '
        'read', () async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.price});
      Future<void> write(PricePayload? price, DateTime now) => WidgetFeed.write(
        board,
        installed: board.installed,
        price: price,
        table: kPriceTable,
        balance: _noBalance,
        network: _noNetwork,
        now: now,
      );

      final evening = DateTime(2026, 10, 3, 23, 55);
      final quote = PriceQuote(
        rate: 50000,
        currency: FiatCurrency('eur'),
        source: PriceSource.coingecko,
        at: _secs(DateTime(2026, 10, 3, 23, 50)),
      );
      await write(PricePayload.of(quote, kPriceTable, now: evening), evening);
      final figure = board.data[WidgetKeys.priceFigure];
      expect(board.data[WidgetKeys.priceAsOf], 'as of 23:50');
      expect(board.data.containsKey(WidgetKeys.priceAsOfNarrow), isFalse);

      // Past midnight, and nothing new came: the same quote, dated, and
      // credited as its source asks.
      board.updates.clear();
      board.data.remove(WidgetKeys.priceCredit);
      await write(null, DateTime(2026, 10, 4, 0, 10));
      expect(board.data[WidgetKeys.priceFigure], figure);
      expect(board.data[WidgetKeys.priceAsOf], 'as of Oct 03, 23:50');
      expect(board.data[WidgetKeys.priceAsOfNarrow], 'as of Oct 03');
      expect(board.data[WidgetKeys.priceCredit], 'Powered by CoinGecko');
      expect(board.updates, [HomeWidgets.price]);

      // Taken off the home screen, the time goes with the rest.
      board.installed.clear();
      await write(null, DateTime(2026, 10, 4, 0, 25));
      for (final key in PricePayload.keys) {
        expect(board.data.containsKey(key), isFalse, reason: key);
      }
    });

    test('a price from a build that kept no source goes, rather than stand '
        'without its credit', () async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.price});
      // What an earlier build left: a figure and its time, no source.
      board.data
        ..[WidgetKeys.priceFigure] = '€72 537'
        ..[WidgetKeys.priceAt] = '$_syncedAt'
        ..[WidgetKeys.priceAsOf] = 'as of 09:41';
      await WidgetFeed.write(
        board,
        installed: board.installed,
        table: kPriceTable,
        balance: _noBalance,
        network: _noNetwork,
      );
      for (final key in PricePayload.keys) {
        expect(board.data.containsKey(key), isFalse, reason: key);
      }
      expect(board.updates, contains(HomeWidgets.price));
    });

    test('a return to the foreground reads the placed widgets again', () async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.price});
      final (:container, :feed) = await _running(_bridge(), board);
      expect(board.data.containsKey(WidgetKeys.networkHeight), isFalse);

      board.installed.add(HomeWidgets.network);
      feed.resume();
      await container.read(installedWidgetsProvider.future);
      await feed.publish();
      expect(board.installedAsks, 2);
      expect(board.data[WidgetKeys.networkHeight], groupThousands('912345'));
      expect(board.updates, contains(HomeWidgets.network));
    });

    testWidgets('the open app reads the placed widgets again on its own '
        'when it comes back', (tester) async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.price});
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [
            bridgeProvider.overrideWithValue(_bridge()),
            widgetBoardProvider.overrideWithValue(board),
            widgetSchedulerProvider.overrideWithValue((wanted) async {}),
            disguiseServiceProvider.overrideWithValue(
              FakeDisguise(disguised: false),
            ),
            biometricGateProvider.overrideWithValue(
              FakeBiometrics(available: false),
            ),
            windowGuardProvider.overrideWithValue(FakeWindowGuard()),
          ],
          child: const GerfautApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(board.installedAsks, 1);
      expect(board.data.containsKey(WidgetKeys.networkHeight), isFalse);

      // A widget placed while the launcher had the screen.
      board.installed.add(HomeWidgets.network);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(board.installedAsks, 2);
      expect(board.data[WidgetKeys.networkHeight], isNotNull);
    });

    test('the background refresh is scheduled only while a widget is '
        'placed', () async {
      final scheduled = <bool>[];
      final board = FakeWidgetBoard();
      final (:container, :feed) = await _running(
        _bridge(),
        board,
        scheduled: scheduled,
      );
      expect(scheduled, [false]);

      board.installed.add(HomeWidgets.price);
      feed.resume();
      await container.read(installedWidgetsProvider.future);
      await feed.publish();
      expect(scheduled, [false, true]);

      board.installed.clear();
      feed.resume();
      await container.read(installedWidgetsProvider.future);
      await feed.publish();
      expect(scheduled, [false, true, false]);
    });

    test('a network that is not the chain is named under its height', () async {
      final bridge = FakeBridge(
        wallets: [
          makeMeta(
            id: 'r',
            name: 'Local',
            network: Network.regtest,
            lastSync: _stamp(_syncedAt, tipHeight: 120),
          ),
        ],
        settings: const Settings(
          preferences: kPreferences,
          activeNetwork: Network.regtest,
          backends: {},
          appPrefs: {},
        ),
      );
      final board = FakeWidgetBoard(installed: {HomeWidgets.network});
      await _running(bridge, board);

      expect(board.data[WidgetKeys.networkHeight], '120');
      expect(board.data[WidgetKeys.networkFooter], startsWith('Regtest · '));
    });
  });

  group('the background refresh', () {
    /// Preferences as the vault would hand them to the isolate.
    FakeBridge prefBridge(
      Map<String, String> prefs, [
      Preferences preferences = kPreferences,
    ]) {
      final bridge = _bridge();
      bridge.settings = Settings(
        preferences: preferences,
        activeNetwork: Network.mainnet,
        backends: const {},
        appPrefs: prefs,
      );
      return bridge;
    }

    test('publishes the placed widgets from the vault, without ever '
        'syncing', () async {
      final bridge = prefBridge(const {
        'widgets.balances': '1',
      }, kPreferences.copyWith(unit: AmountUnit.sats));
      final board = FakeWidgetBoard(
        installed: {
          HomeWidgets.price,
          HomeWidgets.balance,
          HomeWidgets.network,
        },
      );
      var booted = 0;
      final ok = await refreshWidgets(
        bridge: bridge,
        board: board,
        bootstrap: () async => booted++,
        now: _now,
      );

      expect(ok, isTrue);
      expect(booted, 1);
      // The balances are as of the last sync: nothing was synced here.
      expect(bridge.syncAllCalls, 0);
      expect(bridge.syncWalletCalls, 0);
      // Fiat display is off in the app; the quote comes anyway, in the
      // preferred currency, because the placed widget is the opt-in.
      expect(board.data[WidgetKeys.priceFigure], '€50 000');
      expect(board.data[WidgetKeys.balanceTotal], formatSats(100050000));
      expect(board.data[WidgetKeys.balanceSynced], 'Synced 2 h ago');
      expect(board.data[WidgetKeys.networkHeight], groupThousands('912345'));
      expect(board.updates.toSet(), {
        HomeWidgets.price,
        HomeWidgets.balance,
        HomeWidgets.network,
      });
    });

    test('does not even open the vault while nothing is placed', () async {
      final board = FakeWidgetBoard();
      var booted = 0;
      final ok = await refreshWidgets(
        bridge: _bridge(),
        board: board,
        bootstrap: () async => booted++,
      );
      expect(ok, isTrue);
      expect(booted, 0);
      expect(board.data, isEmpty);
      expect(board.updates, isEmpty);
    });

    test('masks the balances until the preference allows them', () async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      await refreshWidgets(
        bridge: prefBridge(const {}),
        board: board,
        bootstrap: () async {},
        now: _now,
      );
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
      expect(board.data[WidgetKeys.balanceRowName(1)], 'Cold storage');
      expect(board.data[WidgetKeys.balanceRowFigure(1)], maskedValue);
    });

    test('the app-wide mask covers the widgets too', () async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      await refreshWidgets(
        bridge: prefBridge(const {
          'widgets.balances': '1',
        }, kPreferences.copyWith(masked: true)),
        board: board,
        bootstrap: () async {},
        now: _now,
      );
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
    });

    test('under an app lock, no name and no figure, whatever the '
        'notifications show', () async {
      final bridge = prefBridge(
        const {'widgets.balances': '1', 'notify.details': '1'},
        kPreferences.copyWith(notifyNewTx: true),
      )..lock = const AppLock(kind: LockKind.pin, biometric: false);
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      await refreshWidgets(
        bridge: bridge,
        board: board,
        bootstrap: () async {},
        now: _now,
      );
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
      expect(board.data[WidgetKeys.balanceRowName(1)], isNull);
      expect(board.data[WidgetKeys.balanceRowFigure(1)], isNull);
    });

    test('fetches only what the placed widgets need', () async {
      final bridge = _bridge();
      var priceAsks = 0;
      bridge.onFetchPrice = (source, currency) {
        priceAsks++;
        return _quote;
      };
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      await refreshWidgets(
        bridge: bridge,
        board: board,
        bootstrap: () async {},
      );
      expect(priceAsks, 0);
    });

    test('a source that does not answer costs a line, never the run', () async {
      final bridge = _bridge();
      bridge.onFetchPrice = (_, _) =>
          throw const BridgeException('sync', 'no answer');
      final board = FakeWidgetBoard(
        installed: {
          HomeWidgets.price,
          HomeWidgets.balance,
          HomeWidgets.network,
        },
      );
      // What an earlier run had put up stays: the quote carries its time.
      board.data[WidgetKeys.priceFigure] = 'kept';
      final ok = await refreshWidgets(
        bridge: bridge,
        board: board,
        bootstrap: () async {},
        now: _now,
      );
      expect(ok, isTrue);
      expect(board.data[WidgetKeys.priceFigure], 'kept');
      expect(board.data[WidgetKeys.balanceSynced], 'Synced 2 h ago');
    });

    test('the run shows the quote the core keeps, and with none kept '
        'leaves the last one up', () async {
      const lasting = PriceTrouble(
        kind: TroubleKind.unreachable,
        since: _syncedAt,
        nextTry: _syncedAt,
        lasting: true,
      );
      Future<String?> run(PriceReading reading) async {
        final bridge = _bridge()..onReadPrice = (_, _) => reading;
        final board = FakeWidgetBoard(installed: {HomeWidgets.price});
        board.data[WidgetKeys.priceFigure] = 'before';
        await refreshWidgets(
          bridge: bridge,
          board: board,
          bootstrap: () async {},
          now: _now,
        );
        return board.data[WidgetKeys.priceFigure];
      }

      expect(
        await run(const PriceKept(_quote, lasting)),
        PricePayload.of(
          _quote,
          kPriceTable,
          now: _now,
        ).toData()[WidgetKeys.priceFigure],
      );
      expect(await run(const PriceMissing(lasting)), 'before');
    });

    test('a quote kept from another day is dated, at the time of the '
        'run', () async {
      final bridge = _bridge();
      bridge.onFetchPrice = (_, _) =>
          throw const BridgeException('sync', 'no answer');
      final board = FakeWidgetBoard(installed: {HomeWidgets.price});
      final at = _secs(DateTime(2026, 10, 3, 9, 41));
      board.data
        ..[WidgetKeys.priceFigure] = 'kept'
        ..[WidgetKeys.priceAsOf] = 'as of 09:41'
        ..[WidgetKeys.priceAt] = '$at'
        ..[WidgetKeys.priceSource] = 'mempool_space';
      await refreshWidgets(
        bridge: bridge,
        board: board,
        bootstrap: () async {},
        now: DateTime(2026, 10, 4, 7, 30),
      );
      expect(board.data[WidgetKeys.priceFigure], 'kept');
      expect(board.data[WidgetKeys.priceAsOf], 'as of Oct 03, 09:41');
      expect(board.data[WidgetKeys.priceAsOfNarrow], 'as of Oct 03');
    });

    test('with a .onion node, the price follows a Tor that already runs '
        'and never has one started for it', () async {
      // Asked from here, the core's route would bring the built-in Tor
      // up every quarter hour for one figure. It follows a Tor already
      // running, or the widget keeps what it had.
      TorStatus tor(TorMode mode, {bool up = false}) => TorStatus(
        mode: mode,
        socksProxy: '127.0.0.1:9050',
        via: up ? TorVia.embedded : null,
        socks: null,
        running: up,
        bootstrapped: up,
        bootstrapPercent: up ? 100 : 0,
        error: null,
        embeddedAvailable: true,
      );
      Future<({int asks, String? figure, String? asOf})> run({
        required bool usesTor,
        required TorStatus status,
      }) async {
        final bridge = _bridge();
        bridge.usesTorValue = usesTor;
        bridge.onTorStatus = (_) => status;
        var asks = 0;
        bridge.onFetchPrice = (source, currency) {
          asks++;
          return _quote;
        };
        final board = FakeWidgetBoard(
          installed: {HomeWidgets.price, HomeWidgets.balance},
        );
        board.data[WidgetKeys.priceFigure] = 'kept';
        board.data[WidgetKeys.priceAsOf] = 'as of 09:41';
        final ok = await refreshWidgets(
          bridge: bridge,
          board: board,
          bootstrap: () async {},
          now: _now,
        );
        expect(ok, isTrue);
        // The rest of the run goes on as ever.
        expect(board.data[WidgetKeys.balanceSynced], 'Synced 2 h ago');
        return (
          asks: asks,
          figure: board.data[WidgetKeys.priceFigure],
          asOf: board.data[WidgetKeys.priceAsOf],
        );
      }

      final fresh = PricePayload.of(_quote, kPriceTable, now: _now);

      // Built-in Tor, not running in this process: nothing is asked,
      // and the last price stays up with its time.
      for (final mode in [TorMode.auto, TorMode.embedded]) {
        final idle = await run(usesTor: true, status: tor(mode));
        expect(idle, (asks: 0, figure: 'kept', asOf: 'as of 09:41'));
      }

      // Already up for a sync or the live watch: the price goes through it.
      final up = await run(usesTor: true, status: tor(TorMode.auto, up: true));
      expect(up, (asks: 1, figure: fresh.figure, asOf: fresh.asOf));

      // A Tor app chosen as System: the core knocks on it and starts
      // nothing, and refuses if nothing answers.
      final system = await run(usesTor: true, status: tor(TorMode.system));
      expect(system, (asks: 1, figure: fresh.figure, asOf: fresh.asOf));

      // No .onion node: the price is asked as before, whatever Tor does.
      final clear = await run(usesTor: false, status: tor(TorMode.auto));
      expect(clear, (asks: 1, figure: fresh.figure, asOf: fresh.asOf));
    });
  });

  group('the widgets settings', () {
    testWidgets('the switch writes the preference and republishes', (
      tester,
    ) async {
      final bridge = _bridge();
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [
            bridgeProvider.overrideWithValue(bridge),
            widgetBoardProvider.overrideWithValue(board),
            widgetSchedulerProvider.overrideWithValue((wanted) async {}),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const Scaffold(body: WidgetsSection()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WidgetsSection)),
      );
      container.read(widgetFeedProvider);
      await tester.pumpAndSettle();
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
      expect(find.text('Show balances on widgets'), findsOneWidget);
      expect(
        find.textContaining('To add one, hold an empty spot'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(bridge.appPrefs['widgets.balances'], '1');
      expect(board.data[WidgetKeys.balanceTotal], '1.00050000 BTC');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(bridge.appPrefs['widgets.balances'], '0');
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
    });

    testWidgets('under an app lock the switch is greyed and says why', (
      tester,
    ) async {
      final bridge = _bridge()
        ..lock = const AppLock(kind: LockKind.pin, biometric: false)
        ..lockSecret = '1234';
      bridge.appPrefs['widgets.balances'] = '1';
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [
            bridgeProvider.overrideWithValue(bridge),
            widgetBoardProvider.overrideWithValue(board),
            widgetSchedulerProvider.overrideWithValue((wanted) async {}),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const Scaffold(body: WidgetsSection()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WidgetsSection)),
      );
      container.read(widgetBalancesProvider.notifier).hydrate('1');
      container.read(widgetFeedProvider);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Off while an app lock is set'),
        findsOneWidget,
      );
      expect(
        tester.widget<SettingSwitch>(find.byType(SettingSwitch)).onChanged,
        isNull,
      );
      // Drawn off, as the line under it says, the choice kept for later.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(container.read(widgetBalancesProvider), isTrue);
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
      expect(board.data[WidgetKeys.balanceRowName(1)], isNull);
    });

    testWidgets('disguised, the card says the widgets are off', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [
            bridgeProvider.overrideWithValue(_bridge()),
            widgetBoardProvider.overrideWithValue(FakeWidgetBoard()),
            widgetSchedulerProvider.overrideWithValue((wanted) async {}),
            disguiseServiceProvider.overrideWithValue(
              FakeDisguise(disguised: true),
            ),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const Scaffold(body: WidgetsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The providers are disabled while the calculator is the launcher
      // entry: there is nothing to add, so the hint does not send anyone
      // looking for it.
      expect(
        find.text('Widgets are off while the app is disguised.'),
        findsOneWidget,
      );
      expect(find.textContaining('To add one'), findsNothing);
    });
  });
}
