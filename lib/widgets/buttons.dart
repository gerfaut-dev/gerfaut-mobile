import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'focus_ring.dart';
import 'tap_target.dart';
import 'motion.dart';

// Every labelled button is filled: a word alone, with no fill and no
// edge, does not read as something to press. A button switched off
// gives its fill up for a hairline, so it no longer reads as one.
//
// - [PrimaryButton]: an action that stands on its own, the action of a
//   card, a form that saves, the yes of a dialog. Every one of them,
//   not one per screen; when two sit side by side, the one people come
//   for is primary and the other secondary.
// - [SecondaryButton]: the way out beside a primary (Cancel, Back,
//   Later, Skip), one of several equal choices, and the actions a list
//   repeats on every row.
// - [DangerButton]: the yes of a confirmation that erases, never the
//   button that opens it.
// - [DisclosureButton]: shows or hides the part of the page under it.
//   It does nothing, it shows, so it is the one labelled button left
//   without a fill.
//
// Every button here is drawn [GerfautTouch.control] tall and answers the
// finger over [GerfautTouch.target]: the extra height is invisible
// padding, so a tap just above or below the button still presses it.

/// An action that stands on its own: Glacier fill, a darker Glacier
/// under the finger.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;

  /// Null switches the button off: no fill, a hairline and muted ink,
  /// nothing on press.
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Fills the available width: the thumb-reachable bottom action.
  final bool expand;

  /// Working on it: a spinner takes the icon's place and the button
  /// keeps its full colour, since it is not off but busy. Presses are
  /// ignored. The label says what is going on ("Saving…").
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      busy: busy,
      fill: tokens.primary,
      pressedFill: tokens.primaryPressed,
      ink: tokens.onPrimary,
    );
  }
}

/// The second choice, which is still a button: Givre fill, no border.
///
/// On a tinted panel (a notice, see [TintedSurface]) the Givre would
/// read as a dirty grey in the light theme, so it takes the card white
/// with a hairline instead. The dark theme keeps its fill there, the
/// panel being the card surface.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// As [PrimaryButton.busy].
  final bool busy;

  /// For a screen that hands the keyboard's focus on to it.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onTint = !dark && TintedSurface.of(context);
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      busy: busy,
      fill: onTint ? tokens.surface : tokens.surfaceSunken,
      // Brume at 60% over the fill, as the desktop's hover; on a tint,
      // the page canvas under the white.
      pressedFill: onTint
          ? tokens.background
          : Color.alphaBlend(
              tokens.border.withValues(alpha: 0.6),
              tokens.surfaceSunken,
            ),
      ink: tokens.text,
      edge: onTint ? tokens.border : null,
      focusNode: focusNode,
    );
  }
}

/// The yes of a confirmation that erases, and nothing else: the
/// primary's form in the alert colour. The button that opens the
/// confirmation stays a [SecondaryButton]; red appears at the yes.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// As [PrimaryButton.busy].
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      busy: busy,
      fill: tokens.alert,
      pressedFill: tokens.alertPressed,
      ink: tokens.onAlert,
    );
  }
}

/// Shows or hides the part of the page under it: a chevron, then the
/// label in Ardoise, Givre under the finger. Not an action, so no fill;
/// a fill would make it pass for one. Read out with whether it is open.
class DisclosureButton extends StatelessWidget {
  const DisclosureButton({
    super.key,
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final String label;

  /// Whether what it folds is shown: the chevron points up, and a screen
  /// reader says "expanded".
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // One node: the button, and whether what it folds is open.
    return MergeSemantics(
      child: Semantics(
        expanded: open,
        child: TapTarget(
          child: SizedBox(
            height: GerfautTouch.control,
            // No fill at rest; Givre, whole, under the finger. Material's
            // own overlay would lay it at a tenth of its strength, which
            // vanishes on a card. The keyboard gets the ring instead of
            // a tint, inside its edge: it often sits flush with the side of
            // a scroll view, which would clip a ring drawn outside.
            child: FocusRing(
              gap: 0,
              child: TextButton(
                style:
                    TextButton.styleFrom(
                      foregroundColor: tokens.textMuted,
                      overlayColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                      padding: const EdgeInsets.symmetric(
                        horizontal: GerfautSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(GerfautRadius.md),
                      ),
                      textStyle: _labelStyle(tokens),
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.pressed)
                            ? tokens.surfaceSunken
                            : Colors.transparent,
                      ),
                    ),
                onPressed: onPressed,
                child: _Content(
                  label: label,
                  leading: Icon(
                    open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: _glyph,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks a tinted panel, a notice, for the buttons inside it: a
/// [SecondaryButton] there takes white and a hairline instead of Givre.
/// The panel sets it once, so no caller has to remember.
class TintedSurface extends InheritedWidget {
  const TintedSurface({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TintedSurface>() != null;

  @override
  bool updateShouldNotify(TintedSurface oldWidget) => false;
}

/// The two buttons that close a confirmation: the way out and the deed,
/// in that order, the deed at the end where the thumb expects the last
/// word.
///
/// A Wrap and not a Row: at a large text size two labels do not share
/// a line on a phone, and the deed then goes to a line of its own under
/// the way out rather than past the edge of the panel. Aligned to the
/// end whichever column it sits in.
class ConfirmActions extends StatelessWidget {
  const ConfirmActions({
    super.key,
    required this.cancel,
    required this.confirm,
  });

  final Widget cancel;
  final Widget confirm;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: GerfautSpacing.sm,
        runSpacing: GerfautSpacing.sm,
        children: [cancel, confirm],
      ),
    );
  }
}

/// The glyph before a label, and the spinner that takes its place.
const double _glyph = 16;

TextStyle _labelStyle(GerfautTokens tokens) => tokens.bodySmall.copyWith(
  fontWeight: FontWeight.w500,
  fontVariations: const [FontVariation('wght', 500)],
);

/// The one filled button the three variants draw: geometry, press,
/// busy, off and focus in one place, so no screen styles its own.
class _FilledAction extends StatefulWidget {
  const _FilledAction({
    required this.label,
    required this.onPressed,
    required this.icon,
    required this.expand,
    required this.busy,
    required this.fill,
    required this.pressedFill,
    required this.ink,
    this.edge,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool busy;
  final Color fill;
  final Color pressedFill;
  final Color ink;

  /// A hairline around the fill, for the secondary on a tint.
  final Color? edge;
  final FocusNode? focusNode;

  @override
  State<_FilledAction> createState() => _FilledActionState();
}

class _FilledActionState extends State<_FilledAction> {
  /// A finger is down on it: the button gives a little.
  bool _pressed = false;

  /// Focused from a keyboard: the ring shows.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final busy = widget.busy;
    final off = widget.onPressed == null && !busy;
    final radius = BorderRadius.circular(GerfautRadius.md);

    // Busy keeps its colour. Off gives up its fill for a hairline and
    // muted ink: fading the whole button would drop the label below a
    // readable contrast, and turning the fill grey would pass it for a
    // secondary. Hollow, it differs from every live button by its form.
    final fill = off ? Colors.transparent : widget.fill;
    final ink = off ? tokens.textMuted : widget.ink;
    final edge = off ? tokens.border : widget.edge;

    final style =
        FilledButton.styleFrom(
          foregroundColor: ink,
          disabledBackgroundColor: fill,
          disabledForegroundColor: ink,
          elevation: 0,
          // Under the finger the fill itself darkens; no ripple on top.
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: edge == null ? BorderSide.none : BorderSide(color: edge),
          ),
          textStyle: _labelStyle(tokens),
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed) && !off
                ? widget.pressedFill
                : fill,
          ),
        );

    final live = !busy && widget.onPressed != null;
    void press(bool down) {
      if (_pressed != down) setState(() => _pressed = down);
    }

    // Pressed, the button gives a little (0.96, never less); focused
    // from a keyboard, it gets the 2px Glacier ring, 2px out, which
    // stands clear of a filled button in both themes. Only in the
    // keyboard's highlight mode: a touch never shows a ring.
    final ring =
        _focused &&
        live &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final button = CustomPaint(
      foregroundPainter: ring
          ? FocusRingPainter(color: tokens.primary, radius: GerfautRadius.md)
          : null,
      child: Listener(
        onPointerDown: live ? (_) => press(true) : null,
        onPointerUp: (_) => press(false),
        onPointerCancel: (_) => press(false),
        child: AnimatedScale(
          // The press moves nothing around the button, so it stays
          // with animations reduced.
          scale: _pressed && live ? GerfautMotion.press : 1,
          duration: GerfautMotion.fast,
          curve: GerfautMotion.ease,
          child: FilledButton(
            style: style,
            focusNode: widget.focusNode,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
            },
            onPressed: live ? widget.onPressed : null,
            child: _FilledContent(
              label: widget.label,
              icon: widget.icon,
              busy: busy,
            ),
          ),
        ),
      ),
    );

    return TapTarget(
      child: SizedBox(
        height: GerfautTouch.control,
        width: widget.expand ? double.infinity : null,
        child: button,
      ),
    );
  }
}

/// What a filled button shows: its glyph, or the spinner while busy,
/// then its label. When its state changes ("Add wallet", then "Adding…";
/// a busy label that moves on; a glyph that changes), the old fades into
/// the new in place, and the button keeps the room of the widest label
/// it showed, during the fade and after it, so neither it nor what
/// stands beside it moves.
///
/// A label that changes at rest is a value ("Restore 3 wallets"): it is
/// replaced in the same frame, as an amount is, and the button takes its
/// width.
class _FilledContent extends StatefulWidget {
  const _FilledContent({
    required this.label,
    required this.icon,
    required this.busy,
  });

  final String label;
  final IconData? icon;
  final bool busy;

  @override
  State<_FilledContent> createState() => _FilledContentState();
}

class _FilledContentState extends State<_FilledContent> {
  /// Counts the changes of state, which fade.
  int _change = 0;

  /// The labels shown since the last change at rest, each with whether a
  /// glyph stood before it: held unseen for their width.
  final List<(String, bool)> _held = [];

  @override
  void didUpdateWidget(_FilledContent old) {
    super.didUpdateWidget(old);
    final was = (old.label, old.busy || old.icon != null);
    final now = (widget.label, widget.busy || widget.icon != null);
    if (old.label == widget.label &&
        old.busy == widget.busy &&
        old.icon == widget.icon) {
      return;
    }
    if (old.busy || widget.busy || old.icon != widget.icon) {
      _change++;
      if (!_held.contains(was)) _held.add(was);
    } else {
      _held.clear();
    }
    _held.remove(now);
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        FadeInPlace(
          state: _change,
          alignment: Alignment.center,
          child: _Content(
            label: widget.label,
            leading: widget.busy
                // Still with animations reduced: the label carries the
                // state.
                ? const TurningIcon(turning: true, size: _glyph)
                : (icon == null ? null : Icon(icon, size: _glyph)),
          ),
        ),
        for (final (label, glyph) in _held)
          HeldPlace(
            // On one line, as the label it stands beside: wrapped, it
            // would hold a height the button does not have.
            child: glyph
                ? _Content(
                    label: label,
                    leading: const SizedBox.square(dimension: _glyph),
                  )
                : Text(label, maxLines: 1, softWrap: false),
          ),
      ],
    );
  }
}

/// The glyph, if any, then the label. The height is fixed, so a label
/// wider than the phone at a large text size gives ground at its end
/// rather than running past the button.
class _Content extends StatelessWidget {
  const _Content({required this.label, required this.leading});

  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    if (leading == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: GerfautSpacing.sm),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
