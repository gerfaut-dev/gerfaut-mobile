import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// A bounded block that changes state in place (loading, content, empty,
/// error; the sync line; copy then copied): the old state fades into the
/// new one in [GerfautMotion.base], both drawn from the same top-left
/// corner so nothing around them jumps.
///
/// The fade follows [state], never the value shown: a balance that
/// changes inside the same state is replaced in the same frame, as a
/// change of balance is never animated.
///
/// Never around a whole page or a list that scrolls: an opacity over a
/// large surface is the costly part of a fade.
class FadeInPlace extends StatelessWidget {
  const FadeInPlace({
    super.key,
    required this.state,
    required this.child,
    this.alignment = AlignmentDirectional.topStart,
  });

  /// What the block is showing: a new state fades, the same one does not.
  final Object? state;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: GerfautMotion.base,
      switchInCurve: GerfautMotion.ease,
      switchOutCurve: GerfautMotion.ease.flipped,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey<Object?>(state), child: child),
    );
  }
}

/// The icon of a copy button: copy, then a check for
/// [GerfautMotion.hold] once copied, the one fading into the other in
/// place. The word or the toast beside it says it too.
class CopyGlyph extends StatelessWidget {
  const CopyGlyph({super.key, required this.copied, this.size, this.color});

  final bool copied;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FadeInPlace(
      state: copied,
      alignment: Alignment.center,
      child: Icon(
        copied ? LucideIcons.check : LucideIcons.copy,
        size: size,
        color: color,
      ),
    );
  }
}

/// A note, an error or a detail that appears: its height opens in
/// [GerfautMotion.base] while it fades in, and what follows moves down
/// with it rather than in one jump. Null closes the place the same way.
///
/// With animations reduced the place opens at once and only the fade is
/// left. Never around a list that scrolls.
class OpeningPlace extends StatelessWidget {
  const OpeningPlace({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    return AnimatedSize(
      duration: GerfautMotion.reduced(context)
          ? Duration.zero
          : GerfautMotion.base,
      curve: GerfautMotion.ease,
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        duration: GerfautMotion.base,
        switchInCurve: GerfautMotion.ease,
        switchOutCurve: GerfautMotion.ease.flipped,
        // What leaves is laid over the place rather than holding it
        // open: the height follows what stays, and the old block fades
        // out as the place closes over it.
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.topStart,
          children: [
            for (final old in previous)
              PositionedDirectional(top: 0, start: 0, end: 0, child: old),
            ?current,
          ],
        ),
        child: child == null
            ? const SizedBox(key: ValueKey(false), width: double.infinity)
            : KeyedSubtree(key: const ValueKey(true), child: child),
      ),
    );
  }
}

/// The icon of an action under way: one turn in [GerfautMotion.turn],
/// on [GerfautMotion.linear], the only loop of the app.
///
/// A turn that has started finishes before the icon stops, and starts
/// over if the action resumes during that last turn. With animations
/// reduced it stands still; the words beside it say the state.
class TurningIcon extends StatefulWidget {
  const TurningIcon({
    super.key,
    required this.turning,
    this.icon = LucideIcons.loaderCircle,
    this.size,
    this.color,
  });

  final bool turning;
  final IconData icon;
  final double? size;
  final Color? color;

  @override
  State<TurningIcon> createState() => _TurningIconState();
}

class _TurningIconState extends State<TurningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: GerfautMotion.turn,
  );

  /// The action is over and the last turn is running out.
  bool _finishing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  @override
  void didUpdateWidget(TurningIcon old) {
    super.didUpdateWidget(old);
    if (old.turning != widget.turning) _apply();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _apply() {
    final still = GerfautMotion.reduced(context);
    if (widget.turning && !still) {
      if (!_turn.isAnimating || _finishing) {
        _finishing = false;
        // From wherever the icon stands: no jump back to the start.
        _turn.repeat();
      }
      return;
    }
    if (still) {
      _finishing = false;
      _turn
        ..stop()
        ..value = 0;
      return;
    }
    if (!_turn.isAnimating || _finishing) return;
    _finishing = true;
    _turn.forward().then((_) {
      if (!mounted || !_finishing) return;
      _finishing = false;
      _turn.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _turn,
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}

/// A modal bottom sheet on the motion of every surface: it rises in
/// [GerfautMotion.slow] and leaves in [GerfautMotion.base] on
/// [GerfautMotion.ease]; with animations reduced it appears and leaves
/// at once. Every bottom sheet of the app goes through here.
Future<T?> showGerfautSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  BoxConstraints? constraints,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    constraints: constraints,
    shape: shape,
    sheetAnimationStyle: GerfautMotion.sheet(context),
  );
}

/// One screen standing in for another at the root of the app: the lock,
/// the start, home.
///
/// The screen that leaves fades away over the one that arrives, in
/// [GerfautMotion.base]. A screen that must cover everything at once
/// ([cut], the lock) appears in the same frame, with nothing of the old
/// one showing through. The old screen keeps its state while it fades:
/// it is the same element, moved under the fade, never built anew.
class ScreenFade extends StatefulWidget {
  const ScreenFade({
    super.key,
    required this.state,
    required this.child,
    this.cut = false,
  });

  /// Which screen this is: a new state fades, the same one does not.
  final Object state;
  final Widget child;

  /// Appear at once over whatever was there.
  final bool cut;

  @override
  State<ScreenFade> createState() => _ScreenFadeState();
}

class _ScreenFadeState extends State<ScreenFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: GerfautMotion.base,
    value: 1,
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _fade,
    curve: GerfautMotion.ease,
  );

  ScreenFade? _leaving;

  @override
  void didUpdateWidget(ScreenFade old) {
    super.didUpdateWidget(old);
    if (old.state == widget.state) return;
    if (widget.cut) {
      _fade.value = 1;
      _leaving = null;
      return;
    }
    _leaving = old;
    _fade.reverse(from: 1).then((_) {
      if (mounted) setState(() => _leaving = null);
    });
  }

  @override
  void dispose() {
    _eased.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// The same shape for the screen that stays and the one that leaves,
  /// so a screen that starts leaving keeps its element and its state.
  Widget _slot(ScreenFade screen, {required bool leaving}) => KeyedSubtree(
    key: ValueKey<Object>(screen.state),
    child: IgnorePointer(
      ignoring: leaving,
      child: ExcludeSemantics(
        excluding: leaving,
        child: FadeTransition(
          opacity: leaving ? _eased : kAlwaysCompleteAnimation,
          child: screen.child,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    return Stack(
      fit: StackFit.expand,
      children: [
        _slot(widget, leaving: false),
        if (leaving != null) _slot(leaving, leaving: true),
      ],
    );
  }
}
