import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/page_transition.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/app_bar.dart';
import 'package:gerfaut/widgets/choice_group.dart';
import 'package:gerfaut/widgets/dialog.dart';
import 'package:gerfaut/widgets/setting_switch.dart';

import 'contrast.dart';

Widget _app(Widget home, {bool still = false, Brightness? brightness}) {
  final dark = brightness == Brightness.dark;
  return MaterialApp(
    theme: themeFrom(
      dark ? GerfautTokens.dark : GerfautTokens.light,
      dark ? Brightness.dark : Brightness.light,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: still),
      child: child!,
    ),
    home: home,
  );
}

/// How far to the side the page that shows [text] is drawn.
double _left(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

/// The haptic calls the platform receives while [body] runs.
Future<List<String>> _haptics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await body();
  return calls;
}

void main() {
  group('a page', () {
    Widget first() => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Align(child: Text('Second'))),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    testWidgets('arrives from a short way to the side, within the ceiling', (
      tester,
    ) async {
      await tester.pumpWidget(_app(first()));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final start = _left(tester, 'Second');

      await tester.pump(GerfautMotion.slow);
      final rest = _left(tester, 'Second');
      expect(
        start - rest,
        closeTo(GerfautPageTransitionsBuilder.travel, 1),
        reason: 'the page starts its travel to the side of where it rests',
      );

      // Nothing is left to run: the whole transition fits the slowest
      // duration of the design system.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        GerfautMotion.slow,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
    });

    testWidgets('stays put when animations are reduced', (tester) async {
      await tester.pumpWidget(_app(first(), still: true));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final start = _left(tester, 'Second');

      await tester.pumpAndSettle();
      expect(_left(tester, 'Second'), start);
    });
  });

  group('a dialog', () {
    Widget opener(void Function(bool?) answered) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => answered(
              await showGerfautDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sure?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Yes'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Ask'),
          ),
        ),
      ),
    );

    testWidgets('rises as it arrives and hands back its answer', (
      tester,
    ) async {
      final answers = <bool?>[];
      await tester.pumpWidget(_app(opener(answers.add)));
      await tester.tap(find.text('Ask'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final start = tester.getTopLeft(find.text('Sure?')).dy;

      await tester.pumpAndSettle();
      expect(start - tester.getTopLeft(find.text('Sure?')).dy, closeTo(8, 1));

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('closes on a touch outside, with no answer', (tester) async {
      final answers = <bool?>[];
      await tester.pumpWidget(_app(opener(answers.add)));
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Sure?'), findsNothing);
      expect(answers, [null]);
    });

    testWidgets('has started to fade halfway through leaving', (tester) async {
      await tester.pumpWidget(_app(opener((_) {})));
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(GerfautMotion.fast ~/ 2);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Sure?'),
              matching: find.byType(FadeTransition),
            )
            .last,
      );
      // It leaves on the mirror of the curve it came in on: most of the
      // way out by the middle, not still whole.
      expect(fade.opacity.value, lessThan(0.5));
      await tester.pumpAndSettle();
    });
  });

  group('the header', () {
    Color edge(WidgetTester tester) {
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      return (bar.shape! as Border).bottom.color;
    }

    testWidgets('is ruled off once the page has scrolled, and only then', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            appBar: GerfautAppBar.text('Title'),
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 48, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      );
      expect(edge(tester).a, 0);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(edge(tester), GerfautTokens.light.border);

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(edge(tester).a, 0);
    });
  });

  group('a touch', () {
    testWidgets('ticks when a choice changes, not on the current one', (
      tester,
    ) async {
      var value = 'btc';
      final calls = await _haptics(tester, () async {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => ChoiceGroup<String>(
                  label: 'Unit',
                  value: value,
                  options: const [
                    ChoiceOption(value: 'btc', label: 'BTC'),
                    ChoiceOption(value: 'sats', label: 'sats'),
                  ],
                  onChanged: (picked) => setState(() => value = picked),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('BTC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('sats'));
        await tester.pumpAndSettle();
      });
      expect(value, 'sats');
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('ticks when a switch is thrown', (tester) async {
      var on = false;
      final calls = await _haptics(tester, () async {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => GerfautSwitch(
                  value: on,
                  onChanged: (value) => setState(() => on = value),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
      });
      expect(on, isTrue);
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });
  });

  testWidgets('side by side, the options follow the reading direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ChoiceGroup<String>(
              label: 'Unit',
              value: 'btc',
              options: const [
                ChoiceOption(value: 'btc', label: 'BTC'),
                ChoiceOption(value: 'sats', label: 'sats'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getCenter(find.text('BTC')).dx,
      greaterThan(tester.getCenter(find.text('sats')).dx),
    );
    // One line, not two rows.
    expect(
      tester.getCenter(find.text('BTC')).dy,
      tester.getCenter(find.text('sats')).dy,
    );
  });

  test('the received chip has a fill of its own in both themes', () {
    for (final tokens in [GerfautTokens.light, GerfautTokens.dark]) {
      expect(tokens.confirmedChip, isNot(tokens.surface));
    }
    expect(
      GerfautTokens.light.confirmedChip,
      GerfautTokens.light.confirmedSurface,
    );
    expect(GerfautTokens.dark.confirmedChip, GerfautTokens.dark.surfaceSunken);
  });

  test('the square of a data output has a fill of its own in both themes, '
      'and its glyph reads on it', () {
    // As on the desktop: the tinted surface in light, the ink at 10 % in
    // dark, where the tinted surface is the card's own.
    expect(GerfautTokens.light.pendingChip, GerfautTokens.light.pendingSurface);
    expect(
      GerfautTokens.dark.pendingChip,
      GerfautTokens.dark.pending.withValues(alpha: 0.10),
    );
    for (final tokens in [GerfautTokens.light, GerfautTokens.dark]) {
      final square = Color.alphaBlend(tokens.pendingChip, tokens.surface);
      expect(square, isNot(tokens.surface));
      // A glyph is a graphic: 3:1 at least against what it sits on.
      expect(contrastRatio(tokens.pending, square), greaterThanOrEqualTo(3));
    }
  });
}
