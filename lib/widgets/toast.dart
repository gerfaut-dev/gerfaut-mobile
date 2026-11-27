import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How long a toast stays once it has arrived.
const Duration toastDuration = Duration(seconds: 3);

/// A benign confirmation — "Copied", "Setting saved" — gone after three
/// seconds, as on the desktop app. Never for an error or an alert: what
/// matters does not go away by itself.
///
/// An app has one toast, over every page of its navigator: shown as a
/// page closes, it stays its three seconds over the page below; shown
/// while another is up, it takes that one's place and its three seconds
/// start again, instead of waiting its turn.
class Toast {
  Toast._(this._overlay);

  static final Expando<Toast> _byOverlay = Expando('toast');

  /// The toast of the app [context] is in. Taken before an `await`, it
  /// still shows once the screen that took it is gone.
  static Toast of(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    return _byOverlay[overlay] ??= Toast._(overlay);
  }

  final OverlayState _overlay;
  final ValueNotifier<(int, String)?> _said = ValueNotifier(null);
  OverlayEntry? _entry;

  /// Shows [message], in place of the toast on screen if there is one.
  void show(String message) {
    // The app is gone: nobody is left to read it.
    if (!_overlay.mounted) return;
    _said.value = ((_said.value?.$1 ?? 0) + 1, message);
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => _ToastLayer(said: _said));
      _overlay.insert(_entry!);
    }
  }
}

/// Keeps every toast off what it covers while [open] is false: the app
/// puts it above its navigator, closed while the lock (or the calculator
/// standing for it) is the screen, so no "Copied" is ever drawn over it.
/// A toast on screen when it closes goes at once, and none shows until
/// it opens again.
class ToastGate extends InheritedWidget {
  const ToastGate({super.key, required this.open, required super.child});

  final bool open;

  /// Open where no gate says otherwise.
  static bool openOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToastGate>()?.open ?? true;

  @override
  bool updateShouldNotify(ToastGate oldWidget) => open != oldWidget.open;
}

/// What a toast looks like: an island of the dark theme in either theme,
/// as on the desktop app — night ground, foam text. On a light page it
/// stands out by itself. In the dark theme its ground is the page's own,
/// so there, and only there, the theme's hairline gives it an edge.
class ToastView extends StatelessWidget {
  const ToastView(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<GerfautTokens>()!;
    return Material(
      color: GerfautTokens.dark.background,
      elevation: _elevation,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        side: theme.brightness == Brightness.dark
            ? BorderSide(color: tokens.border)
            : BorderSide.none,
      ),
      child: Padding(
        padding: _padding,
        child: DefaultTextStyle(
          style: GerfautTokens.dark.bodySmall,
          child: Text(message),
        ),
      ),
    );
  }

  /// Lifted off the page as the platform's floating surfaces are.
  static const double _elevation = 6;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );
}

/// Around the toast, off the edges of the page and above whatever sits
/// at its foot.
const EdgeInsets _margin = EdgeInsets.fromLTRB(15, 5, 15, 10);

/// The toast of one navigator, at the foot of its pages, above the
/// keyboard when there is one.
class _ToastLayer extends StatefulWidget {
  const _ToastLayer({required this.said});

  final ValueListenable<(int, String)?> said;

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer>
    with SingleTickerProviderStateMixin {
  // It arrives in slow and leaves in base, both on ease: what leaves
  // starts as briskly as what arrives.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GerfautMotion.slow,
    reverseDuration: GerfautMotion.base,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _eased = GerfautMotion.eased(_controller);

  /// The toast on screen, and the count that tells two of the same
  /// words apart.
  (int, String)? _shown;
  Timer? _timer;
  bool? _open;

  @override
  void initState() {
    super.initState();
    widget.said.addListener(_onSaid);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _open == null;
    _open = ToastGate.openOf(context);
    if (_open == false) {
      _drop();
    } else if (first) {
      // The words that brought this layer in.
      _take(widget.said.value);
    }
  }

  @override
  void dispose() {
    widget.said.removeListener(_onSaid);
    _timer?.cancel();
    _eased.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onSaid() => setState(() => _take(widget.said.value));

  void _take((int, String)? said) {
    if (said == null || _open != true) return;
    _shown = said;
    _stopClock();
    // Already up, it only changes its words, and its time starts again.
    if (_controller.isCompleted) {
      _startClock();
    } else {
      _controller.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    // Its time starts once it has landed.
    if (status.isCompleted) _startClock();
    if (status.isDismissed) setState(() => _shown = null);
  }

  void _startClock() =>
      _timer = Timer(toastDuration, () => _controller.reverse());

  void _stopClock() {
    _timer?.cancel();
    _timer = null;
  }

  /// Gone at once: swiped away, dismissed by a screen reader, or the
  /// lock is up.
  void _drop() {
    _stopClock();
    _shown = null;
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    // Where a floating snack bar sits: on the keyboard when it is up,
    // otherwise above the system's gesture bar.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final foot = keyboard > 0
        ? keyboard
        : MediaQuery.viewPaddingOf(context).bottom;
    // With animations reduced it only fades, in place.
    final rise = GerfautMotion.reduced(context) ? 0.0 : GerfautMotion.rise;
    // While it leaves, its words are already gone for a screen reader,
    // and a touch goes through to the page.
    final leaving = _controller.status == AnimationStatus.reverse;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: foot),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: _margin,
            child: AnimatedBuilder(
              animation: _eased,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, rise * (1 - _eased.value)),
                child: child,
              ),
              child: FadeTransition(
                opacity: _eased,
                child: IgnorePointer(
                  ignoring: leaving,
                  child: ExcludeSemantics(
                    excluding: leaving,
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      onDismiss: () => setState(_drop),
                      child: Dismissible(
                        key: ValueKey(shown.$1),
                        direction: DismissDirection.down,
                        resizeDuration: null,
                        onDismissed: (_) => setState(_drop),
                        child: SizedBox(
                          width: double.infinity,
                          child: ToastView(shown.$2),
                        ),
                      ),
                    ),
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
