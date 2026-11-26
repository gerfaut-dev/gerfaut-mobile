import 'package:flutter/material.dart';

/// A glyph drawn in Lucide's grammar, for the few shapes Lucide does
/// not have: a path in a 24 unit box, stroked at 1.5 with round caps
/// and joins, never filled, in the current colour. Drawn to the same
/// rules as the set it stands in, it cannot be told from its
/// neighbours.
///
/// Size and colour come from the surrounding [IconTheme], exactly as
/// they do for [Icon], so a caller that sets neither matches whatever
/// row it sits in.
class StrokeGlyph extends StatelessWidget {
  const StrokeGlyph(
    this.path, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  /// The box every path is drawn in.
  static const double box = 24;

  /// The width of the stroke, in units of [box].
  static const double strokeWidth = 1.5;

  /// The drawing, in a [box] unit square.
  final Path path;

  /// Falls back to the ambient icon theme, then to Material's own 24.
  final double? size;

  /// Falls back to the ambient icon theme, then to the text colour.
  final Color? color;

  /// Said out loud when the glyph carries meaning of its own. Left
  /// unset beside a title that already names it: an icon that repeats
  /// the word next to it makes a screen reader say it twice.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? box;
    final base =
        color ?? theme.color ?? DefaultTextStyle.of(context).style.color;
    // Dimmed with the theme's opacity, as [Icon] is: a drawn glyph in a
    // faded row fades with its Lucide neighbours.
    final opacity = theme.opacity ?? 1;
    final tint = base?.withValues(alpha: base.a * opacity);
    // Sized and centred the way [Icon] is, so a parent that forces a
    // larger box gets a glyph of the asked size in its middle rather
    // than one stretched to fill it.
    final glyph = SizedBox.square(
      dimension: side,
      child: Center(
        child: CustomPaint(
          size: Size.square(side),
          painter: _StrokePainter(path, tint ?? const Color(0xFF000000)),
        ),
      ),
    );
    if (semanticLabel == null) return glyph;
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

/// The canvas is scaled rather than the coordinates, so the 1.5 stroke
/// thins with the glyph the way a font would, instead of thickening at
/// 16px.
class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.path, this.color);

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / StrokeGlyph.box, size.height / StrokeGlyph.box);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = StrokeGlyph.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.color != color || old.path != path;
}
