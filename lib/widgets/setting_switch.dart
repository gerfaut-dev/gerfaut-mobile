import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'focus_ring.dart';

/// A setting that is a switch: its name, what it does under the name,
/// and the switch at the end of the row.
///
/// One node for a screen reader. Left to themselves, the name and the
/// switch are two stops, and the switch is read alone: three of them
/// in a card become "off, switch" three times over, with no word of
/// which locks the app and which disguises it. Merged, the switch is
/// read with its name and its line.
///
/// A switch that cannot be moved is greyed and the name keeps its ink:
/// the line under it says why, as a disabled control does everywhere
/// else in Gerfaut.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    this.semanticLabel,
    this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;

  /// Read in place of the title, for a name that does not say on its
  /// own what the switch does: a wallet's name in a list of them.
  final String? semanticLabel;

  /// What the setting does, or why it cannot be changed, in a muted
  /// line under the name. Null for a name that says it all.
  final String? hint;
  final bool value;

  /// Null greys the switch out.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final name = Text(
      title,
      semanticsLabel: semanticLabel,
      style: tokens.bodySmall.copyWith(
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 500)],
      ),
    );
    final hint = this.hint;
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                if (hint != null)
                  Text(
                    hint,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          GerfautSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The switch itself, wherever one stands: a 44 × 24 track, the border
/// tone when off and the action colour when on, and a knob that slides
/// in [GerfautMotion.base] on [GerfautMotion.ease].
///
/// Drawn here rather than taken from Material: the Material 3 switch
/// overshoots its end on a curve no theme can change, and nothing in
/// Gerfaut bounces. It keeps what the platform's gave: read as a switch
/// with its state, a keyboard stop with the focus ring, Space or Enter
/// to throw it, a 48-point target, and a click under the finger.
class GerfautSwitch extends StatelessWidget {
  const GerfautSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  /// Null greys the switch out.
  final ValueChanged<bool>? onChanged;

  static const double _width = 44;
  static const double _height = 24;
  static const double _inset = 2;
  static const double _target = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final light = Theme.of(context).brightness == Brightness.light;
    final onChanged = this.onChanged;
    final enabled = onChanged != null;
    void flip() {
      if (onChanged == null) return;
      // The click of a switch thrown.
      HapticFeedback.selectionClick();
      onChanged(!value);
    }

    final still = GerfautMotion.reduced(context);
    final knob = value
        ? tokens.onPrimary
        : light
        ? tokens.surface
        : tokens.textMuted;
    final track = AnimatedContainer(
      duration: GerfautMotion.base,
      curve: GerfautMotion.ease,
      width: _width,
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: value ? tokens.primary : tokens.border,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
      ),
      child: AnimatedAlign(
        // The knob jumps to its side with animations reduced; the
        // colours still turn.
        duration: still ? Duration.zero : GerfautMotion.base,
        curve: GerfautMotion.ease,
        alignment: value
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: AnimatedContainer(
          duration: GerfautMotion.base,
          curve: GerfautMotion.ease,
          width: _height - 2 * _inset,
          height: _height - 2 * _inset,
          decoration: BoxDecoration(color: knob, shape: BoxShape.circle),
        ),
      ),
    );

    // The theme gives the switch the same colours whether or not it
    // can move: on its own a greyed switch still wears the Glacier
    // track of one that is on, and reads as on. At the opacity of
    // every disabled control, it reads as out of reach.
    return Semantics(
      toggled: value,
      enabled: enabled,
      onTap: enabled ? flip : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled ? flip : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: _target,
              minHeight: _target,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              // The ring hugs the track, not the wider target around it.
              child: FocusRing(
                radius: GerfautRadius.full,
                child: FocusableActionDetector(
                  enabled: enabled,
                  mouseCursor: enabled
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) => flip(),
                    ),
                  },
                  child: track,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
