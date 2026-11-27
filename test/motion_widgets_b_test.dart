import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/sync_indicator.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(body: child),
  ),
);

SyncStamp _stampAgo(Duration age) => SyncStamp(
  at: DateTime.now().subtract(age).millisecondsSinceEpoch ~/ 1000,
  tipHeight: 912345,
  backend: 'mempool.space',
);

void main() {
  testWidgets('the sync line does not fade when only its time moves on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SyncIndicator(
          stamp: _stampAgo(const Duration(minutes: 2)),
          syncing: false,
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        SyncIndicator(
          stamp: _stampAgo(const Duration(minutes: 3)),
          syncing: false,
        ),
      ),
    );
    await tester.pump();
    // Still synced: the newer words stand alone, with no older line
    // fading out under them.
    expect(find.textContaining('Synced', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the sync line fades when its state changes', (tester) async {
    final stamp = _stampAgo(const Duration(minutes: 2));
    await tester.pumpWidget(_host(SyncIndicator(stamp: stamp, syncing: false)));
    await tester.pumpWidget(_host(SyncIndicator(stamp: stamp, syncing: true)));
    await tester.pump(GerfautMotion.base ~/ 2);
    // Midway, the synced line is still fading out under the syncing
    // one, which alone reads as the line.
    expect(find.textContaining('Synced', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Synced'), findsNothing);
    expect(find.textContaining('last sync'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('Synced', skipOffstage: false), findsNothing);
  });

  testWidgets('a failure reason opens its place under the line', (
    tester,
  ) async {
    final stamp = _stampAgo(const Duration(minutes: 2));
    await tester.pumpWidget(_host(SyncIndicator(stamp: stamp, syncing: false)));
    final before = tester.getSize(find.byType(SyncIndicator)).height;
    await tester.pumpWidget(
      _host(
        SyncIndicator(stamp: stamp, syncing: false, error: 'Server refused'),
      ),
    );
    await tester.pump(GerfautMotion.base ~/ 2);
    final midway = tester.getSize(find.byType(SyncIndicator)).height;
    await tester.pumpAndSettle();
    final open = tester.getSize(find.byType(SyncIndicator)).height;
    // The place grows by degrees rather than in one jump.
    expect(midway, greaterThan(before));
    expect(midway, lessThan(open));
    expect(find.text('Server refused'), findsOneWidget);
  });
}
