// The phone's screen going off, as the platform tells it.
//
// Whoever turns the screen back on may not be the one who turned it
// off, so the app lock does not wait out its delay for that: it comes
// up at once. Android says so when the screen goes off. iOS says
// nothing to an app it has suspended, which is every app behind by the
// time the phone locks: there the delay alone decides.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tells when the screen goes off. Behind an interface so no test ever
/// reaches the platform.
abstract class ScreenOffWatch {
  /// Calls [onScreenOff] each time the screen goes off, until [stop]
  /// is called with the same function.
  void start(void Function() onScreenOff);

  /// Stops calling [onScreenOff]. A listener started since is left
  /// alone: the gate that started it outlives the one that stops.
  void stop(void Function() onScreenOff);
}

/// The real watch: a method channel the platform calls into.
class SystemScreenOffWatch implements ScreenOffWatch {
  const SystemScreenOffWatch();

  static const MethodChannel _channel = MethodChannel('gerfaut/screen');

  /// The listener the channel answers to; one channel, so one listener.
  static void Function()? _listener;

  @override
  void start(void Function() onScreenOff) {
    _listener = onScreenOff;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'screenOff') throw MissingPluginException();
      _listener?.call();
    });
  }

  @override
  void stop(void Function() onScreenOff) {
    if (!identical(_listener, onScreenOff)) return;
    _listener = null;
    _channel.setMethodCallHandler(null);
  }
}

/// The watch in use. Widget tests override this with a fake.
final screenOffWatchProvider = Provider<ScreenOffWatch>(
  (ref) => const SystemScreenOffWatch(),
);
