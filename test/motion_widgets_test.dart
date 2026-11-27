import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/motion.dart';
import 'package:gerfaut/widgets/setting_switch.dart';

Widget _app(Widget body, {bool still = false}) => MaterialApp(
  theme: themeFrom(GerfautTokens.light, Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: still),
    child: child!,
  ),
  home: Scaffold(body: Center(child: body)),
);

/// The haptic calls the platform receives.
List<String> _listenToHaptics(WidgetTester tester) {
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
  return calls;
}

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byType(TurningIcon),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

void main() {
  group('a fade in place', () {
    testWidgets('replaces an amount in the same frame', (tester) async {
      await tester.pumpWidget(
        _app(const FadeInPlace(state: 'data', child: Text('1 000 sats'))),
      );
      await tester.pumpWidget(
        _app(const FadeInPlace(state: 'data', child: Text('2 000 sats'))),
      );
      // No time has passed: a balance never fades from one value to
      // the next.
      expect(find.text('1 000 sats'), findsNothing);
      expect(find.text('2 000 sats'), findsOne);
    });

    testWidgets('fades one state into the next', (tester) async {
      await tester.pumpWidget(
        _app(const FadeInPlace(state: 'loading', child: Text('Loading…'))),
      );
      await tester.pumpWidget(
        _app(const FadeInPlace(state: 'data', child: Text('2 000 sats'))),
      );
      await tester.pump(GerfautMotion.base ~/ 2);
      expect(find.text('Loading…'), findsOne);
      expect(find.text('2 000 sats'), findsOne);
      await tester.pumpAndSettle();
      expect(find.text('Loading…'), findsNothing);
    });
  });

  group('a turning icon', () {
    Widget icon(bool turning, {bool still = false}) =>
        _app(TurningIcon(turning: turning), still: still);

    testWidgets('stands still with animations reduced', (tester) async {
      await tester.pumpWidget(icon(true, still: true));
      await tester.pump(GerfautMotion.turn ~/ 3);
      expect(_turns(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('finishes its turn before it stops', (tester) async {
      await tester.pumpWidget(icon(true));
      await tester.pump(GerfautMotion.turn ~/ 4);
      final stoppedAt = _turns(tester);
      await tester.pumpWidget(icon(false));
      await tester.pump(GerfautMotion.turn ~/ 4);
      expect(_turns(tester), greaterThan(stoppedAt));
      await tester.pump(GerfautMotion.turn);
      expect(_turns(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('turns on when the action resumes in its last turn', (
      tester,
    ) async {
      await tester.pumpWidget(icon(true));
      await tester.pump(GerfautMotion.turn ~/ 4);
      await tester.pumpWidget(icon(false));
      await tester.pump(GerfautMotion.turn ~/ 4);
      await tester.pumpWidget(icon(true));
      // Well past the end of the last turn: it is still turning.
      await tester.pump(GerfautMotion.turn * 2);
      expect(tester.hasRunningAnimations, isTrue);
    });
  });

  group('a bottom sheet', () {
    Widget opener({required bool still}) => _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showGerfautSheet<void>(
            context: context,
            builder: (_) => const SizedBox(height: 200, child: Text('Sheet')),
          ),
          child: const Text('Open'),
        ),
      ),
      still: still,
    );

    testWidgets('appears at once with animations reduced', (tester) async {
      await tester.pumpWidget(opener(still: true));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();
      final first = tester.getTopLeft(find.text('Sheet'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Sheet')), first);
    });

    testWidgets('rises otherwise', (tester) async {
      await tester.pumpWidget(opener(still: false));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(GerfautMotion.slow ~/ 5);
      final early = tester.getTopLeft(find.text('Sheet'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Sheet')).dy, lessThan(early.dy));
    });
  });

  group('a switch', () {
    testWidgets('clicks when thrown, and its knob never overshoots', (
      tester,
    ) async {
      final calls = _listenToHaptics(tester);
      var value = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _app(
            GerfautSwitch(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      );
      final knob = find.descendant(
        of: find.byType(GerfautSwitch),
        matching: find.byType(AnimatedContainer),
      );
      await tester.tap(find.byType(GerfautSwitch));
      expect(value, isTrue);
      expect(calls, ['HapticFeedbackType.selectionClick']);

      final travelled = <double>[];
      for (var i = 0; i < 10; i++) {
        await tester.pump(GerfautMotion.base ~/ 10);
        travelled.add(tester.getTopLeft(knob.last).dx);
      }
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(knob.last).dx;
      for (final x in travelled) {
        expect(x, lessThanOrEqualTo(end));
      }
    });

    testWidgets('is thrown from the keyboard and reads as a switch', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _app(
            GerfautSwitch(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(GerfautSwitch)),
        matchesSemantics(
          hasToggledState: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(
        tester.getSemantics(find.byType(GerfautSwitch)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          isFocused: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(tester.getSize(find.byType(GerfautSwitch)).height, 48);
      handle.dispose();
    });
  });
}
