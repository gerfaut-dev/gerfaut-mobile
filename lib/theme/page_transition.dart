import 'package:flutter/material.dart';

import 'tokens.dart';

/// How a page arrives where the platform has no gesture of its own to
/// keep: it fades in over the one it covers and settles from a short
/// way to the side, while the covered page gives half that way.
///
/// The platform's own transition takes close to half a second, and a
/// whole screen travelling that long is the slowest thing in the app.
/// This one keeps to [GerfautMotion.slow], on [GerfautMotion.ease], and
/// leaves by the same road. With animations reduced, only the fade is
/// left.
class GerfautPageTransitionsBuilder extends PageTransitionsBuilder {
  const GerfautPageTransitionsBuilder();

  /// How far the arriving page travels, in logical pixels.
  static const double travel = GerfautMotion.travel;

  @override
  Duration get transitionDuration => GerfautMotion.slow;

  @override
  Duration get reverseTransitionDuration => GerfautMotion.base;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _PageTransition extends StatefulWidget {
  const _PageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// The page arriving, or leaving on the way back.
  final Animation<double> animation;

  /// Another page arriving over this one.
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_PageTransition> createState() => _PageTransitionState();
}

class _PageTransitionState extends State<_PageTransition> {
  late CurvedAnimation _arriving = GerfautMotion.eased(widget.animation);
  late CurvedAnimation _fade = _fadeOf(widget.animation);

  late CurvedAnimation _covered = GerfautMotion.eased(
    widget.secondaryAnimation,
  );

  /// The fade is over by the middle of the way in, and the page is
  /// gone by the middle of the way out: a whole page under an opacity
  /// is the costly part of the transition, and half of its frames do
  /// without it.
  static CurvedAnimation _fadeOf(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: const Interval(0, GerfautMotion.pageFade, curve: GerfautMotion.ease),
    reverseCurve: Interval(
      1 - GerfautMotion.pageFade,
      1,
      curve: GerfautMotion.ease.flipped,
    ),
  );

  @override
  void didUpdateWidget(_PageTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      _arriving.dispose();
      _arriving = GerfautMotion.eased(widget.animation);
      _fade.dispose();
      _fade = _fadeOf(widget.animation);
    }
    if (old.secondaryAnimation != widget.secondaryAnimation) {
      _covered.dispose();
      _covered = GerfautMotion.eased(widget.secondaryAnimation);
    }
  }

  @override
  void dispose() {
    _arriving.dispose();
    _fade.dispose();
    _covered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With animations reduced the page keeps its fade and stays put.
    final travel = GerfautMotion.reduced(context)
        ? 0.0
        : GerfautPageTransitionsBuilder.travel;
    final side = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return AnimatedBuilder(
      animation: Listenable.merge([_arriving, _covered]),
      builder: (context, child) => Transform.translate(
        offset: Offset(
          side * ((1 - _arriving.value) * travel - _covered.value * travel / 2),
          0,
        ),
        child: child,
      ),
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}
