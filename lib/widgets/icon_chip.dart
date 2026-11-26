import 'package:flutter/material.dart';

/// The square, rounded chip that opens a row: which way a transaction
/// went, what an input or an output is to the wallet. One size, one
/// corner and one glyph size, whatever the row.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required IconData this.icon,
    required this.ink,
    required this.fill,
    this.semanticLabel,
  }) : glyph = null;

  /// The chip around a glyph that is a widget rather than a font
  /// glyph: a wallet's icon, which may be drawn. It is handed the same
  /// size and the same ink through the [IconTheme], and says out loud
  /// whatever it says itself.
  const IconChip.glyph({
    super.key,
    required Widget this.glyph,
    required this.ink,
    required this.fill,
  }) : icon = null,
       semanticLabel = null;

  /// The side of the square.
  static const double side = 32;

  /// The side of the glyph in it.
  static const double glyphSize = 16;

  /// The font glyph, unless [glyph] is set.
  final IconData? icon;

  /// The widget glyph, unless [icon] is set.
  final Widget? glyph;

  /// The colour of the glyph.
  final Color ink;

  /// The colour of the square under it.
  final Color fill;

  /// What the glyph says out loud, when no text beside it says it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: switch (glyph) {
        final glyph? => Center(
          child: IconTheme.merge(
            data: IconThemeData(size: glyphSize, color: ink),
            child: glyph,
          ),
        ),
        null => Icon(
          icon,
          size: glyphSize,
          color: ink,
          semanticLabel: semanticLabel,
        ),
      },
    );
  }
}
