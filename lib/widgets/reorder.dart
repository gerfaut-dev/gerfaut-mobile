import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Marks the copy of a list item that follows the finger while it is
/// dragged. The item reads it and paints itself as the one thing on the
/// screen that really floats: on its own surface, with the overlay
/// shadow. Nothing else changes about it, so what lands is what was
/// lifted.
///
/// A `proxyDecorator` cannot hand the item a flag, and cannot draw the
/// shadow itself without shading the gutter under the item too: the
/// item owns its margin, so the item has to own its lift.
class LiftedItem extends InheritedWidget {
  const LiftedItem({super.key, required this.lift, required super.child});

  /// How far the item has risen, 0 at rest and 1 held: its shadow
  /// follows it in and out.
  final Animation<double> lift;

  /// Whether the widget at [context] is being dragged right now.
  static bool of(BuildContext context) => liftOf(context) != null;

  /// The rise of the item at [context], null when it is not dragged.
  static Animation<double>? liftOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiftedItem>()?.lift;

  /// [shadow] scaled to the rise of the item at [context]; none at rest.
  /// Rebuilds with the rise: call it under an [AnimatedBuilder] on
  /// [liftOf].
  static List<BoxShadow>? shadowOf(Animation<double>? lift, BoxShadow shadow) {
    if (lift == null) return null;
    final eased = BoxShadow.lerp(null, shadow, lift.value);
    return eased == null ? null : [eased];
  }

  @override
  bool updateShouldNotify(LiftedItem oldWidget) => false;
}

/// The `proxyDecorator` of every reorderable list in the app.
///
/// The item rises with the drag's own animation, on [GerfautMotion.ease]:
/// its surface and shadow come in as it lifts and go as it lands, rather
/// than appearing in one frame. The lift gives a click, the only sign
/// that the long press took.
Widget liftedProxy(Widget child, int index, Animation<double> animation) {
  return _Lift(animation: animation, child: child);
}

class _Lift extends StatefulWidget {
  const _Lift({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_Lift> createState() => _LiftState();
}

class _LiftState extends State<_Lift> {
  late CurvedAnimation _eased = GerfautMotion.eased(widget.animation);

  @override
  void initState() {
    super.initState();
    HapticFeedback.selectionClick();
  }

  @override
  void didUpdateWidget(_Lift old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      _eased.dispose();
      _eased = GerfautMotion.eased(widget.animation);
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LiftedItem(lift: _eased, child: widget.child),
    );
  }
}
