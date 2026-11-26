// The credit a price source asks for beside its data ("Powered by
// CoinGecko", as the core's table words it and links it), shown by one
// mechanism for every screen, so that no screen can forget it:
//
// - whatever shows a price, or an amount a price turned into fiat,
//   marks the source of that price for its route while it is on screen
//   ([CreditMark]; [FiatText] does it for every fiat amount);
// - the app has one slot, under the navigator ([CreditFrame]), which
//   shows the credit of what is in view, once, whatever the number of
//   figures: what the route on top marked, and the route below it while
//   it leaves that one in view, undimmed, as a menu does; a route under
//   a page, or dimmed by a sheet or a dialog over it, shows none.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/lock.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';

/// What each route shows that a source priced, by the part that shows
/// it, and the routes of the navigator, bottom first.
class CreditBoard extends ChangeNotifier {
  final Map<Route<dynamic>, Map<Object, PriceSource>> _marks = {};
  final List<Route<dynamic>> _stack = [];
  bool _scheduled = false;
  bool _disposed = false;

  /// The sources of the figures in view: those of the route on top, and
  /// of each route below it that the routes above leave in view,
  /// neither covered nor dimmed.
  Set<PriceSource> get shown {
    final sources = <PriceSource>{};
    for (final route in _stack.reversed) {
      sources.addAll(_marks[route]?.values ?? const <PriceSource>[]);
      if (route is! ModalRoute ||
          route.opaque ||
          (route.barrierColor?.a ?? 0) > 0) {
        break;
      }
    }
    return sources;
  }

  void mark(Route<dynamic> route, Object by, PriceSource source) {
    final held = _marks.putIfAbsent(route, () => {});
    if (held[by] == source) return;
    held[by] = source;
    _changed();
  }

  void unmark(Route<dynamic> route, Object by) {
    final held = _marks[route];
    if (held == null || held.remove(by) == null) return;
    if (held.isEmpty) _marks.remove(route);
    _changed();
  }

  /// [route] goes just above [below], the route it was pushed over, or
  /// on top when the board does not hold that one.
  void pushed(Route<dynamic> route, Route<dynamic>? below) {
    final at = below == null ? -1 : _stack.indexOf(below);
    _stack.insert(at < 0 ? _stack.length : at + 1, route);
    _changed();
  }

  void removed(Route<dynamic> route) {
    if (_stack.remove(route)) _changed();
  }

  /// [route] takes the place of [old], or goes on top when the board
  /// does not hold [old].
  void replaced(Route<dynamic>? old, Route<dynamic>? route) {
    final at = old == null ? -1 : _stack.indexOf(old);
    if (at >= 0) _stack.removeAt(at);
    if (route != null) _stack.insert(at >= 0 ? at : _stack.length, route);
    _changed();
  }

  // Marks come and go while the tree builds: the slot hears of them
  // after the frame, once.
  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final creditBoardProvider = Provider<CreditBoard>((ref) {
  final board = CreditBoard();
  ref.onDispose(board.dispose);
  return board;
});

/// Tells the board which routes the navigator holds.
class CreditObserver extends NavigatorObserver {
  CreditObserver(this.board);

  final CreditBoard board;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      board.pushed(route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      board.removed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      board.removed(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      board.replaced(oldRoute, newRoute);
}

/// Marks, while [child] is on screen, that it shows a figure [source]
/// priced; a null [source] marks nothing.
class CreditMark extends ConsumerStatefulWidget {
  const CreditMark({super.key, required this.source, required this.child});

  final PriceSource? source;
  final Widget child;

  @override
  ConsumerState<CreditMark> createState() => _CreditMarkState();
}

class _CreditMarkState extends ConsumerState<CreditMark> {
  final Object _by = Object();
  late final CreditBoard _board;
  Route<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _board = ref.read(creditBoardProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _unmark();
      _route = route;
    }
    _mark();
  }

  @override
  void didUpdateWidget(CreditMark old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _unmark();
      _mark();
    }
  }

  void _mark() {
    final route = _route;
    final source = widget.source;
    if (route != null && source != null) _board.mark(route, _by, source);
  }

  void _unmark() {
    final route = _route;
    if (route != null) _board.unmark(route, _by);
  }

  @override
  void dispose() {
    _unmark();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The app under its one credit slot. The slot takes the bottom of the
/// window only while a route in view shows a figure whose source asks
/// for a credit, and never over the keyboard; the screens above keep
/// their own layout, the inset of the system bar moved under the slot.
///
/// It reads the core's table only once a figure is marked: it stands
/// above the bootstrap, and nothing may ask the core before the vault
/// is open.
class CreditFrame extends ConsumerWidget {
  const CreditFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(creditBoardProvider);
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) => Consumer(
        builder: (context, ref, _) {
          final shown = board.shown;
          // The lock replaces the screen a frame before its marks go:
          // the slot goes with the lock, never a frame over it.
          final locked = shown.isNotEmpty && ref.watch(lockProvider).locked;
          final table = shown.isEmpty || locked
              ? null
              : ref.watch(priceTableProvider).value;
          return _framed(context, shown, table);
        },
      ),
    );
  }

  Widget _framed(
    BuildContext context,
    Set<PriceSource> shown,
    PriceTable? table,
  ) {
    final credits = [
      for (final entry in table?.sources ?? const <SourceEntry>[])
        if (shown.contains(entry.source) && entry.credit != null) entry.credit!,
    ];
    final visible =
        credits.isNotEmpty && MediaQuery.viewInsetsOf(context).bottom == 0;
    return Column(
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: visible,
            child: child,
          ),
        ),
        if (visible) _Slot(credits: credits),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.credits});

  final List<Credit> credits;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Material(
      color: tokens.background,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.sm),
            child: Wrap(
              alignment: WrapAlignment.end,
              children: [for (final credit in credits) _CreditLink(credit)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The source's words, opening its page in the browser: 12 px, muted,
/// underlined, in a full touch target.
class _CreditLink extends StatelessWidget {
  const _CreditLink(this.credit);

  final Credit credit;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // A node of its own: above the navigator, it would otherwise lend
    // its words and its tap to the whole window.
    return Semantics(
      container: true,
      link: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.sm),
        onTap: () => launchUrl(
          Uri.parse(credit.url),
          mode: LaunchMode.externalApplication,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: GerfautTouch.target),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.sm),
            child: Align(
              widthFactor: 1,
              child: Text(
                credit.text,
                style: tokens.bodySmall.copyWith(
                  fontSize: 12,
                  color: tokens.textMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: tokens.border,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
