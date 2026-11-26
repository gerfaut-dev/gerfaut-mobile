import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/receive.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/address_chip.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fakes.dart';

Widget receiveApp(
  FakeBridge bridge, {
  GerfautTokens? tokens,
  Brightness brightness = Brightness.light,
  String walletId = 'w1',
}) {
  return ProviderScope(
    retry: noRetry,
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: creditedApp(
      theme: themeFrom(tokens ?? GerfautTokens.light, brightness),
      home: ReceiveScreen(walletId: walletId),
    ),
  );
}

/// A surface tall enough to build the whole page at once.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A bridge with one wallet and the given audit list.
FakeBridge bridgeWith(AddressList list, {WalletMeta? meta}) {
  final wallet = meta ?? makeMeta();
  return FakeBridge(
    wallets: [wallet],
    snapshots: {'w1': makeSnapshot(meta: wallet)},
    addressLists: {'w1': list},
  );
}

AddressRow row(int index, {bool used = false, int balance = 0}) => AddressRow(
  index: index,
  address: 'bc1qaddress$index',
  used: used,
  balanceSats: balance,
);

void main() {
  group('the address on offer', () {
    testWidgets('skipping peeks the next index and returns to the first', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(index: 4, address: 'tb1qfirst', used: false),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
      expect(find.text('tb1qfirst'), findsOneWidget);
      expect(find.text('First unused'), findsNothing);

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();

      // One step further down the derivation path, nothing retired.
      expect(find.text('UNUSED ADDRESS · INDEX 5'), findsOneWidget);
      expect(find.text('tb1qfirst1'), findsOneWidget);
      // One past the address on display, to know whether there is a next.
      expect(bridge.receiveLookaheads.last, 2);

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 6'), findsOneWidget);

      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
      expect(find.text('tb1qfirst'), findsOneWidget);
      expect(find.text('First unused'), findsNothing);
    });

    testWidgets('an address paid while on screen gives way to the next', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(index: 4, address: 'tb1qfirst', used: false),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);

      // The payer pays index 4, and a sync started elsewhere, Live's,
      // sees it: the screen moves on without being left.
      bridge.addresses['w1'] = const [
        AddressEntry(index: 5, address: 'tb1qsecond', used: false),
      ];
      ProviderScope.containerOf(tester.element(find.byType(ReceiveScreen)))
          .read(syncProvider.notifier)
          .refreshed('w1');
      await tester.pumpAndSettle();

      expect(find.text('NEXT UNUSED ADDRESS · INDEX 5'), findsOneWidget);
      expect(find.text('tb1qsecond'), findsOneWidget);
      expect(find.text('tb1qfirst'), findsNothing);
    });

    testWidgets('reopening Receive after a payment asks the core again', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(index: 4, address: 'tb1qfirst', used: false),
          ],
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [bridgeProvider.overrideWithValue(bridge)],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReceiveScreen(walletId: 'w1'),
                    ),
                  ),
                  child: const Text('Open receive'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open receive'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Paid while nobody looked, and no sync of this app saw it.
      bridge.addresses['w1'] = const [
        AddressEntry(index: 5, address: 'tb1qsecond', used: false),
      ];
      await tester.tap(find.text('Open receive'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 5'), findsOneWidget);
    });

    testWidgets('a single-address wallet shows its one address, no skip', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(
        name: 'Donation address',
        kind: const SingleAddressKind(address: 'bc1qwatched'),
      );
      final bridge = bridgeWith(
        const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qwatched',
              used: true,
              balanceSats: 5000,
            ),
          ],
          internal: [],
        ),
        meta: meta,
      );
      bridge.addresses['w1'] = const [
        AddressEntry(index: 0, address: 'bc1qwatched', used: true),
      ];
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      // The label above the address and the card title share the words.
      expect(find.text('WATCHED ADDRESS'), findsNWidgets(2));
      // Once in full above, once as the card's chip.
      expect(find.text('bc1qwatched'), findsNWidgets(2));
      expect(find.text('Copy address'), findsOneWidget);
      expect(find.text('Next address'), findsNothing);
      expect(find.text('First unused'), findsNothing);
      expect(find.byIcon(LucideIcons.skipForward), findsNothing);
      // A single watched address has no derivation path to show.
      expect(find.text('DERIVATION PATH'), findsNothing);
      // One card, no keychain vocabulary.
      expect(find.text('EXTERNAL'), findsNothing);
      expect(find.text('CHANGE'), findsNothing);
      expect(find.text('No change addresses revealed yet.'), findsNothing);
    });

    testWidgets('the derivation path shows when the core provides one', (
      tester,
    ) async {
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(
              index: 0,
              address: 'tb1qfirst',
              used: false,
              derivation: "m/84'/1'/0'/0/0",
            ),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('DERIVATION PATH'), findsOneWidget);
      expect(find.text("m/84'/1'/0'/0/0"), findsOneWidget);
    });

    testWidgets('no derivation line when the core sends none', (tester) async {
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(index: 0, address: 'tb1qfirst', used: false),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('DERIVATION PATH'), findsNothing);
    });

    testWidgets('peeking past the gap limit raises the warning', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 2);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.textContaining('beyond the gap limit'), findsNothing);

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '2 unused addresses in a row come before this one, beyond the gap '
          'limit of 2: other wallet software may not detect funds received '
          'here.',
        ),
        findsOneWidget,
      );
      // Two panels, two tones, and the glyph says which is which: the
      // triangle is the verify warning, which is about funds; the gap
      // note only states a convention, so it carries the info glyph.
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.byIcon(LucideIcons.info), findsOneWidget);
      expect(
        find.text(
          'Verify this address on your signing device before sharing it.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(find.textContaining('beyond the gap limit'), findsNothing);
    });

    testWidgets('an address a payment reached is skipped, and ends the run', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 3);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      )..paidAhead['w1'] = {1, 2};
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      // Indexes 1 and 2 were paid: the next on offer is 3. Software that
      // scans finds those two, so only index 0 is unused before it, and
      // the gap limit of 3 is nowhere near.
      expect(find.text('UNUSED ADDRESS · INDEX 3'), findsOneWidget);
      expect(find.textContaining('beyond the gap limit'), findsNothing);
    });

    testWidgets('the longest unused run counts, wherever it lies', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 3);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      )..paidAhead['w1'] = {4};
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next address'));
        await tester.pumpAndSettle();
      }
      // 0 to 3 unused, 4 paid, then 5: the run of four before the paid
      // one is where a scan with a gap limit of 3 stops.
      expect(find.text('UNUSED ADDRESS · INDEX 5'), findsOneWidget);
      expect(
        find.textContaining('4 unused addresses in a row come before this'),
        findsOneWidget,
      );
    });

    testWidgets('skipping stops at the most the core offers', (tester) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 500);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      for (var i = 0; i < maxReceivePeek; i++) {
        await tester.tap(find.text('Next address'));
        await tester.pumpAndSettle();
      }
      expect(find.text('UNUSED ADDRESS · INDEX 200'), findsOneWidget);
      expect(bridge.receiveLookaheads.every((n) => n <= 200), isTrue);
      final next = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, 'Next address'),
      );
      expect(next.onPressed, isNull);
      expect(
        find.text(
          'Gerfaut offers at most 200 addresses past the next unused one.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 0'), findsOneWidget);
    });

    testWidgets('a descriptor without a wildcard offers no next address', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      )..withoutWildcard.add('w1');
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('NEXT UNUSED ADDRESS · INDEX 0'), findsOneWidget);
      expect(find.text('Next address'), findsNothing);
    });

    testWidgets('the address wraps into lines of the same length', (
      tester,
    ) async {
      const address = 'tb1qa3658sv7ndr9mkcwqy52g39snc70j5xdleavm0';
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [AddressEntry(index: 0, address: address, used: false)],
        },
      );

      /// The length of each line the address is drawn on, in characters.
      List<int> lines() {
        final editable = tester
            .state<EditableTextState>(
              find.descendant(
                of: find.byType(SelectableText),
                matching: find.byType(EditableText),
              ),
            )
            .renderEditable;
        final glyph = editable
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 1),
            )
            .single
            .toRect()
            .width;
        return [
          for (final box in editable.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: address.length),
          ))
            (box.toRect().width / glyph).round(),
        ];
      }

      tester.view.physicalSize = const Size(480, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      // Two halves, not a full line and a stray tail.
      expect(lines(), [21, 21]);
      // The text itself is the whole address, for selection and speech.
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        address,
      );

      // At twice the text size, more lines, still level.
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final scaled = lines();
      expect(scaled.length, greaterThan(2));
      expect(scaled.reduce(min), greaterThanOrEqualTo(scaled.reduce(max) - 2));
    });

    testWidgets('the copy toast stays dark in the dark theme', (tester) async {
      useTallSurface(tester);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(
        receiveApp(
          bridge,
          tokens: GerfautTokens.dark,
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy address'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // As on the desktop app: night ground and foam text in either
      // theme, never the light block the dark theme's text colour made.
      final toast = find.byType(SnackBar);
      expect(toast, findsOneWidget);
      final ground = tester.widget<Material>(
        find.descendant(of: toast, matching: find.byType(Material)).first,
      );
      expect(ground.color, GerfautTokens.dark.background);
      final shape = ground.shape! as RoundedRectangleBorder;
      expect(shape.side.color, GerfautTokens.dark.border);
      expect(shape.side.style, BorderStyle.solid);
      final words = tester.widget<DefaultTextStyle>(
        find
            .ancestor(
              of: find.descendant(of: toast, matching: find.text('Copied')),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
      expect(words.style.color, GerfautTokens.dark.text);
      // Past the button's check and the toast's three seconds.
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    test('the toast has an edge only where the page shares its ground', () {
      // Dark ground on a light page: it stands out by itself.
      final light = themeFrom(GerfautTokens.light, Brightness.light);
      final lightShape = light.snackBarTheme.shape! as RoundedRectangleBorder;
      expect(
        light.snackBarTheme.backgroundColor,
        GerfautTokens.dark.background,
      );
      expect(lightShape.side, BorderSide.none);
      // Dark ground on a dark page of the same colour: the hairline.
      final dark = themeFrom(GerfautTokens.dark, Brightness.dark);
      final darkShape = dark.snackBarTheme.shape! as RoundedRectangleBorder;
      expect(dark.snackBarTheme.backgroundColor, GerfautTokens.dark.background);
      expect(darkShape.side.color, GerfautTokens.dark.border);
    });

    testWidgets('the small QR code opens large and closes on a tap', (
      tester,
    ) async {
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      // One code on the page, at its compact size.
      expect(find.byType(QrImageView), findsOneWidget);
      final small = tester.getSize(find.byType(QrImageView));
      expect(small.width, lessThanOrEqualTo(140));

      await tester.tap(find.byType(QrImageView));
      await tester.pumpAndSettle();

      // The dialog draws a second, larger one on a white card.
      expect(find.byType(QrImageView), findsNWidgets(2));
      expect(find.text('Tap anywhere to close'), findsOneWidget);
      final large = tester.getSize(find.byType(QrImageView).last);
      expect(large.width, greaterThan(300));
      final card = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(QrImageView).last,
              matching: find.byType(Container),
            )
            .first,
      );
      expect((card.decoration! as BoxDecoration).color, GerfautQr.background);
      // Under it, the address in full, in mono: both ends to compare.
      final under = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (text) =>
                text.style?.fontFamily == GerfautFonts.data &&
                text.style?.color == GerfautTokens.dark.text,
          )
          .toList();
      expect(under, hasLength(1));
      expect(under.single.data, 'tb1qexample');

      await tester.tap(find.text('Tap anywhere to close'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);

      // Escape closes it as well.
      await tester.tap(find.byType(QrImageView));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
    });
  });

  group('the revealed addresses', () {
    testWidgets('a test coin on an address is worth zero in the currency', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        AddressList(
          external: [row(0, used: true, balance: 150000)],
          internal: const [],
        ),
        meta: makeMeta(network: Network.signet),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveScreen)),
        listen: false,
      );
      container.read(fiatEnabledProvider.notifier).set(true);
      await tester.pumpAndSettle();

      // 150 000 sats at 50 000 a coin would be €75.00 on mainnet.
      expect(find.textContaining('0.00150000'), findsOneWidget);
      expect(find.text('€0.00'), findsOneWidget);
      expect(find.text('€75.00'), findsNothing);
    });

    testWidgets('an index of three digits stays on one line at twice the '
        'text size', (tester) async {
      tester.view.physicalSize = const Size(411, 3600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final bridge = bridgeWith(
        AddressList(external: [row(7), row(123)], internal: const []),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      final index = tester.renderObject<RenderParagraph>(find.text('123'));
      expect(
        index.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(index.size.width),
      );
      // Both rows keep one column for their addresses.
      expect(
        tester.getRect(find.byType(AddressChip).at(0)).left,
        tester.getRect(find.byType(AddressChip).at(1)).left,
      );
    });

    testWidgets('external and change keychains sit in their own cards', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: true,
              balanceSats: 150000,
            ),
            AddressRow(
              index: 1,
              address: 'bc1qsecond',
              used: false,
              balanceSats: 0,
            ),
          ],
          internal: [
            AddressRow(
              index: 0,
              address: 'bc1qchange',
              used: true,
              balanceSats: 0,
            ),
          ],
        ),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('EXTERNAL'), findsOneWidget);
      expect(find.text('CHANGE'), findsOneWidget);
      expect(
        find.text('Receive addresses, in derivation order.'),
        findsOneWidget,
      );
      expect(
        find.text('Internal addresses used by outgoing transactions.'),
        findsOneWidget,
      );

      // Usage: a pill each, same shape, never a bare word.
      expect(find.text('Used'), findsNWidgets(2));
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.byType(AddressStatePill), findsNWidgets(3));

      // Balances: an amount when coins sit there, a dash otherwise.
      expect(find.textContaining('0.00150000'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));

      // Short keychains have nothing to unfold; nothing was truncated.
      expect(find.textContaining('Show all'), findsNothing);
      expect(find.textContaining('Long keychains are capped'), findsNothing);
    });

    // A balance folded away is no figure on screen: CoinGecko's credit
    // comes with the row that shows one, and goes with it.
    testWidgets('a folded balance is not credited, an unfolded one is', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        AddressList(
          external: [
            for (var i = 0; i < 6; i++) row(i, used: true),
            row(6, used: true, balance: 150000),
          ],
          internal: const [],
        ),
        meta: makeMeta(network: Network.mainnet),
      );
      bridge.preferences = bridge.preferences.copyWith(
        fiat: true,
        priceSource: PriceSource.coingecko,
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveScreen)),
        listen: false,
      );
      container.read(preferencesProvider.notifier).hydrate(bridge.preferences);
      await tester.pumpAndSettle();
      expect(find.text('€75.00'), findsNothing);
      expect(find.text('Powered by CoinGecko'), findsNothing);

      await tester.tap(find.text('Show all 7'));
      await tester.pumpAndSettle();
      expect(find.text('€75.00'), findsOneWidget);
      expect(find.text('Powered by CoinGecko'), findsOneWidget);

      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('Powered by CoinGecko'), findsNothing);
    });

    testWidgets('a long keychain shows five rows, then all of them', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        AddressList(
          external: [for (var i = 0; i < 12; i++) row(i, used: i < 8)],
          internal: [for (var i = 0; i < 7; i++) row(i, used: true)],
        ),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      // Five per card, the counts in the headers.
      expect(find.byType(AddressStatePill), findsNWidgets(10));
      expect(find.text('12'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Show all 12'), findsOneWidget);
      expect(find.text('Show all 7'), findsOneWidget);

      // Unfolding one card leaves the other folded.
      await tester.tap(find.text('Show all 12'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressStatePill), findsNWidgets(17));
      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Show all 7'), findsOneWidget);
      expect(find.text('Fresh'), findsNWidgets(4));

      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressStatePill), findsNWidgets(10));
      expect(find.text('Show all 12'), findsOneWidget);
    });

    testWidgets('an empty change keychain says so', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: false,
              balanceSats: 0,
            ),
          ],
          internal: [],
        ),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('No change addresses revealed yet.'), findsOneWidget);
    });

    testWidgets('a truncated keychain states the cap', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: true,
              balanceSats: 0,
            ),
          ],
          internal: [],
          truncated: true,
        ),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Long keychains are capped: only the first 200 addresses of each '
          'are listed.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('masking hides the balances on the cards', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: true,
              balanceSats: 150000,
            ),
          ],
          internal: [],
        ),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveScreen)),
        listen: false,
      );
      container.read(maskedProvider.notifier).toggle();
      await tester.pumpAndSettle();

      expect(find.textContaining('0.00150000'), findsNothing);
      expect(find.text('•••••'), findsOneWidget);
    });
  });

  group('address state pills', () {
    /// Decoration of the pill carrying [label].
    BoxDecoration pill(WidgetTester tester, String label) {
      return tester
              .widget<Container>(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;
    }

    TextStyle pillText(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!;

    FakeBridge bridgeWithBothStates() {
      return bridgeWith(
        const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qused',
              used: true,
              balanceSats: 0,
            ),
            AddressRow(
              index: 1,
              address: 'bc1qfresh',
              used: false,
              balanceSats: 0,
            ),
          ],
          internal: [],
        ),
      );
    }

    testWidgets('both states are pills of the same shape', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(receiveApp(bridgeWithBothStates()));
      await tester.pumpAndSettle();

      for (final label in ['Used', 'Fresh']) {
        final decoration = pill(tester, label);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(GerfautRadius.full),
        );
        expect(decoration.border!.top.width, 1);
        expect(pillText(tester, label).fontSize, 11);
        expect(pillText(tester, label).fontWeight, FontWeight.w500);
      }
    });

    testWidgets('used wears the alert role, fresh the primary one', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(receiveApp(bridgeWithBothStates()));
      await tester.pumpAndSettle();

      final light = GerfautTokens.light;
      expect(pillText(tester, 'Used').color, light.alert);
      expect(pill(tester, 'Used').color, light.alertSurface);
      expect(
        pill(tester, 'Used').border!.top.color,
        light.alert.withValues(alpha: 0.25),
      );

      expect(pillText(tester, 'Fresh').color, light.primary);
      expect(pill(tester, 'Fresh').color, light.primary.withValues(alpha: 0.1));
      expect(
        pill(tester, 'Fresh').border!.top.color,
        light.primary.withValues(alpha: 0.25),
      );
    });

    testWidgets('the dark theme tints used, where the surface would not', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        receiveApp(
          bridgeWithBothStates(),
          tokens: GerfautTokens.dark,
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final dark = GerfautTokens.dark;
      // alertSurface is the card surface in the dark theme: a plain
      // tint would leave the pill invisible.
      expect(dark.alertSurface, dark.surface);
      expect(pillText(tester, 'Used').color, dark.alert);
      expect(pill(tester, 'Used').color, dark.alert.withValues(alpha: 0.1));
      expect(pillText(tester, 'Fresh').color, dark.primary);
      expect(pill(tester, 'Fresh').color, dark.primary.withValues(alpha: 0.1));
    });
  });

  group('New address', () {
    /// A wallet whose next unused address, index 4, and the one after
    /// it were handed out before: the first never shown is index 6.
    FakeBridge revealedBridge() {
      final meta = makeMeta();
      return FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(
              index: 4,
              address: 'tb1qgiven4',
              used: false,
              revealed: true,
            ),
            AddressEntry(
              index: 5,
              address: 'tb1qgiven5',
              used: false,
              revealed: true,
            ),
          ],
        },
        addressLists: {
          'w1': AddressList(external: [row(4), row(5)], internal: []),
        },
      );
    }

    final newAddress = find.widgetWithText(SecondaryButton, 'New address');
    const noneInReach =
        'Every address within 200 of the first unused one was shown '
        'before. Use one of them, or wait for a payment to free the next '
        'ones.';

    testWidgets('keeps every address it shows revealed, once each, Next '
        'address included', (tester) async {
      useTallSurface(tester);
      final gate = Completer<void>();
      final bridge = bridgeWith(const AddressList(external: [], internal: []))
        ..revealGate = gate;
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      expect(bridge.revealCalls, [('w1', 0)]);

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      // Shown again while the core answers: asked once all the same.
      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(bridge.revealCalls, [('w1', 0), ('w1', 1)]);

      gate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(bridge.revealCalls, [('w1', 0), ('w1', 1)]);
    });

    testWidgets('a reveal that failed is asked again the next time the '
        'address shows', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(const AddressList(external: [], internal: []))
        ..revealError = const BridgeException('internal', 'vault busy');
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      expect(bridge.revealCalls, [('w1', 0)]);

      // Index 1 fails too: revealed, it would have kept index 0 with it.
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      bridge.revealError = null;
      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(
        bridge.revealCalls.where((call) => call == ('w1', 0)),
        hasLength(2),
      );
      expect(bridge.revealCalls.last, ('w1', 0));
    });

    testWidgets('shows on an address handed out before, not on a fresh one', (
      tester,
    ) async {
      useTallSurface(tester);
      // The reveal of index 6 never answers: it stays as it was read.
      final bridge = revealedBridge()..revealGate = Completer<void>();
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
      expect(newAddress, findsOneWidget);
      expect(tester.widget<SecondaryButton>(newAddress).icon, LucideIcons.plus);

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 6'), findsOneWidget);
      expect(newAddress, findsNothing);
    });

    testWidgets('hides where the screen can go no further', (tester) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 500);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': [
            for (var i = 0; i <= maxReceivePeek; i++)
              AddressEntry(
                index: i,
                address: 'tb1qgiven$i',
                used: false,
                revealed: true,
              ),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      for (var i = 0; i < maxReceivePeek; i++) {
        await tester.tap(find.text('Next address'));
        await tester.pumpAndSettle();
      }
      expect(find.text('UNUSED ADDRESS · INDEX 200'), findsOneWidget);
      expect(newAddress, findsNothing);
    });

    testWidgets('goes to the first address never shown, a new one each '
        'press', (tester) async {
      useTallSurface(tester);
      final bridge = revealedBridge();
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      // What the audit list reads once the core has revealed index 6.
      bridge.addressLists['w1'] = AddressList(
        external: [row(4), row(5), row(6)],
        internal: [],
      );

      await tester.tap(newAddress);
      await tester.pump();
      expect(tester.widget<SecondaryButton>(newAddress).busy, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 6'), findsOneWidget);
      expect(find.text('tb1qgiven42'), findsOneWidget);
      expect(bridge.revealCalls, [('w1', 6)]);
      expect(find.byType(AddressStatePill), findsNWidgets(3));
      expect(tester.widget<SecondaryButton>(newAddress).busy, isFalse);

      // Index 6 now counts as handed out: the next press goes past it.
      await tester.tap(newAddress);
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 7'), findsOneWidget);

      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
    });

    testWidgets('never offers an address reached with Next address', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = revealedBridge();
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 6'), findsOneWidget);
      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();

      await tester.tap(newAddress);
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 7'), findsOneWidget);
    });

    testWidgets('with none never shown within reach, stays and says so', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 500);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': [
            for (var i = 0; i <= maxReceivePeek; i++)
              AddressEntry(
                index: i,
                address: 'tb1qgiven$i',
                used: false,
                revealed: true,
              ),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(newAddress);
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 0'), findsOneWidget);
      expect(newAddress, findsNothing);
      expect(find.text(noneInReach), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.text(noneInReach))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      handle.dispose();

      // Moving on takes the line away, and New address is back.
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.text(noneInReach), findsNothing);
      expect(newAddress, findsOneWidget);
    });

    testWidgets('never offers an address shown in this visit, even when '
        'keeping it failed', (tester) async {
      useTallSurface(tester);
      final bridge = revealedBridge()
        ..revealError = const BridgeException('internal', 'vault busy');
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 6'), findsOneWidget);
      expect(bridge.revealCalls, contains(('w1', 6)));
      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();

      await tester.tap(newAddress);
      await tester.pumpAndSettle();
      expect(find.text('UNUSED ADDRESS · INDEX 7'), findsOneWidget);
    });

    testWidgets('a sync brings New address back after none was found', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 500);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': [
            for (var i = 0; i <= maxReceivePeek; i++)
              AddressEntry(
                index: i,
                address: 'tb1qgiven$i',
                used: false,
                revealed: true,
              ),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();
      await tester.tap(newAddress);
      await tester.pumpAndSettle();
      expect(find.text(noneInReach), findsOneWidget);

      // What a finished sync does: the wallet is read again.
      ProviderScope.containerOf(tester.element(find.byType(ReceiveScreen)))
          .invalidate(snapshotProvider('w1'));
      await tester.pumpAndSettle();
      expect(find.text(noneInReach), findsNothing);
      expect(newAddress, findsOneWidget);
    });

    testWidgets('a press before a wallet switch changes nothing in the '
        'other wallet', (tester) async {
      useTallSurface(tester);
      final bridge = revealedBridge();
      bridge.addresses['w2'] = const [
        AddressEntry(
          index: 10,
          address: 'tb1qother10',
          used: false,
          revealed: true,
        ),
        AddressEntry(index: 11, address: 'tb1qother11', used: false),
      ];
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(newAddress);
      await tester.pump();
      await tester.pumpWidget(receiveApp(bridge, walletId: 'w2'));
      await tester.pumpAndSettle();
      // Had the press carried over, the screen would sit on index 11.
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 10'), findsOneWidget);
      expect(tester.widget<SecondaryButton>(newAddress).busy, isFalse);
    });
  });
}
