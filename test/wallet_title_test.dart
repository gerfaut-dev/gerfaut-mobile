// The title of a wallet's page: the wallet's icon beside its name, each
// its own target. The icon opens the picker the settings open.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/focus_ring.dart';
import 'package:gerfaut/widgets/icon_chip.dart';
import 'package:gerfaut/widgets/wallet_icon.dart';
import 'package:gerfaut/widgets/wallet_title.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

const _change = "Change this wallet's icon";
const _rename = 'Rename this wallet';

FakeBridge _bridge({String name = 'Cold storage'}) {
  final meta = makeMeta(name: name, icon: WalletIcon.shield);
  return FakeBridge(
    wallets: [meta],
    snapshots: {'w1': makeSnapshot(meta: meta)},
  );
}

Widget _page(FakeBridge bridge, {bool dark = false}) => ProviderScope(
  retry: noRetry,
  overrides: [bridgeProvider.overrideWithValue(bridge)],
  child: MaterialApp(
    theme: dark
        ? themeFrom(GerfautTokens.dark, Brightness.dark)
        : themeFrom(GerfautTokens.light, Brightness.light),
    home: const WalletHomeScreen(walletId: 'w1'),
  ),
);

Finder _chip() => find.descendant(
  of: find.byType(WalletTitle),
  matching: find.byType(IconChip),
);

/// The wallet icon the chip of the title wears.
WalletIcon _worn(WidgetTester tester) => tester
    .widget<WalletGlyph>(
      find.descendant(of: _chip(), matching: find.byType(WalletGlyph)),
    )
    .icon;

/// What the rest of the app reads: the home cards and the settings rows
/// are drawn from this list.
Future<WalletMeta> _listed(WidgetTester tester) async {
  final wallets = ProviderScope.containerOf(
    tester.element(find.byType(WalletHomeScreen)),
  ).read(walletsProvider.future);
  await tester.pumpAndSettle();
  return (await wallets).single;
}

/// Lets the toast run out.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  for (final (width, label) in [
    (320.0, 'a narrow phone'),
    (411.0, 'a phone'),
    (1000.0, 'a wide window'),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'on $label, ${dark ? 'dark' : 'light'}, large text: the icon stays '
        'and a long name ends on its ellipsis',
        (tester) async {
          // Tall enough for the page under the bar to lay out whole at
          // twice the text size: only the bar is looked at here.
          tester.view.physicalSize = Size(width, 2400);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          const long =
              'Savings for the house, the car and a long trip around the world';
          await tester.pumpWidget(_page(_bridge(name: long), dark: dark));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final tokens = dark ? GerfautTokens.dark : GerfautTokens.light;
          // The chip of the home card, glyph and tones alike.
          expect(_worn(tester), WalletIcon.shield);
          final chip = tester.widget<IconChip>(_chip());
          expect(chip.fill, tokens.surfaceSunken);
          expect(chip.ink, tokens.textMuted);
          final chipRect = tester.getRect(_chip());
          expect(chipRect.width, IconChip.side);
          expect(chipRect.left, greaterThanOrEqualTo(0));

          final icon = tester.getRect(find.byTooltip(_change));
          final name = tester.getRect(find.byTooltip(_rename));
          final sync = tester.getRect(find.byTooltip('Sync'));
          // Two targets a finger can land on, side by side, apart.
          expect(icon.width, greaterThanOrEqualTo(GerfautTouch.target));
          expect(icon.height, greaterThanOrEqualTo(GerfautTouch.target));
          expect(name.height, greaterThanOrEqualTo(GerfautTouch.target));
          expect(icon.overlaps(name), isFalse);
          expect(icon.right, lessThanOrEqualTo(name.left));
          // The name gives way before the bar's actions do.
          expect(name.right, lessThanOrEqualTo(sync.left));
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(long))
                .didExceedMaxLines,
            isTrue,
          );
        },
      );
    }
  }

  testWidgets('no icon until the wallet has loaded', (tester) async {
    final bridge = _bridge();
    final gate = Completer<void>();
    bridge.snapshotGate = gate;
    await tester.pumpWidget(_page(bridge));
    await tester.pump();

    expect(find.byTooltip(_change), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip(_change), findsOneWidget);
  });

  testWidgets('tapping the icon picks a new one, saved everywhere', (
    tester,
  ) async {
    final bridge = _bridge();
    await tester.pumpWidget(_page(bridge));
    await tester.pumpAndSettle();

    // Said as the glyph worn, then what a tap does.
    final node = tester.getSemantics(find.byTooltip(_change));
    expect(node.label, contains(WalletIcon.shield.label));
    expect(node.tooltip, _change);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.byTooltip(_change));
    await tester.pumpAndSettle();

    // The sheet of the settings, the current icon marked.
    expect(find.byType(WalletIconPicker), findsOneWidget);
    expect(find.text('Rename wallet'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(WalletIcon.shield.label).last)
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    await tester.tap(find.bySemanticsLabel('Snowflake'));
    await tester.pumpAndSettle();

    expect(bridge.iconCalls, [(id: 'w1', icon: WalletIcon.snowflake)]);
    expect(find.byType(WalletIconPicker), findsNothing);
    expect(find.text('Setting saved'), findsOneWidget);
    // The page wears it at once, and so does the list the home screen
    // and the settings read.
    expect(_worn(tester), WalletIcon.snowflake);
    expect((await _listed(tester)).icon, WalletIcon.snowflake);
    await _flush(tester);
  });

  testWidgets('dismissing the picker or keeping the icon writes nothing', (
    tester,
  ) async {
    final bridge = _bridge();
    await tester.pumpWidget(_page(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_change));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(WalletIconPicker), findsNothing);

    await tester.tap(find.byTooltip(_change));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(WalletIconPicker),
        matching: find.byIcon(LucideIcons.shield),
      ),
    );
    await tester.pumpAndSettle();

    expect(bridge.iconCalls, isEmpty);
    expect(find.text('Setting saved'), findsNothing);
  });

  testWidgets('the name is the heading that names the page', (tester) async {
    await tester.pumpWidget(_page(_bridge()));
    await tester.pumpAndSettle();

    final name = tester.getSemantics(find.byTooltip(_rename));
    expect(name.label, 'Cold storage');
    expect(name.flagsCollection.isHeader, isTrue);
    expect(name.flagsCollection.namesRoute, isTrue);
    expect(name.flagsCollection.isButton, isTrue);
    // One heading in the bar, and it is the name: the icon is not one.
    final icon = tester.getSemantics(find.byTooltip(_change));
    expect(icon.flagsCollection.isHeader, isFalse);
    expect(icon.flagsCollection.namesRoute, isFalse);
  });

  testWidgets('tapping the name still renames, never the icon', (tester) async {
    await tester.pumpWidget(_page(_bridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Rename wallet'), findsOneWidget);
    expect(find.byType(WalletIconPicker), findsNothing);
  });

  testWidgets('a refused icon is said, and stays said', (tester) async {
    final bridge = _RefusingIcon(
      wallets: [makeMeta(icon: WalletIcon.shield)],
      snapshots: {'w1': makeSnapshot(meta: makeMeta(icon: WalletIcon.shield))},
    );
    await tester.pumpWidget(_page(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_change));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Snowflake'));
    await tester.pumpAndSettle();

    // Not a toast: it waits to be read.
    expect(find.text('Icon not saved'), findsOneWidget);
    expect(find.text('the vault could not be written'), findsOneWidget);
    expect(find.text('Setting saved'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Icon not saved'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Icon not saved'), findsNothing);
    expect(_worn(tester), WalletIcon.shield);
  });

  testWidgets('the icon answers during a sync, as the name does', (
    tester,
  ) async {
    final bridge = _bridge();
    final gate = Completer<void>();
    bridge.syncGate = gate;
    await tester.pumpWidget(_page(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sync'));
    // Not settled: the sync button turns for as long as the sync runs.
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester
          .getSemantics(find.byTooltip(_change))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.byTooltip(_change));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WalletIconPicker), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Snowflake'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(bridge.iconCalls, [(id: 'w1', icon: WalletIcon.snowflake)]);

    // The sync ends after the change and keeps it.
    gate.complete();
    await tester.pumpAndSettle();
    expect(_worn(tester), WalletIcon.snowflake);
    await _flush(tester);
  });

  testWidgets('a keyboard reaches the icon and rings it', (tester) async {
    await tester.pumpWidget(_page(_bridge()));
    await tester.pumpAndSettle();

    final ring = find.descendant(
      of: find.byType(WalletTitle),
      matching: find.byType(FocusRing),
    );
    bool ringed() => tester
        .widgetList<CustomPaint>(
          find.descendant(of: ring, matching: find.byType(CustomPaint)),
        )
        .any((paint) => paint.foregroundPainter is FocusRingPainter);

    expect(ringed(), isFalse);
    for (var i = 0; i < 6 && !ringed(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(ringed(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(WalletIconPicker), findsOneWidget);
  });
}

class _RefusingIcon extends FakeBridge {
  _RefusingIcon({required super.wallets, required super.snapshots});

  @override
  Future<void> setWalletIcon(String id, WalletIcon icon) async {
    throw const BridgeException('storage', 'the vault could not be written');
  }
}
