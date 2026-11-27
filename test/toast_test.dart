import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/toast.dart';

/// A page with one button behind the toast's place, under an optional
/// gate and with animations optionally reduced.
Widget toastApp({
  bool reduced = false,
  ValueNotifier<bool>? open,
  VoidCallback? onBehind,
}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    builder: (context, child) {
      Widget app = MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      );
      if (open != null) {
        app = ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (_, isOpen, child) => ToastGate(open: isOpen, child: child!),
          child: app,
        );
      }
      return app;
    },
    home: Scaffold(
      body: SizedBox.expand(
        child: TextButton(onPressed: onBehind, child: const Text('Behind')),
      ),
    ),
  );
}

Toast toastOf(WidgetTester tester) =>
    Toast.of(tester.element(find.byType(Scaffold).last));

double opacityOf(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(ToastView),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

/// One frame: an animation is over only on the frame after its last.
const Duration frame = Duration(milliseconds: 16);

/// Through the arrival, and the frame where it has landed and the
/// toast's time starts.
Future<void> arrive(WidgetTester tester) async {
  await tester.pump(GerfautMotion.slow);
  await tester.pump(frame);
}

/// Through the departure, the frame where it is over, and the one that
/// takes it off the screen.
Future<void> leave(WidgetTester tester) async {
  await tester.pump(GerfautMotion.base);
  await tester.pump(frame);
  await tester.pump();
}

void main() {
  testWidgets('a toast rises and fades in, stays, then leaves', (tester) async {
    await tester.pumpWidget(toastApp());
    toastOf(tester).show('Copied');
    await tester.pump();

    final start = tester.getTopLeft(find.byType(ToastView));
    expect(opacityOf(tester), 0);
    await arrive(tester);
    final end = tester.getTopLeft(find.byType(ToastView));
    expect(opacityOf(tester), 1);
    expect(start.dy - end.dy, GerfautMotion.rise);
    expect(start.dx, end.dx);

    // Still there a moment before its time is up.
    await tester.pump(toastDuration - const Duration(milliseconds: 1));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await leave(tester);
    expect(find.text('Copied'), findsNothing);
    expect(find.byType(ToastView), findsNothing);
  });

  testWidgets('a second toast takes the place of the first', (tester) async {
    await tester.pumpWidget(toastApp());
    toastOf(tester).show('Copied');
    await tester.pump();
    await arrive(tester);
    await tester.pump(const Duration(seconds: 2));

    toastOf(tester).show('Setting saved');
    await tester.pump();
    expect(find.text('Copied'), findsNothing);
    expect(find.text('Setting saved'), findsOneWidget);
    expect(find.byType(ToastView), findsOneWidget);

    // Its own three seconds, not what was left of the first one's.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Setting saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await leave(tester);
    expect(find.text('Setting saved'), findsNothing);
  });

  testWidgets('with animations reduced, it fades in place', (tester) async {
    await tester.pumpWidget(toastApp(reduced: true));
    toastOf(tester).show('Copied');
    await tester.pump();

    final places = <Offset>[];
    final fades = <double>[];
    for (var i = 0; i < 5; i++) {
      places.add(tester.getTopLeft(find.byType(ToastView)));
      fades.add(opacityOf(tester));
      await tester.pump(GerfautMotion.slow ~/ 4);
    }
    expect(places.toSet(), hasLength(1));
    expect(fades.first, 0);
    expect(fades.last, 1);

    await tester.pump(toastDuration);
    await leave(tester);
    expect(find.byType(ToastView), findsNothing);
  });

  testWidgets('it sits at the foot of the page, above the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(toastApp());
    toastOf(tester).show('Copied');
    await tester.pump();
    await arrive(tester);
    final screen = tester.getSize(find.byType(Scaffold));
    final low = tester.getBottomLeft(find.byType(ToastView));
    expect(screen.height - low.dy, 10);
    expect(low.dx, 15);
    expect(tester.getSize(find.byType(ToastView)).width, screen.width - 30);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    final raised = tester.getBottomLeft(find.byType(ToastView));
    expect(screen.height - raised.dy, 10 + 300 / tester.view.devicePixelRatio);
    await tester.pump(toastDuration);
    await leave(tester);
  });

  testWidgets('a touch beside the toast reaches the page', (tester) async {
    var taps = 0;
    await tester.pumpWidget(toastApp(onBehind: () => taps++));
    toastOf(tester).show('Copied');
    await tester.pump();
    await arrive(tester);

    await tester.tapAt(const Offset(10, 10));
    expect(taps, 1);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(toastDuration);
    await leave(tester);
  });

  testWidgets('once it starts leaving, a touch goes through it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(toastApp(onBehind: () => taps++));
    toastOf(tester).show('Copied');
    await tester.pump();
    await arrive(tester);
    await tester.pump(toastDuration);
    await tester.pump(GerfautMotion.base ~/ 4);

    // On the toast itself, while it fades out.
    await tester.tapAt(tester.getCenter(find.byType(ToastView)));
    expect(taps, 1);
    await leave(tester);
  });

  testWidgets('its words are announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(toastApp());
    toastOf(tester).show('Copied');
    await tester.pump();
    await arrive(tester);

    expect(
      tester.getSemantics(find.text('Copied')),
      isSemantics(label: 'Copied', isLiveRegion: true),
    );
    await tester.pump(toastDuration);
    await leave(tester);
    semantics.dispose();
  });

  testWidgets('it outlives the page that showed it', (tester) async {
    await tester.pumpWidget(toastApp());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      ),
    );
    await tester.pumpAndSettle();
    toastOf(tester).show('Copied');
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Detail'), findsNothing);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(toastDuration);
    await leave(tester);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('a closed gate takes the toast down and keeps new ones out', (
    tester,
  ) async {
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await tester.pumpWidget(toastApp(open: open));
    toastOf(tester).show('Copied');
    await tester.pump();
    await arrive(tester);
    expect(find.text('Copied'), findsOneWidget);

    open.value = false;
    await tester.pump();
    expect(find.byType(ToastView), findsNothing);

    toastOf(tester).show('Setting saved');
    await tester.pump();
    await arrive(tester);
    expect(find.byType(ToastView), findsNothing);

    // Open again, what was said behind it stays unsaid.
    open.value = true;
    await tester.pump();
    await arrive(tester);
    expect(find.byType(ToastView), findsNothing);
  });
}
