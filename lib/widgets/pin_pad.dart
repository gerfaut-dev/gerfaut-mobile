import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// The longest PIN the core takes.
const int pinMaxLength = 12;

/// The digits in the order a phone's own keypad has them: 1 to 9, then
/// 0 under the 8.
const List<int> phoneOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];

/// Where the shuffled orders come from. A secure source: an order that
/// could be guessed would tell where the finger went. Tests give a
/// seeded one.
final pinPadRandomProvider = Provider<Random>((ref) => Random.secure());

/// The ten digits in a new order drawn from [random].
List<int> shuffledDigits(Random random) => [...phoneOrder]..shuffle(random);

/// One dot per digit typed, so the length shows and the digits do not.
/// Empty, it says what to do, in the same height: the pad under it does
/// not move as the first digit lands.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.count, this.refused = false});

  final int count;

  /// The digits were just refused: the dots turn the alert colour,
  /// with no shake, until the next key.
  final bool refused;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final said = refused
        ? 'PIN refused'
        : switch (count) {
            0 => 'PIN, no digits entered',
            1 => 'PIN, 1 digit entered',
            _ => 'PIN, $count digits entered',
          };
    return Semantics(
      container: true,
      label: said,
      liveRegion: true,
      excludeSemantics: true,
      // A floor, not a height: at a large text size the words grow, and
      // the row grows with them.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Center(
          child: count == 0
              ? Text(
                  'Enter your PIN',
                  style: tokens.body.copyWith(color: tokens.textMuted),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < count; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          left: i == 0 ? 0 : GerfautSpacing.sm,
                        ),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: refused ? tokens.alert : tokens.text,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The lock screen's own keypad for a PIN, in place of the phone's
/// keyboard, which may be a third party's and would see every digit.
///
/// Three columns, four rows: the first nine of [order] row by row, then
/// an empty cell, the tenth, and the key that deletes. The keys are as
/// tall as the room allows, from [minKeyHeight] to [keyHeight].
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.order,
    required this.onDigit,
    required this.onDelete,
    required this.onClear,
    this.enabled = true,
  }) : assert(order.length == 10);

  /// The ten digits, in the order they are laid out.
  final List<int> order;
  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;

  /// A long press on the delete key: everything typed goes.
  final VoidCallback onClear;

  /// Off while the core makes the user wait: the keys fade and answer
  /// nothing.
  final bool enabled;

  static const double keyHeight = 64;
  static const double minKeyHeight = GerfautTouch.target;
  static const double gap = GerfautSpacing.sm;
  static const double maxWidth = 320;

  /// The height of the whole pad with the tallest keys.
  static const double fullHeight = keyHeight * 4 + gap * 3;

  @override
  Widget build(BuildContext context) {
    Widget key(int index) {
      if (index == 9) return const SizedBox.shrink();
      if (index == 11) {
        return _PadKey(
          key: const Key('pin.delete'),
          label: 'Delete',
          enabled: enabled,
          onTap: onDelete,
          onLongPress: onClear,
          child: const _KeyGlyph(icon: LucideIcons.delete),
        );
      }
      final digit = order[index == 10 ? 9 : index];
      return _PadKey(
        key: Key('pin.$digit'),
        label: '$digit',
        enabled: enabled,
        onTap: () => onDigit(digit),
        child: _KeyGlyph(digit: digit),
      );
    }

    final rows = <Widget>[];
    for (var row = 0; row < 4; row++) {
      if (row > 0) rows.add(const SizedBox(height: gap));
      rows.add(
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minKeyHeight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 3; column++) ...[
                  if (column > 0) const SizedBox(width: gap),
                  Expanded(child: key(row * 3 + column)),
                ],
              ],
            ),
          ),
        ),
      );
    }
    // At 45% and out of reach, as every control switched off in
    // Gerfaut; still read out, as switched off.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: fullHeight,
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Column(children: rows),
          ),
        ),
      ),
    );
  }
}

/// What a key shows: a digit in the heading face with tabular figures,
/// so the ten line up whatever their order, or the delete glyph.
class _KeyGlyph extends StatelessWidget {
  const _KeyGlyph({this.digit, this.icon});

  final int? digit;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final icon = this.icon;
    return Center(
      child: icon != null
          ? Icon(icon, size: 24, color: tokens.text)
          // At a large text size the digit shrinks to its key rather
          // than spill out of it.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$digit',
                style: tokens.h1.copyWith(
                  color: tokens.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
    );
  }
}

/// One key: a Givre rectangle at the small radius, never a round one,
/// that takes the border tint under the finger and gives a click.
class _PadKey extends StatefulWidget {
  const _PadKey({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    required this.enabled,
    this.onLongPress,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  // A click under each key: a PIN pad has no other answer under the
  // finger, the digits it takes being drawn as dots.
  void _tap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  // The hold that clears the whole PIN is felt as such.
  void _longPress() {
    _press(false);
    HapticFeedback.mediumImpact();
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final longPress = widget.onLongPress == null ? null : _longPress;
    return Semantics(
      container: true,
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: _tap,
      onLongPress: longPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: _tap,
        onLongPress: longPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // The secondary button's press: Brume at 60% over the Givre.
            color: _pressed
                ? Color.alphaBlend(
                    tokens.border.withValues(alpha: 0.6),
                    tokens.surfaceSunken,
                  )
                : tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
