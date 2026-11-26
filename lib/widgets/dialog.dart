import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shows a modal the way every modal of Gerfaut arrives: it fades in
/// and rises a few pixels onto the page it dims. A modal has no origin
/// on screen, and the movement gives it one; a panel hung under its own
/// button already has one, and only fades.
///
/// In place of [showDialog], whose fade alone leaves a modal appearing
/// from nowhere. Same contract otherwise: the root navigator, the back
/// gesture and a touch outside close it.
Future<T?> showGerfautDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? barrierLabel,
}) {
  final tokens = Theme.of(context).extension<GerfautTokens>()!;
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return Navigator.of(context, rootNavigator: true).push<T>(
    _GerfautDialogRoute<T>(
      barrierDismissible: true,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: tokens.scrim,
      transitionDuration: GerfautMotion.slow,
      pageBuilder: (context, _, _) =>
          themes.wrap(SafeArea(child: Builder(builder: builder))),
      transitionBuilder: (context, animation, _, child) =>
          _DialogTransition(animation: animation, child: child),
    ),
  );
}

/// A modal leaves faster than it arrives: by then it has been read.
class _GerfautDialogRoute<T> extends RawDialogRoute<T> {
  _GerfautDialogRoute({
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.barrierColor,
    required super.transitionDuration,
    required super.transitionBuilder,
  });

  @override
  Duration get reverseTransitionDuration => GerfautMotion.fast;
}

class _DialogTransition extends StatefulWidget {
  const _DialogTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_DialogTransition> createState() => _DialogTransitionState();
}

class _DialogTransitionState extends State<_DialogTransition> {
  late CurvedAnimation _eased = GerfautMotion.eased(widget.animation);

  @override
  void didUpdateWidget(_DialogTransition old) {
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
    // With animations reduced the modal keeps its fade and stays put.
    final rise = MediaQuery.disableAnimationsOf(context) ? 0.0 : _rise;
    return AnimatedBuilder(
      animation: _eased,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (1 - _eased.value) * rise),
        child: child,
      ),
      child: FadeTransition(opacity: _eased, child: widget.child),
    );
  }
}

/// How far a modal rises as it arrives, in logical pixels.
const double _rise = GerfautSpacing.sm;
