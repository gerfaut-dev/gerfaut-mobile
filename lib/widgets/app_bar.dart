import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The one header of the app.
///
/// A page with a back arrow puts its title against the arrow: what the
/// title gives up on the left, the actions take on the right. A root
/// page, which has no arrow, opens at the page margin like its own
/// content does.
///
/// Material's default adds 16px after the leading whatever the page is,
/// which is what made the wallet screen — the only one that corrected
/// it by hand — sit differently from Settings, Add a wallet and
/// Broadcast. The rule lives here now so no screen can drift again.
///
/// The bar is the colour of the page, so at rest nothing separates the
/// two. Once the page has scrolled under it, a hairline does: what
/// slides behind the title is then cut by an edge rather than by
/// nothing.
class GerfautAppBar extends StatefulWidget implements PreferredSizeWidget {
  const GerfautAppBar({
    super.key,
    required this.title,
    this.actions,
    this.titleNamesItself = false,
  });

  /// Usually a [Text]; the wallet screen makes it the wallet's icon and
  /// name, two targets that change the one and the other.
  final Widget title;
  final List<Widget>? actions;

  /// The title marks its own heading, the one that names the page. A
  /// title of two targets has to: the bar's heading around both would
  /// carry neither label, and the page would open unnamed.
  final bool titleNamesItself;

  /// A plain titled header, the common case.
  factory GerfautAppBar.text(String title, {List<Widget>? actions}) {
    return GerfautAppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<GerfautAppBar> createState() => _GerfautAppBarState();
}

class _GerfautAppBarState extends State<GerfautAppBar> {
  ScrollNotificationObserverState? _observer;

  /// The page's own scroll view has moved off its top.
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  /// The page's vertical scroll view only, as [AppBar] itself listens:
  /// a list inside a tab or a card scrolls under its own header, not
  /// under this one.
  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return;
    if (notification.depth != 0) return;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return;
    final under = metrics.extentBefore > 0;
    if (under != _scrolledUnder) setState(() => _scrolledUnder = under);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // `ModalRoute.canPop` is what AppBar itself asks before drawing a
    // back arrow, so the two never disagree.
    final hasBack = ModalRoute.of(context)?.canPop ?? false;
    return AppBar(
      titleSpacing: hasBack ? 0 : GerfautSpacing.md,
      title: widget.title,
      excludeHeaderSemantics: widget.titleNamesItself,
      actions: widget.actions,
      // The bar's Material moves from one shape to the other on its
      // own, in the time of any change of state.
      shape: Border(
        bottom: BorderSide(
          color: _scrolledUnder
              ? tokens.border
              : tokens.border.withValues(alpha: 0),
        ),
      ),
    );
  }
}
