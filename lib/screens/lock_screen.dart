import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/lock.dart';
import '../src/models.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/buttons.dart';
import '../widgets/pin_pad.dart';
import '../widgets/pinned_action_form.dart';
import '../widgets/readable_width.dart';

/// The screen that stands in front of everything while the app is
/// locked. Nothing of the wallet is behind it: it replaces the app,
/// it does not cover it.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  /// The password, typed in its field.
  final _controller = TextEditingController();

  /// The PIN, typed on the pad: never in a text field, so the phone's
  /// keyboard never sees it.
  String _pin = '';

  /// Where the digits of the pad stand, drawn anew each time the
  /// screen opens and after each PIN refused.
  late List<int> _shuffled;
  late final Random _random;

  bool _hidden = true;
  bool _checking = false;
  String? _message;

  /// Seconds left before the core will even look at a secret again.
  int _wait = 0;

  /// The wait as it was when it began: what a screen reader is told.
  int _waitFrom = 0;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _random = ref.read(pinPadRandomProvider);
    _shuffled = shuffledDigits(_random);
    // A phone that unlocks by face should not make the user reach for
    // the keyboard first: the prompt comes up on its own.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// The offer is made once the phone has said it can answer; until
  /// then the secret is the way in, which it always is.
  bool get _offersBiometrics {
    final lock = ref.watch(lockProvider);
    return (lock.lock?.biometric ?? false) &&
        lock.biometricLapse == null &&
        ref.watch(biometricSupportProvider).value == BiometricSupport.strong;
  }

  Future<void> _tryBiometrics() async {
    final lock = ref.read(lockProvider);
    if (!(lock.lock?.biometric ?? false) || lock.biometricLapse != null) {
      return;
    }
    // Awaited, not read: the sensor answers a moment after the screen
    // is up, and the prompt is worth waiting for. A phone left with a
    // weak biometric only is not asked: it cannot answer.
    final support = await ref.read(biometricSupportProvider.future);
    if (support != BiometricSupport.strong || !mounted) return;
    await ref.read(lockProvider.notifier).unlockWithBiometrics();
    // A refusal says nothing: the secret field is right there.
  }

  void _startCountdown(int seconds) {
    _countdown?.cancel();
    setState(() {
      _wait = seconds;
      _waitFrom = seconds;
    });
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _wait -= 1);
      if (_wait <= 0) {
        timer.cancel();
        // Said once the wait is over, as its start was: a screen reader
        // hears the two ends, not every second in between.
        setState(() => _message = 'You can try again.');
      }
    });
  }

  bool get _pinLock =>
      (ref.read(lockProvider).lock?.kind ?? LockKind.pin) == LockKind.pin;

  /// What is typed, on the pad or in the field.
  String get _secret => _pinLock ? _pin : _controller.text;

  /// The pad answers nothing while a secret is checked or the core
  /// makes the user wait.
  bool get _padOpen => !_checking && _wait <= 0;

  void _digit(int digit) {
    if (!_padOpen || _pin.length >= pinMaxLength) return;
    setState(() {
      _pin += '$digit';
      _message = null;
    });
  }

  void _delete() {
    if (!_padOpen || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _clear() {
    if (!_padOpen || _pin.isEmpty) return;
    setState(() => _pin = '');
  }

  /// A keyboard plugged in, or the emulator's, types on the pad too:
  /// digits, the delete key, Enter.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    // Enter on a focused button is that button's own: only the pad,
    // focused itself, takes it as Unlock.
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        node.hasPrimaryFocus) {
      if (event is KeyDownEvent) _unlock();
      return KeyEventResult.handled;
    }
    final digit = _digitKeys[key] ?? int.tryParse(event.character ?? '');
    if (digit == null || digit < 0 || digit > 9) {
      return KeyEventResult.ignored;
    }
    _digit(digit);
    return KeyEventResult.handled;
  }

  Future<void> _unlock() async {
    final secret = _secret;
    if (_checking || _wait > 0 || secret.isEmpty) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final verdict = await ref.read(lockProvider.notifier).unlock(secret);
      if (!mounted || verdict.unlocked) return;
      final kind = ref.read(lockProvider).lock?.kind ?? LockKind.pin;
      setState(() {
        _controller.clear();
        _pin = '';
        // Someone who watched where the finger went learns nothing
        // they can use on the next try.
        _shuffled = shuffledDigits(_random);
        _message = verdict.retryAfterSecs > 0
            ? null
            : 'Wrong ${kind == LockKind.pin ? 'PIN' : 'password'}';
      });
      if (verdict.retryAfterSecs > 0) _startCountdown(verdict.retryAfterSecs);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // The owner left, or the screen went off: what they had typed goes
    // with them, and the next person meets the keypad in a new order.
    ref.listen(lockDeparturesProvider, (_, _) {
      setState(() {
        _pin = '';
        _controller.clear();
        _shuffled = shuffledDigits(_random);
      });
    });
    final kind = ref.watch(lockProvider).lock?.kind ?? LockKind.pin;
    final pin = kind == LockKind.pin;
    final blocked = _wait > 0;
    final secret = pin ? 'PIN' : 'password';
    final note = blocked
        ? 'Too many attempts. Try again in $_wait s'
        : _message ??
              switch (ref.watch(lockProvider).biometricLapse) {
                BiometricLapse.changed =>
                  'The fingerprints or faces on this phone changed. Unlock '
                      'with your $secret, then turn biometrics on again in '
                      'Settings.',
                // A vault from before keys: nothing changed on the
                // phone, there is only a step to take again.
                BiometricLapse.missing =>
                  'Unlock with your $secret, then turn biometrics on again '
                      'in Settings.',
                null => null,
              };

    final action = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_offersBiometrics) ...[
          SecondaryButton(
            label: 'Use fingerprint or face',
            icon: LucideIcons.fingerprint,
            expand: true,
            onPressed: _tryBiometrics,
          ),
          const SizedBox(height: GerfautSpacing.sm),
        ],
        PrimaryButton(
          label: _checking ? 'Unlocking…' : 'Unlock',
          expand: true,
          busy: _checking,
          onPressed: blocked ? null : _unlock,
        ),
      ],
    );
    final head = [
      const SizedBox(height: GerfautSpacing.xl),
      Center(
        child: GerfautMark(
          color: tokens.primary,
          height: 40,
          semanticLabel: 'Gerfaut',
        ),
      ),
      const SizedBox(height: GerfautSpacing.lg),
      Center(child: Text('Locked', style: tokens.h2)),
      const SizedBox(height: GerfautSpacing.lg),
    ];
    final noteLine = note == null
        ? null
        // A refused secret is a fact, not an alarm: Alerte is kept for
        // coins moving. Said aloud as it appears; the countdown is said
        // once, with the wait it began at, and the field or the keys
        // greyed meanwhile say the rest.
        : Semantics(
            liveRegion: true,
            label: blocked
                ? 'Too many attempts. Try again in $_waitFrom seconds.'
                : null,
            excludeSemantics: blocked,
            child: Text(
              note,
              textAlign: pin ? TextAlign.center : TextAlign.start,
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          );

    return Scaffold(
      body: SafeArea(
        child: ReadableWidth(
          child: Padding(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            child: pin
                ? _pinForm(head: head, note: noteLine, action: action)
                : _passwordForm(head: head, note: noteLine, action: action),
          ),
        ),
      ),
    );
  }

  /// The PIN: dots, the pad, and the action pinned under them. With
  /// room, the pad takes what is left, up to its full height; without,
  /// a phone on its side or a large text size, every key is as small as
  /// a key may be and the pad scrolls above the action, which stays.
  Widget _pinForm({
    required List<Widget> head,
    required Widget? note,
    required Widget action,
  }) {
    // A screen reader says each digit as the finger finds it: the
    // shuffle hides nothing then, and makes the pad hard to walk.
    final shuffle =
        ref.watch(lockShuffleProvider) &&
        !MediaQuery.accessibleNavigationOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...head,
                        PinDots(count: _pin.length),
                        if (note != null) ...[
                          const SizedBox(height: GerfautSpacing.sm),
                          note,
                        ],
                        const SizedBox(height: GerfautSpacing.lg),
                        Expanded(
                          child: PinPad(
                            order: shuffle ? _shuffled : phoneOrder,
                            enabled: _wait <= 0,
                            onDigit: _digit,
                            onDelete: _delete,
                            onClear: _clear,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: GerfautSpacing.lg),
          action,
        ],
      ),
    );
  }

  /// The password: its field, with the phone's keyboard.
  Widget _passwordForm({
    required List<Widget> head,
    required Widget? note,
    required Widget action,
  }) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return PinnedActionForm(
      action: action,
      children: [
        ...head,
        Semantics(
          // The hint goes as soon as a character is typed: the name
          // stays.
          label: 'Password',
          child: TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _hidden,
            enabled: _wait <= 0,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.text,
            style: tokens.body,
            onChanged: (_) => setState(() => _message = null),
            onSubmitted: (_) => _unlock(),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: tokens.body.copyWith(color: tokens.textMuted),
              filled: true,
              fillColor: tokens.surfaceSunken,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: GerfautSpacing.md,
                vertical: GerfautSpacing.sm + GerfautSpacing.xs,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GerfautRadius.sm),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GerfautRadius.sm),
                borderSide: BorderSide(color: tokens.primary, width: 2),
              ),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden ? LucideIcons.eye : LucideIcons.eyeOff,
                  size: 20,
                  color: tokens.textMuted,
                ),
              ),
            ),
          ),
        ),
        if (note != null) ...[const SizedBox(height: GerfautSpacing.sm), note],
      ],
    );
  }
}

/// The keys of a keyboard that type a digit, the number row and the
/// numeric pad alike.
final Map<LogicalKeyboardKey, int> _digitKeys = {
  LogicalKeyboardKey.digit0: 0,
  LogicalKeyboardKey.digit1: 1,
  LogicalKeyboardKey.digit2: 2,
  LogicalKeyboardKey.digit3: 3,
  LogicalKeyboardKey.digit4: 4,
  LogicalKeyboardKey.digit5: 5,
  LogicalKeyboardKey.digit6: 6,
  LogicalKeyboardKey.digit7: 7,
  LogicalKeyboardKey.digit8: 8,
  LogicalKeyboardKey.digit9: 9,
  LogicalKeyboardKey.numpad0: 0,
  LogicalKeyboardKey.numpad1: 1,
  LogicalKeyboardKey.numpad2: 2,
  LogicalKeyboardKey.numpad3: 3,
  LogicalKeyboardKey.numpad4: 4,
  LogicalKeyboardKey.numpad5: 5,
  LogicalKeyboardKey.numpad6: 6,
  LogicalKeyboardKey.numpad7: 7,
  LogicalKeyboardKey.numpad8: 8,
  LogicalKeyboardKey.numpad9: 9,
};
