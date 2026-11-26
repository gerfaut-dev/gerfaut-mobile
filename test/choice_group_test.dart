import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/choice_group.dart';

/// One group of three, the middle one out of reach, in a column [width]
/// wide: wide enough for the three side by side unless told otherwise.
Widget _app({
  required String value,
  required ValueChanged<String> onChanged,
  bool middleEnabled = false,
  double width = 480,
  double textScale = 1,
  bool still = false,
}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: still,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: ChoiceGroup<String>(
                label: 'Theme',
                value: value,
                options: [
                  const ChoiceOption(value: 'first', label: 'Light'),
                  ChoiceOption(
                    value: 'second',
                    label: 'Dark',
                    enabled: middleEnabled,
                  ),
                  const ChoiceOption(value: 'third', label: 'System'),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Too narrow for three labels on one line.
const double _narrow = 180;

Rect _option(WidgetTester tester, String label) =>
    tester.getRect(find.widgetWithText(InkWell, label));

/// What the group draws under its options, in its own coordinates.
Finder get _group => find.byType(ChoiceGroup<String>);

/// The box of the option at [index] of three, side by side in a group
/// [width] wide: a control's height less the track's inset.
RRect _segment(int index, double width) {
  final share = (width - 4) / 3;
  return RRect.fromLTRBR(
    2 + index * share,
    4,
    2 + (index + 1) * share,
    GerfautTouch.target - 4,
    const Radius.circular(6),
  );
}

/// The row drawn for the stacked option at [index], in a group [width]
/// wide: a control's height in a touch target, the targets 4 apart.
RRect _row(int index, double width) {
  final top = index * (GerfautTouch.target + GerfautSpacing.xs);
  return RRect.fromLTRBR(
    0,
    top + 2,
    width,
    top + 2 + GerfautTouch.control,
    const Radius.circular(GerfautRadius.md),
  );
}

void main() {
  group('side by side', () {
    testWidgets('options that fit share one line', (tester) async {
      await tester.pumpWidget(_app(value: 'first', onChanged: (_) {}));

      final first = _option(tester, 'Light');
      final second = _option(tester, 'Dark');
      final third = _option(tester, 'System');
      expect(first.top, second.top);
      expect(second.top, third.top);
      // Each answers the finger over a whole target, one beside the
      // other, none over its neighbour.
      expect(first.height, GerfautTouch.target);
      expect(first.width, greaterThanOrEqualTo(GerfautTouch.target));
      expect(second.left, closeTo(first.right, 0.01));
      expect(third.left, closeTo(second.right, 0.01));
    });

    testWidgets('the fill sits under the current option', (tester) async {
      await tester.pumpWidget(
        _app(value: 'third', onChanged: (_) {}, middleEnabled: true),
      );

      final tokens = GerfautTokens.light;
      final width = tester.getSize(_group).width;
      // One track for the three, drawn a control's height, and the fill
      // inside it under the option chosen.
      expect(
        _group,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(
              0,
              2,
              width,
              2 + GerfautTouch.control,
              const Radius.circular(GerfautRadius.md),
            ),
            color: tokens.surfaceSunken,
          )
          ..rrect(rrect: _segment(2, width), color: tokens.primary),
      );
    });

    testWidgets('the fill moves to the option picked', (tester) async {
      var value = 'first';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _app(
            value: value,
            middleEnabled: true,
            onChanged: (picked) => setState(() => value = picked),
          ),
        ),
      );
      final tokens = GerfautTokens.light;
      final width = tester.getSize(_group).width;
      expect(
        _group,
        paints
          ..rrect(color: tokens.surfaceSunken)
          ..rrect(rrect: _segment(0, width), color: tokens.primary),
      );

      await tester.tap(find.text('System'));
      // On its way: between the first option and the third.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _group,
        isNot(
          paints
            ..rrect(color: tokens.surfaceSunken)
            ..rrect(rrect: _segment(2, width), color: tokens.primary),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _group,
        paints
          ..rrect(color: tokens.surfaceSunken)
          ..rrect(rrect: _segment(2, width), color: tokens.primary),
      );
      // The ink of the label follows: on the fill where it landed.
      expect(
        tester.widget<Text>(find.text('System')).style?.color,
        tokens.onPrimary,
      );
      expect(tester.widget<Text>(find.text('Light')).style?.color, tokens.text);
    });

    testWidgets('with animations reduced the fill does not travel', (
      tester,
    ) async {
      var value = 'first';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _app(
            value: value,
            middleEnabled: true,
            still: true,
            onChanged: (picked) => setState(() => value = picked),
          ),
        ),
      );
      final tokens = GerfautTokens.light;
      final width = tester.getSize(_group).width;

      await tester.tap(find.text('System'));
      await tester.pump();
      expect(
        _group,
        paints
          ..rrect(color: tokens.surfaceSunken)
          ..rrect(rrect: _segment(2, width), color: tokens.primary),
      );
    });

    testWidgets('picking an option reports it once', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(_app(value: 'first', onChanged: picked.add));

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(picked, ['third']);
    });

    testWidgets('an option that cannot apply takes no tap', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(_app(value: 'first', onChanged: picked.add));

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);

      // Quiet rather than absent: the option still says it exists.
      final tokens = GerfautTokens.light;
      final label = tester.widget<Text>(find.text('Dark'));
      expect(label.style?.color, tokens.textMuted);
    });

    testWidgets('each option says whether it is the current one', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(value: 'first', onChanged: (_) {}));

      expect(
        tester.getSemantics(find.bySemanticsLabel('Light')),
        isSemantics(
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('System')),
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('stacked', () {
    testWidgets('a label that does not fit stacks the options', (tester) async {
      await tester.pumpWidget(
        _app(value: 'first', onChanged: (_) {}, width: _narrow),
      );

      final first = _option(tester, 'Light');
      final second = _option(tester, 'Dark');
      expect(second.top, greaterThan(first.bottom));
      expect(second.left, first.left);
    });

    testWidgets('a large text size stacks them too', (tester) async {
      await tester.pumpWidget(
        _app(value: 'first', onChanged: (_) {}, width: 260, textScale: 2),
      );

      final first = _option(tester, 'Light');
      final second = _option(tester, 'Dark');
      expect(second.top, greaterThan(first.bottom));
    });

    testWidgets('two options never touch', (tester) async {
      await tester.pumpWidget(
        _app(value: 'first', onChanged: (_) {}, width: _narrow),
      );

      // The failure this guards: options laid out with no gap read as
      // one block of colour, and adjacent touch targets need room of
      // their own to be aimed at. Each one answers the finger over a
      // full target, and the targets stand apart.
      final first = _option(tester, 'Light');
      final second = _option(tester, 'Dark');
      final third = _option(tester, 'System');
      expect(first.height, GerfautTouch.target);
      expect(second.height, GerfautTouch.target);
      expect(second.top, greaterThan(first.bottom));
      expect(third.top, greaterThan(second.bottom));
      // Each is drawn a control's height, 8 from the next.
      final tokens = GerfautTokens.light;
      final width = tester.getSize(_group).width;
      expect(_row(1, width).top - _row(0, width).bottom, GerfautSpacing.sm);
      expect(
        _group,
        paints
          ..rrect(rrect: _row(1, width), color: tokens.surfaceSunken)
          ..rrect(rrect: _row(2, width), color: tokens.surfaceSunken)
          ..rrect(rrect: _row(0, width), color: tokens.primary),
      );
    });

    testWidgets('picking an option reports it once', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _app(value: 'first', onChanged: picked.add, width: _narrow),
      );

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(picked, ['third']);
    });

    testWidgets('an option that cannot apply takes no tap', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _app(value: 'first', onChanged: picked.add, width: _narrow),
      );

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });

    testWidgets('the selected option is the only filled one', (tester) async {
      await tester.pumpWidget(
        _app(
          value: 'third',
          onChanged: (_) {},
          middleEnabled: true,
          width: _narrow,
        ),
      );

      final tokens = GerfautTokens.light;
      final width = tester.getSize(_group).width;
      expect(
        _group,
        paints
          ..rrect(rrect: _row(0, width), color: tokens.surfaceSunken)
          ..rrect(rrect: _row(1, width), color: tokens.surfaceSunken)
          ..rrect(rrect: _row(2, width), color: tokens.primary),
      );
    });
  });
}
