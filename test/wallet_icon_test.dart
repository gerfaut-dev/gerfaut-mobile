import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/stroke_glyph.dart';
import 'package:gerfaut/widgets/wallet_icon.dart';

Widget framed(Widget child) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(body: Center(child: child)),
  );
}

/// Points along the stroke itself, not the control points of its
/// curves: what a bounds check has to hold to.
Iterable<Offset> pointsOn(Path path) sync* {
  for (final metric in path.computeMetrics()) {
    for (var at = 0.0; at < metric.length; at += 0.1) {
      yield metric.getTangentForOffset(at)!.position;
    }
    // The end of the stroke, which the steps may fall short of.
    yield metric.getTangentForOffset(metric.length)!.position;
  }
}

void main() {
  test('every drawn icon stays inside its box, its stroke included', () {
    // Half the stroke falls outside the path: past that margin, the
    // glyph would be cut at the edge of its box.
    const margin = StrokeGlyph.strokeWidth / 2;
    var drawn = 0;
    for (final icon in WalletIcon.values) {
      final source = walletGlyphSource(icon);
      if (source is! DrawnGlyph) continue;
      drawn++;
      final points = pointsOn(source.path).toList();
      expect(points, isNotEmpty, reason: icon.id);
      for (final point in points) {
        expect(
          point.dx,
          inInclusiveRange(margin, StrokeGlyph.box - margin),
          reason: icon.id,
        );
        expect(
          point.dy,
          inInclusiveRange(margin, StrokeGlyph.box - margin),
          reason: icon.id,
        );
      }
    }
    expect(drawn, greaterThan(0));
  });

  testWidgets('a drawn device is stroked like the Lucide symbols', (
    tester,
  ) async {
    const ink = Color(0xFF0E7490);
    await tester.pumpWidget(
      framed(const WalletGlyph(WalletIcon.nfcCard, size: 16, color: ink)),
    );

    expect(tester.getSize(find.byType(StrokeGlyph)), const Size.square(16));
    expect(
      tester.renderObject(find.byType(CustomPaint).last),
      paints..path(color: ink, strokeWidth: 1.5, style: PaintingStyle.stroke),
    );
  });

  testWidgets('on a small phone, the sheet opens on the current icon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      framed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                WalletIconPicker.show(context, current: WalletIcon.values.last),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final tile = tester.getRect(
      find.bySemanticsLabel(WalletIcon.values.last.label),
    );
    expect(tile.top, greaterThanOrEqualTo(0));
    expect(tile.bottom, lessThanOrEqualTo(560));
  });

  testWidgets('a drawn glyph fades with the icon theme, as Icon does', (
    tester,
  ) async {
    const ink = Color(0xFF0E7490);
    await tester.pumpWidget(
      framed(
        const IconTheme(
          data: IconThemeData(color: ink, opacity: 0.5),
          child: WalletGlyph(WalletIcon.nfcCard, size: 16),
        ),
      ),
    );

    expect(
      tester.renderObject(find.byType(CustomPaint).last),
      paints..path(color: ink.withValues(alpha: 0.5)),
    );
  });

  testWidgets('the picker shows the symbols, then the devices, and answers '
      'with the one tapped', (tester) async {
    WalletIcon? picked;
    await tester.pumpWidget(
      framed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await WalletIconPicker.show(
              context,
              current: WalletIcon.wallet,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final symbols = tester.getTopLeft(find.bySemanticsLabel('Symbols'));
    final devices = tester.getTopLeft(find.bySemanticsLabel('Devices'));
    expect(devices.dy, greaterThan(symbols.dy));
    // The devices section holds the drawn ones, below its heading.
    final device = find.bySemanticsLabel(WalletIcon.nfcCard.label);
    await tester.ensureVisible(device);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(device).dy,
      greaterThan(tester.getTopLeft(find.bySemanticsLabel('Devices')).dy),
    );

    await tester.tap(device);
    await tester.pumpAndSettle();
    expect(picked, WalletIcon.nfcCard);
    expect(find.byType(WalletIconPicker), findsNothing);
  });
}
