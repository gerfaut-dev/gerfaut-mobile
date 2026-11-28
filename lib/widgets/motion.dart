import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
class FadeInPlace extends StatefulWidget {
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
  State<FadeInPlace> createState() => _FadeInPlaceState();
}

class _FadeInPlaceState extends State<FadeInPlace> {
  /// Counts the changes of state. The child is keyed on it rather than
  /// on the state itself: a state that comes back while it is still
  /// fading out (loading, content, loading) is a new child, never a
  /// second one under the same key.
  int _change = 0;

  @override
  void didUpdateWidget(FadeInPlace old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _change++;
  }

  @override
  Widget build(BuildContext context) {
    final alignment = widget.alignment;
    return AnimatedSwitcher(
      duration: GerfautMotion.base,
      switchInCurve: GerfautMotion.ease,
      switchOutCurve: GerfautMotion.ease.flipped,
      // Every child keeps the same wrapper, leaving or not, so the one
      // that starts leaving keeps its element and its state.
      // The parent's constraints reach the child as if the fade were not
      // there: a line stretched to the width of its column stays so.
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        fit: StackFit.passthrough,
        children: [
          for (final old in previous)
            _Stage(key: old.key, leaving: true, child: old),
          if (current != null)
            _Stage(key: current.key, leaving: false, child: current),
        ],
      ),
      child: KeyedSubtree(key: ValueKey<int>(_change), child: widget.child),
    );
  }
}

/// Where a child of a fade stands. The one leaving still paints while it
/// fades out, but it is no longer what the block shows: it takes no
/// touch, is not read out a second time beside its successor, and is
/// not found as onstage content, as with [Offstage] or a hidden
/// [Overlay] entry.
class _Stage extends StatelessWidget {
  const _Stage({super.key, required this.leaving, required this.child});

  final bool leaving;
  final Widget child;

  @override
  StatelessElement createElement() => _StageElement(this);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: leaving,
    child: ExcludeSemantics(excluding: leaving, child: child),
  );
}

class _StageElement extends StatelessElement {
  _StageElement(_Stage super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    if (!(widget as _Stage).leaving) super.debugVisitOnstageChildren(visitor);
  }
}

/// Keeps the room of something no longer shown, beside what replaced it
/// in a [FadeInPlace]: it takes its size, but is not painted, not read
/// out, not hit and not found as onstage content. A button whose label
/// changes keeps the width of the wider of the two this way, so nothing
/// around it moves once the fade is over either.
class HeldPlace extends StatelessWidget {
  const HeldPlace({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: 0, child: _Stage(leaving: true, child: child));
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
class OpeningPlace extends StatefulWidget {
  const OpeningPlace({super.key, required this.child});

  final Widget? child;

  @override
  State<OpeningPlace> createState() => _OpeningPlaceState();
}

class _OpeningPlaceState extends State<OpeningPlace> {
  /// Counts the openings and closings, as [FadeInPlace] counts its
  /// changes: a note that comes back while it is still closing is a new
  /// child, never a second one under the same key.
  int _change = 0;

  @override
  void didUpdateWidget(OpeningPlace old) {
    super.didUpdateWidget(old);
    if ((old.child == null) != (widget.child == null)) _change++;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final key = ValueKey<int>(_change);
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
        // Every child keeps the same wrappers, leaving or not, so the one
        // that starts leaving keeps its element and its state.
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.topStart,
          fit: StackFit.passthrough,
          children: [
            for (final old in previous)
              _Place(
                key: old.key,
                over: true,
                child: _Stage(leaving: true, child: old),
              ),
            if (current != null)
              _Place(
                key: current.key,
                over: false,
                child: _Stage(leaving: false, child: current),
              ),
          ],
        ),
        child: child == null
            ? SizedBox.shrink(key: key)
            : KeyedSubtree(key: key, child: child),
      ),
    );
  }
}

/// Where a child of an [OpeningPlace] stands in its stack: what stays
/// holds the place and gives it its height; what leaves is laid over
/// it, across its width from the top, and no longer holds it open. One
/// widget for both, so a child that starts leaving is not rebuilt.
class _Place extends ParentDataWidget<StackParentData> {
  const _Place({super.key, required this.over, required super.child});

  final bool over;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as StackParentData;
    final edge = over ? 0.0 : null;
    if (data.top == edge && data.left == edge && data.right == edge) return;
    data
      ..top = edge
      ..left = edge
      ..right = edge;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Stack;
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

/// The tab controller of every set of tabs: a change of tab slides the
/// indicator and the pages in [GerfautMotion.base] (the platform takes
/// 300 ms on its own curve), jumps with animations reduced, and gives a
/// click when the tab changes, by a tap or a swipe.
class GerfautTabController extends StatelessWidget {
  const GerfautTabController({
    super.key,
    required this.length,
    this.initialIndex = 0,
    required this.child,
  });

  final int length;
  final int initialIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: length,
      initialIndex: initialIndex,
      animationDuration: GerfautMotion.reduced(context)
          ? Duration.zero
          : GerfautMotion.base,
      child: _TabClick(child: child),
    );
  }
}

class _TabClick extends StatefulWidget {
  const _TabClick({required this.child});

  final Widget child;

  @override
  State<_TabClick> createState() => _TabClickState();
}

class _TabClickState extends State<_TabClick> {
  TabController? _controller;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (controller == _controller) return;
    _controller?.removeListener(_changed);
    _controller = controller..addListener(_changed);
    _index = controller.index;
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final index = _controller!.index;
    if (index == _index) return;
    _index = index;
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
  // Played backwards only: the flipped curve makes the screen that
  // leaves start as briskly as anything that arrives.
  late final CurvedAnimation _eased = GerfautMotion.eased(_fade);

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
  Widget _slot(ScreenFade screen, {required bool leaving}) => _Stage(
    key: ValueKey<Object>(screen.state),
    leaving: leaving,
    child: FadeTransition(
      opacity: leaving ? _eased : kAlwaysCompleteAnimation,
      child: screen.child,
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
