import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/lock_screen.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/settings/security_section.dart';
import 'package:gerfaut/screens/welcome.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/platform_features.dart';
import 'package:gerfaut/src/prefs.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/screen_off.dart';
import 'package:gerfaut/src/updates.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/pin_pad.dart';
import 'package:gerfaut/widgets/setting_switch.dart';
import 'package:gerfaut/widgets/toast.dart';

import 'fakes.dart';
import 'menu.dart';

const AppLock pinLock = AppLock(kind: LockKind.pin, biometric: false);

FakeBridge locked({
  AppLock lock = pinLock,
  String secret = '1234',
  List<WalletMeta> wallets = const [],
}) {
  return FakeBridge(
      wallets: wallets,
      settings: const Settings(
        preferences: kPreferences,
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'onboarding.seen': '1'},
      ),
    )
    ..lock = lock
    ..lockSecret = secret;
}

/// Every test substitutes the sensor: a widget test must never reach
/// the platform, which under a test binding simply never answers.
List<Override> _overrides(
  FakeBridge bridge,
  FakeBiometrics? biometrics, {
  FakeWindowGuard? guard,
  FakeScreenOffWatch? screen,
  Random? random,
}) => [
  bridgeProvider.overrideWithValue(bridge),
  biometricGateProvider.overrideWithValue(
    biometrics ?? FakeBiometrics(available: false),
  ),
  windowGuardProvider.overrideWithValue(guard ?? FakeWindowGuard()),
  // Not disguised: these tests are about the plain lock screen.
  disguiseServiceProvider.overrideWithValue(FakeDisguise()),
  screenOffWatchProvider.overrideWithValue(screen ?? FakeScreenOffWatch()),
  if (random != null) pinPadRandomProvider.overrideWithValue(random),
];

Widget app(
  FakeBridge bridge, {
  FakeBiometrics? biometrics,
  FakeWindowGuard? guard,
  FakeScreenOffWatch? screen,
  Random? random,
}) {
  return ProviderScope(
    retry: noRetry,
    overrides: _overrides(
      bridge,
      biometrics,
      guard: guard,
      screen: screen,
      random: random,
    ),
    child: const GerfautApp(),
  );
}

/// Sends a lifecycle state the way the platform does, so the test
/// walks the states the framework really synthesizes in between — the
/// hidden state lands on the way back in as well as on the way out.
Future<void> sendLifecycle(WidgetTester tester, AppLifecycleState state) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage('$state'),
    (_) {},
  );
}

/// The lock as the vault hands it over: a PIN is set, so the screen
/// is up and the test unlocks it the way the user would.
///
/// Locking at once unless [delay] says otherwise: most tests here are
/// about which trips count as leaving, not about how long one lasts.
({ProviderContainer container, LockController lock}) lockedApp({
  LockDelay delay = LockDelay.immediately,
}) {
  final container = ProviderContainer(
    retry: noRetry,
    overrides: _overrides(locked(), null),
  );
  addTearDown(container.dispose);
  container.read(lockDelayProvider.notifier).hydrate('${delay.seconds}');
  final lock = container.read(lockProvider.notifier);
  lock.syncFromSettings(pinLock);
  return (container: container, lock: lock);
}

/// Pumps the whole app on a container the test keeps hold of, and
/// walks past the lock screen the way the user does. The delay is the
/// one stored, at once unless [delay] says otherwise.
Future<ProviderContainer> pumpUnlocked(
  WidgetTester tester, {
  String? delay = '0',
  FakeScreenOffWatch? screen,
}) async {
  final bridge = locked(wallets: [makeMeta()]);
  if (delay != null) bridge.appPrefs[Pref.lockDelay] = delay;
  final container = ProviderContainer(
    retry: noRetry,
    overrides: _overrides(bridge, null, screen: screen),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const GerfautApp()),
  );
  await tester.pumpAndSettle();
  await unlockWithPin(tester, '1234');
  return container;
}

/// The digits of the lock screen's pad, row by row as drawn.
List<int> padOrder(WidgetTester tester) {
  final keys =
      [
        for (var digit = 0; digit < 10; digit++)
          (digit: digit, at: tester.getCenter(find.byKey(Key('pin.$digit')))),
      ]..sort(
        (a, b) => a.at.dy != b.at.dy
            ? a.at.dy.compareTo(b.at.dy)
            : a.at.dx.compareTo(b.at.dx),
      );
  return [for (final key in keys) key.digit];
}

/// What the row of dots says to a screen reader.
String? dotsSaid(WidgetTester tester) =>
    tester.getSemantics(find.byType(PinDots)).label;

Widget settingsApp(
  FakeBridge bridge, {
  FakeBiometrics? biometrics,
  SettingsSection section = SettingsSection.security,
}) {
  return ProviderScope(
    retry: noRetry,
    overrides: _overrides(bridge, biometrics),
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: SettingsScreen(section: section),
    ),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the lock screen', () {
    testWidgets('a vault with a lock opens locked, and nothing is behind it', (
      tester,
    ) async {
      await tester.pumpWidget(app(locked(wallets: [makeMeta()])));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      // Not a wallet in the tree: the lock replaces the app.
      expect(find.text('Cold storage'), findsNothing);
    });

    testWidgets('no toast is ever drawn over the lock', (tester) async {
      await tester.pumpWidget(app(locked(wallets: [makeMeta()])));
      await tester.pumpAndSettle();

      // A save that finishes behind the lock still says so.
      Toast.of(tester.element(find.byType(LockScreen))).show('Setting saved');
      await tester.pump();
      await tester.pump(GerfautMotion.slow);
      expect(find.text('Setting saved'), findsNothing);
      expect(find.byType(ToastView), findsNothing);
    });

    testWidgets('a wrong PIN is said plainly and the screen stays', (
      tester,
    ) async {
      final bridge = locked();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();
      // The PIN goes through the app's own pad: no field, so the
      // phone's keyboard, maybe a third party's, never sees it.
      expect(find.byType(TextField), findsNothing);

      await unlockWithPin(tester, '9999');

      expect(find.text('Wrong PIN'), findsOneWidget);
      // The refused digits stay as dots in the alert colour until the
      // next key, with no shake.
      final dots = tester.widget<PinDots>(find.byType(PinDots));
      expect((dots.count, dots.refused), (4, true));
      expect(find.byType(LockScreen), findsOneWidget);
    });

    testWidgets('the right PIN opens the app', (tester) async {
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();

      await unlockWithPin(tester, '1234');

      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('No wallets yet'), findsOneWidget);
    });

    testWidgets('past three failures the wait is counted down', (tester) async {
      final bridge = locked();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      for (var attempt = 0; attempt < 3; attempt++) {
        await unlockWithPin(tester, '0000');
      }

      expect(find.text('Too many attempts. Try again in 5 s'), findsOneWidget);
      // The keys answer nothing while the core makes the user wait.
      expect(tester.widget<PinPad>(find.byType(PinPad)).enabled, isFalse);
      for (final digit in ['1', '2']) {
        await tester.tap(find.byKey(Key('pin.$digit')), warnIfMissed: false);
      }
      await tester.pump();
      // No digit went in: the refused dots are still the ones shown.
      expect(tester.widget<PinDots>(find.byType(PinDots)).refused, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many attempts. Try again in 4 s'), findsOneWidget);
      // A screen reader hears the wait it began at, not every second.
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Too many attempts. Try again in 5 seconds.'),
        findsOneWidget,
      );
      // Let the countdown finish so no timer outlives the test: the end
      // is said as the start was.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('You can try again.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a PIN takes digits only, from a keyboard too', (tester) async {
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();

      // A keyboard plugged in types on the pad: digits land, letters
      // do not, and Enter sends.
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.digit4,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      expect(find.text('Enter your PIN'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('the pad says how many digits are in, and each key its own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();
      expect(dotsSaid(tester), 'PIN, no digits entered');

      await typePin(tester, '12');
      expect(dotsSaid(tester), 'PIN, 2 digits entered');
      // Each key is a button named by its digit, wherever it stands.
      expect(
        tester.getSemantics(find.byKey(const Key('pin.7'))),
        isSemantics(label: '7', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('pin.delete'))),
        isSemantics(
          label: 'Delete',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a phone that confirms opens the app without the secret', (
      tester,
    ) async {
      final biometrics = FakeBiometrics();
      await tester.pumpWidget(
        app(
          locked(lock: const AppLock(kind: LockKind.pin, biometric: true)),
          biometrics: biometrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(biometrics.prompts, 1);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('a refused prompt leaves the secret field', (tester) async {
      final biometrics = FakeBiometrics(passes: false);
      await tester.pumpWidget(
        app(
          locked(lock: const AppLock(kind: LockKind.pin, biometric: true)),
          biometrics: biometrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Use fingerprint or face'), findsOneWidget);
    });
    testWidgets('a phone with a weak biometric only is never prompted', (
      tester,
    ) async {
      final biometrics = FakeBiometrics(offers: BiometricSupport.weakOnly);
      await tester.pumpWidget(
        app(
          locked(lock: const AppLock(kind: LockKind.pin, biometric: true)),
          biometrics: biometrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(biometrics.prompts, 0);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Use fingerprint or face'), findsNothing);
    });

    testWidgets('a vault from before keys asks nothing of the phone', (
      tester,
    ) async {
      final biometrics = FakeBiometrics(outcome: BiometricOutcome.missing)
        ..keyed = KeyPresence.absent;
      final bridge = locked(
        lock: const AppLock(kind: LockKind.pin, biometric: true),
      );
      await tester.pumpWidget(app(bridge, biometrics: biometrics));
      await tester.pumpAndSettle();

      // No alarm: nothing changed on the phone.
      expect(find.textContaining('changed'), findsNothing);
      expect(
        find.text(
          'Unlock with your PIN, then turn biometrics on again in Settings.',
        ),
        findsOneWidget,
      );
      expect(find.text('Use fingerprint or face'), findsNothing);

      await unlockWithPin(tester, '1234');
      expect(find.byType(LockScreen), findsNothing);
      expect(bridge.lock?.biometric, isFalse);
    });

    testWidgets('no strong biometric, said at two launches, turns it off', (
      tester,
    ) async {
      for (final lack in [BiometricSupport.weakOnly, BiometricSupport.none]) {
        final bridge = locked(
          lock: const AppLock(kind: LockKind.pin, biometric: true),
        );
        Future<void> launchAndUnlock(String launch) async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            app(bridge, biometrics: FakeBiometrics(offers: lack)),
          );
          await tester.pumpAndSettle();
          ProviderScope.containerOf(tester.element(find.byType(LockScreen)))
                  .read(lockProvider.notifier)
                  .launch =
              launch;
          await unlockWithPin(tester, '1234');
          expect(find.byType(LockScreen), findsNothing);
        }

        // Once: a sensor that says so for a moment turns nothing off.
        await launchAndUnlock('first');
        expect(bridge.lock?.biometric, isTrue, reason: '$lack');
        // The same launch again proves nothing more.
        await launchAndUnlock('first');
        expect(bridge.lock?.biometric, isTrue, reason: '$lack');
        // Another launch, the same answer: it is so for good.
        await launchAndUnlock('second');
        expect(bridge.lock?.biometric, isFalse, reason: '$lack');
        expect(bridge.appPrefs[Pref.biometricLack], isEmpty);
      }
    });

    testWidgets('a strong biometric seen again forgets a passing lack', (
      tester,
    ) async {
      final bridge = locked(
        lock: const AppLock(kind: LockKind.pin, biometric: true),
      )..appPrefs[Pref.biometricLack] = 'earlier';
      await tester.pumpWidget(
        app(bridge, biometrics: FakeBiometrics(passes: false)),
      );
      await tester.pumpAndSettle();
      await unlockWithPin(tester, '1234');

      expect(bridge.lock?.biometric, isTrue);
      expect(bridge.appPrefs[Pref.biometricLack], isEmpty);
    });

    testWidgets('biometrics that still open stay on after the secret', (
      tester,
    ) async {
      for (final biometrics in [
        // A strong biometric with its key: nothing lapsed.
        FakeBiometrics(passes: false),
        // A sensor that cannot answer for now: no reason to turn
        // anything off.
        FakeBiometrics(offers: BiometricSupport.unavailable),
        // A Keystore that could not be read: no proof the key is gone.
        FakeBiometrics(passes: false)..keyed = KeyPresence.unknown,
      ]) {
        final bridge = locked(
          lock: const AppLock(kind: LockKind.pin, biometric: true),
        );
        await tester.pumpWidget(app(bridge, biometrics: biometrics));
        await tester.pumpAndSettle();
        await unlockWithPin(tester, '1234');

        expect(find.byType(LockScreen), findsNothing);
        expect(bridge.lock?.biometric, isTrue);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('biometrics that changed ask for the secret, then go off', (
      tester,
    ) async {
      final biometrics = FakeBiometrics(outcome: BiometricOutcome.reset);
      final bridge = locked(
        lock: const AppLock(kind: LockKind.pin, biometric: true),
      );
      await tester.pumpWidget(app(bridge, biometrics: biometrics));
      await tester.pumpAndSettle();

      expect(biometrics.prompts, 1);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.textContaining('on this phone changed'), findsOneWidget);
      // Nothing more to try by the sensor: the key it opened is gone.
      expect(find.text('Use fingerprint or face'), findsNothing);

      await unlockWithPin(tester, '1234');
      expect(find.byType(LockScreen), findsNothing);
      // Off in the vault, for the user to turn on again with a new key.
      expect(bridge.lockCalls, contains('biometric:false'));
      expect(bridge.lock?.biometric, isFalse);
    });
  });

  group('the security card', () {
    testWidgets('turning the lock on asks twice and stores the kind', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(SecuritySection),
              matching: find.byType(GerfautSwitch),
            )
            // The app lock is the first switch of the card; the disguise
            // switch sits below it once a lock stands.
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn on the app lock'), findsOneWidget);
      expectKeyboardKeepsNothing(tester);
      await tester.enterText(find.byKey(const Key('lock.secret')), '1234');
      await tester.enterText(find.byKey(const Key('lock.confirm')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(bridge.lockCalls, contains('set:pin'));
      expect(bridge.lock?.kind, LockKind.pin);
    });

    testWidgets('a mismatch never reaches the core', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(SecuritySection),
              matching: find.byType(GerfautSwitch),
            )
            // The app lock is the first switch of the card; the disguise
            // switch sits below it once a lock stands.
            .first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.secret')), '1234');
      await tester.enterText(find.byKey(const Key('lock.confirm')), '4321');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.text('The two entries differ.'), findsOneWidget);
      expect(bridge.lockCalls, isEmpty);
    });

    testWidgets('a PIN shorter than four digits is refused on the spot', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(SecuritySection),
              matching: find.byType(GerfautSwitch),
            )
            // The app lock is the first switch of the card; the disguise
            // switch sits below it once a lock stands.
            .first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.secret')), '12');
      await tester.enterText(find.byKey(const Key('lock.confirm')), '12');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.text('A PIN is 4 to 12 digits.'), findsOneWidget);
      expect(bridge.lockCalls, isEmpty);
    });

    testWidgets('a PIN field offers digits and takes nothing else', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(FakeBridge()));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(SecuritySection),
              matching: find.byType(GerfautSwitch),
            )
            .first,
      );
      await tester.pumpAndSettle();

      final secret = find.descendant(
        of: find.byKey(const Key('lock.secret')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(secret).keyboardType,
        TextInputType.number,
      );
      await tester.enterText(secret, '12ab34');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(secret).controller!.text, '1234');
    });

    testWidgets('turning it off asks for the secret in place', (tester) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(SecuritySection),
              matching: find.byType(GerfautSwitch),
            )
            // The app lock is the first switch of the card; the disguise
            // switch sits below it once a lock stands.
            .first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(bridge.lockCalls, contains('clear'));
      expect(bridge.lock, isNull);
    });

    testWidgets('a wrong secret leaves the lock in place, and says so', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(SecuritySection),
              matching: find.byType(GerfautSwitch),
            )
            // The app lock is the first switch of the card; the disguise
            // switch sits below it once a lock stands.
            .first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '0000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(find.text('wrong PIN or password'), findsOneWidget);
      expect(bridge.lock, isNotNull);
    });

    testWidgets('the delay is one of four, and the choice is kept', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('LOCK WHEN AWAY'), findsOneWidget);
      for (final label in ['Immediately', '1 min', '5 min', '15 min']) {
        expect(find.text(label), findsOneWidget);
      }
      // No question the user cannot answer: no "Never", nothing longer.
      expect(find.text('Never'), findsNothing);
      expect(find.text('30 min'), findsNothing);
      expect(
        find.text(
          'Counted from when Gerfaut leaves the screen. Turning the screen '
          'off locks it at once.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('again once you have been away'),
        findsOneWidget,
      );
      expect(find.textContaining('every time it comes back'), findsNothing);
      // The one trip that does not count, with the time it is good for.
      expect(
        find.textContaining(
          'A file picker or share sheet Gerfaut opens does not count as '
          'away if you are back within 10 minutes.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('5 min'));
      await tester.pumpAndSettle();
      expect(bridge.appPrefs[Pref.lockDelay], '300');
      await tester.tap(find.text('Immediately'));
      await tester.pumpAndSettle();
      expect(bridge.appPrefs[Pref.lockDelay], '0');

      // What the card still offers is unchanged.
      expect(find.text('Change PIN'), findsOneWidget);
      expect(find.text('Lock now'), findsOneWidget);
    });

    testWidgets('on iOS, the hint promises nothing of the screen', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [
            ..._overrides(locked(), null),
            platformFeaturesProvider.overrideWithValue(PlatformFeatures.ios),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const SettingsScreen(section: SettingsSection.security),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Counted from when Gerfaut leaves the screen.'),
        findsOneWidget,
      );
      expect(find.textContaining('Turning the screen off'), findsNothing);
      // No picker leaves the app there, so no trip to excuse.
      expect(find.textContaining('file picker'), findsNothing);
    });

    testWidgets('a PIN lock can keep its keypad in order', (tester) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: find.text('Shuffle the keypad'),
        matching: find.byType(SettingSwitch),
      );
      expect(tester.widget<SettingSwitch>(row).value, isTrue);
      expect(
        find.text(
          'The digits change places at every unlock, so no one learns your '
          'PIN from where your finger goes.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(GerfautSwitch)),
      );
      await tester.pumpAndSettle();
      expect(bridge.appPrefs[Pref.lockShuffle], '0');
      expect(tester.widget<SettingSwitch>(row).value, isFalse);
    });

    testWidgets('a password lock has no keypad to shuffle', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(
          locked(
            lock: const AppLock(kind: LockKind.password, biometric: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOCK WHEN AWAY'), findsOneWidget);
      expect(find.text('Shuffle the keypad'), findsNothing);
    });

    testWidgets('biometrics are offered only where the phone can answer', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(
        settingsApp(bridge, biometrics: FakeBiometrics(available: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unlock with biometrics'), findsNothing);

      await tester.pumpWidget(
        settingsApp(locked(), biometrics: FakeBiometrics()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unlock with biometrics'), findsOneWidget);
    });

    testWidgets('a weak biometric is not offered, and the card says why', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(
          locked(),
          biometrics: FakeBiometrics(offers: BiometricSupport.weakOnly),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: find.text('Unlock with biometrics'),
        matching: find.byType(SettingSwitch),
      );
      expect(tester.widget<SettingSwitch>(row).onChanged, isNull);
      expect(tester.widget<SettingSwitch>(row).value, isFalse);
      expect(find.text(biometricsWeakNote(LockKind.pin)), findsOneWidget);
    });

    testWidgets('a sensor out of service for now greys nothing out', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked(
        lock: const AppLock(kind: LockKind.pin, biometric: true),
      )..lockSecret = '1234';
      await tester.pumpWidget(
        settingsApp(
          bridge,
          biometrics: FakeBiometrics(offers: BiometricSupport.unavailable),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: find.text('Unlock with biometrics'),
        matching: find.byType(SettingSwitch),
      );
      expect(tester.widget<SettingSwitch>(row).onChanged, isNotNull);
      expect(tester.widget<SettingSwitch>(row).value, isTrue);
      expect(find.text(biometricsWeakNote(LockKind.pin)), findsNothing);
    });

    testWidgets('turning biometrics on makes the key behind the secret', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      final biometrics = FakeBiometrics();
      await tester.pumpWidget(settingsApp(bridge, biometrics: biometrics));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Unlock with biometrics'),
            matching: find.byType(SettingSwitch),
          ),
          matching: find.byType(GerfautSwitch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(biometrics.enrolls, 1);
      expect(bridge.lock?.biometric, isTrue);

      // Off again: the key goes with it.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Unlock with biometrics'),
            matching: find.byType(SettingSwitch),
          ),
          matching: find.byType(GerfautSwitch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(bridge.lock?.biometric, isFalse);
      expect(biometrics.forgets, 1);
    });

    testWidgets('a key the phone did not confirm turns nothing on', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      final biometrics = FakeBiometrics(passes: false);
      await tester.pumpWidget(settingsApp(bridge, biometrics: biometrics));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Unlock with biometrics'),
            matching: find.byType(SettingSwitch),
          ),
          matching: find.byType(GerfautSwitch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(biometrics.enrolls, 1);
      expect(bridge.lock?.biometric, isFalse);
      expect(
        find.text('The phone did not confirm. Nothing changed.'),
        findsOneWidget,
      );
    });

    testWidgets('locking from a pushed screen brings the lock to the front', (
      tester,
    ) async {
      // The settings live above the home route: a lock that only
      // replaced the home would sit behind them, in plain view.
      useTallSurface(tester);
      final bridge = locked(wallets: [makeMeta()]);
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      await unlockWithPin(tester, '1234');
      expect(find.byType(LockScreen), findsNothing);

      await pickFromMenu(tester, 'Settings');
      expect(find.text('Network'), findsOneWidget);
      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lock now'));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      // Nothing of the settings, and nothing of a wallet, is behind it.
      expect(find.text('Network'), findsNothing);
      expect(find.text('Cold storage'), findsNothing);
    });
  });

  group('the window', () {
    testWidgets('a vault with a lock marks the window secure', (tester) async {
      final guard = FakeWindowGuard();
      await tester.pumpWidget(app(locked(), guard: guard));
      await tester.pumpAndSettle();

      // The task switcher photographs the app before the lock draws;
      // only the window flag keeps a balance out of that picture.
      expect(guard.secure, isTrue);
    });

    testWidgets('a vault without a lock leaves the window plain', (
      tester,
    ) async {
      final guard = FakeWindowGuard();
      await tester.pumpWidget(app(FakeBridge(), guard: guard));
      await tester.pumpAndSettle();

      // Said once, and as plain: screenshots keep working, for the user
      // who wants to show a screen as much as for the emulator tests.
      expect(guard.calls, [false]);
    });

    test('the window follows the lock as the settings change', () {
      final guard = FakeWindowGuard();
      final container = ProviderContainer(
        retry: noRetry,
        overrides: _overrides(locked(), null, guard: guard),
      );
      addTearDown(container.dispose);
      final lock = container.read(lockProvider.notifier);

      lock.syncFromSettings(pinLock);
      expect(guard.secure, isTrue);

      // A refetch that says the same thing does not ask again.
      lock.syncFromSettings(pinLock);
      expect(guard.calls, [true]);

      // Turning the lock off hands the window back.
      lock.syncFromSettings(null);
      expect(guard.calls, [true, false]);

      // And on again, from the settings card, secures it again.
      lock.syncFromSettings(pinLock);
      expect(guard.calls, [true, false, true]);
    });

    test('disguised, the window is plain while the calculator shows', () async {
      final guard = FakeWindowGuard();
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(locked()),
          biometricGateProvider.overrideWithValue(
            FakeBiometrics(available: false),
          ),
          windowGuardProvider.overrideWithValue(guard),
          disguiseServiceProvider.overrideWithValue(
            FakeDisguise(disguised: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final lock = container.read(lockProvider.notifier);

      // The lock lands before the platform has said which face the app
      // wears: secure first, then plain once the calculator is known
      // to be what shows.
      lock.syncFromSettings(pinLock);
      expect(guard.calls, [true]);
      await Future<void>.delayed(Duration.zero);
      expect(guard.calls, [true, false]);

      // Unlocked, the wallet is on screen and photographed blank.
      await lock.unlock('1234');
      expect(guard.secure, isTrue);

      // Locked again, the calculator is back and the card shows it.
      lock.lockNow();
      expect(guard.calls, [true, false, true, false]);
    });
  });

  group('the welcome tour', () {
    testWidgets('a vault with nothing in it introduces the app', (
      tester,
    ) async {
      await tester.pumpWidget(app(FakeBridge()));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Watch, never spend'), findsOneWidget);
    });

    testWidgets('a 0.x version says on the first page, and only there, '
        'that it is a public beta', (tester) async {
      await tester.pumpWidget(app(FakeBridge()));
      await tester.pumpAndSettle();

      final line = find.text(
        'Public beta. Check addresses and amounts on your signing device.',
        findRichText: true,
      );
      expect(line, isBetaVersion(appVersion) ? findsOneWidget : findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Add a wallet'), findsOneWidget);
      expect(line, findsNothing);
    });

    testWidgets('it is not shown again once seen', (tester) async {
      final bridge = FakeBridge(
        settings: const Settings(
          preferences: kPreferences,
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'onboarding.seen': '1'},
        ),
      );
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('No wallets yet'), findsOneWidget);
    });

    testWidgets('a vault that already holds a wallet skips it', (tester) async {
      await tester.pumpWidget(app(FakeBridge(wallets: [makeMeta()])));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
    });

    testWidgets('walking to the end remembers it and lands on the wallets', (
      tester,
    ) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      for (var page = 0; page < welcomePages.length - 1; page++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Keep it yours'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(bridge.appPrefs['onboarding.seen'], '1');
      expect(find.text('No wallets yet'), findsOneWidget);
    });

    testWidgets('back is offered from the second page on', (tester) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      // Nothing to go back to on the first page: Skip has the row.
      expect(find.text('Back'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Add a wallet'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      // Back takes the left of the row Skip had to itself.
      expect(
        tester.getRect(find.text('Back')).left,
        lessThan(tester.getRect(find.text('Skip')).left),
      );

      // A page one can only leave or pass is re-read by starting over.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Watch, never spend'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      // Going back is not leaving: the tour is still unseen.
      expect(bridge.appPrefs['onboarding.seen'], isNull);

      // The swipe still does the same work; the button makes it visible.
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Add a wallet'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('skipping counts as seen', (tester) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(bridge.appPrefs['onboarding.seen'], '1');
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('the settings can play it again', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(
        settings: const Settings(
          preferences: kPreferences,
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'onboarding.seen': '1'},
        ),
      );
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.about),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show the welcome tour'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);

      // Skipped, it lands back on About.
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('Show the welcome tour'), findsOneWidget);

      // Read to the end, the last button closes it as well.
      await tester.tap(find.text('Show the welcome tour'));
      await tester.pumpAndSettle();
      for (var page = 1; page < welcomePages.length; page++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('Show the welcome tour'), findsOneWidget);
    });
  });

  group('coming back from the background', () {
    test('any trip away at all asks for the secret again', () async {
      final app = lockedApp();
      expect(app.container.read(lockProvider).locked, isTrue);
      await app.lock.unlock('1234');
      expect(app.container.read(lockProvider).locked, isFalse);

      // Straight there and straight back: no delay to outlast.
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);

      // A settings refetch never re-locks an app already open.
      await app.lock.unlock('1234');
      app.lock.syncFromSettings(pinLock);
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('a return with no trip behind it leaves the app open', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // A permission dialog and the notification shade never hide the
      // app: there is nothing to come back from.
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('with no lock set, nothing ever locks', () async {
      final container = ProviderContainer(
        retry: noRetry,
        overrides: _overrides(FakeBridge(), null),
      );
      addTearDown(container.dispose);
      final lock = container.read(lockProvider.notifier);

      lock.syncFromSettings(null);
      expect(container.read(lockProvider).locked, isFalse);
      lock.noteHidden();
      lock.noteResumed();
      expect(container.read(lockProvider).locked, isFalse);
      lock.lockNow();
      expect(container.read(lockProvider).locked, isFalse);
    });
  });

  group('a system screen Gerfaut opened itself', () {
    /// Whether the next return from the background locks.
    Future<bool> nextReturnLocks(
      ({ProviderContainer container, LockController lock}) app,
    ) async {
      app.lock.noteHidden();
      app.lock.noteResumed();
      return app.container.read(lockProvider).locked;
    }

    /// The app with its lock, on iOS: pickers drawn over the app.
    Future<({ProviderContainer container, LockController lock})>
    unlockedOnIos() async {
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          ..._overrides(locked(), null),
          platformFeaturesProvider.overrideWithValue(PlatformFeatures.ios),
        ],
      );
      addTearDown(container.dispose);
      lockOnEveryTrip(container);
      final lock = container.read(lockProvider.notifier)
        ..syncFromSettings(pinLock);
      await lock.unlock('1234');
      return (container: container, lock: lock);
    }

    test('on iOS, a picker over the app excuses no later absence', () async {
      final app = await unlockedOnIos();
      expect(await app.lock.excursion(() async => 'picked'), 'picked');
      expect(await nextReturnLocks(app), isTrue);
    });

    test('on iOS, the system settings still excuse their return', () async {
      final app = await unlockedOnIos();
      await app.lock.excursion(() async => true, leavesApp: true);
      expect(await nextReturnLocks(app), isFalse);
    });

    test('an excursion that opened covers its return', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      expect(await app.lock.excursion(() async => 'picked'), 'picked');
      expect(await nextReturnLocks(app), isFalse);
    });

    test('an excursion that failed to open is taken back', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      await expectLater(
        app.lock.excursion<String>(() async => throw StateError('no app')),
        throwsStateError,
      );
      expect(await nextReturnLocks(app), isTrue);
    });

    test('a failure after the screen came up keeps the trip', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      await expectLater(
        app.lock.excursion<String>(
          () async => throw const FormatException('picked, not read'),
          cameUp: (error) => error is FormatException,
        ),
        throwsFormatException,
      );
      expect(await nextReturnLocks(app), isFalse);
    });

    test('a result that says nothing opened is taken back', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      final opened = await app.lock.excursion(
        () async => false,
        shown: (opened) => opened,
      );
      expect(opened, isFalse);
      expect(await nextReturnLocks(app), isTrue);
    });

    test('coming back from a picker does not lock', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('it covers its own return and nothing after it', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // Picked or waved away, the file picker gives back the same
      // return, and that return is the one it was announced for.
      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('one the phone never shows is taken back by the screen', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // No app on the phone could show the picker, so it never opened
      // and Gerfaut never left the screen. The framework delivers
      // nothing at all here — not even a resume, which never arrives
      // without an absence before it — so the screen says so itself.
      app.lock.expectExcursion();
      app.lock.forgetExcursion();

      // The real absence, whenever it comes, is the one that has to
      // lock: hidden, paused, hidden again on the way in, then resumed.
      app.lock.noteHidden();
      app.lock.noteHidden();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('a trip that lasts too long locks all the same', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      var now = DateTime(2026, 9, 25, 14);
      app.lock.clock = () => now;

      // The picker opened, and the phone was put down in front of it.
      app.lock.expectExcursion();
      app.lock.noteHidden();
      now = now.add(excursionAllowance + const Duration(seconds: 1));
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('a clock set back during the trip locks as well', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      var now = DateTime(2026, 9, 25, 14);
      app.lock.clock = () => now;

      // Put down in front of the picker; an hour later somebody sets
      // the date back so the trip looks short.
      app.lock.expectExcursion();
      app.lock.noteHidden();
      now = now.subtract(const Duration(minutes: 1));
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('a trip within the allowance does not', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');
      var now = DateTime(2026, 9, 25, 14);
      app.lock.clock = () => now;

      app.lock.expectExcursion();
      app.lock.noteHidden();
      now = now.add(excursionAllowance);
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('one nobody takes back is spent by whatever comes next', () async {
      // Why every branch that does not leave has to take it back: an
      // announcement waits, and the trip it ends up covering is the
      // next one, if that one comes back within the allowance.
      final app = lockedApp();
      await app.lock.unlock('1234');

      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteHidden();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('taking one back after the trip does not undo the return', () async {
      // The system can answer while the app is still away: the failure
      // of a save lands before Flutter says `resumed`. The return has
      // not happened yet, so the flag it will spend must still be there.
      final app = lockedApp();
      await app.lock.unlock('1234');

      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      app.lock.forgetExcursion();
      expect(app.container.read(lockProvider).locked, isFalse);

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('two in a row each cover their own return', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      for (var trip = 0; trip < 2; trip++) {
        app.lock.expectExcursion();
        app.lock.noteHidden();
        app.lock.noteResumed();
        expect(app.container.read(lockProvider).locked, isFalse);
      }

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('asking twice before leaving still buys one return', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // A screen that announces the same excursion twice has not
      // bought a second one.
      app.lock.expectExcursion();
      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('one asked for while locked leaves the screen up', () async {
      final app = lockedApp();
      expect(app.container.read(lockProvider).locked, isTrue);

      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);

      // And it was spent there: the first trip after the unlock locks.
      await app.lock.unlock('1234');
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });
  });

  group('the app as the platform moves it', () {
    testWidgets('a PIN half typed goes when Gerfaut leaves the screen', (
      tester,
    ) async {
      await tester.pumpWidget(app(locked(), random: Random(4)));
      await tester.pumpAndSettle();
      final before = padOrder(tester);
      await typePin(tester, '12');

      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(padOrder(tester), isNot(before));
    });

    testWidgets('the lock is decided on the way back, before the focus', (
      tester,
    ) async {
      // Split screen: Android draws Gerfaut again beside the app that
      // keeps the focus, and Gerfaut never hears `resumed`.
      await pumpUnlocked(tester);
      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.inactive);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Cold storage'), findsNothing);
    });

    testWidgets('a trip through the background brings the lock back', (
      tester,
    ) async {
      await pumpUnlocked(tester);
      expect(find.text('Cold storage'), findsOneWidget);

      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Cold storage'), findsNothing);
    });

    testWidgets('a picker Gerfaut opened leaves the flow where it was', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = await pumpUnlocked(tester);
      await pickFromMenu(tester, 'Settings');
      expect(find.text('Network'), findsOneWidget);

      container.read(lockProvider.notifier).expectExcursion();
      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Back from a file picker the user opened two seconds ago: the
      // screen they were on is still there, with no lock in front.
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('Network'), findsOneWidget);

      // A real absence right after still locks, and takes the pushed
      // screen with it.
      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Network'), findsNothing);
    });
  });

  group('the delay', () {
    /// The app unlocked with [stored] as its delay, on two clocks the
    /// test moves: the wall clock and the one nobody can set.
    Future<({LockController lock, _Clocks clocks, bool Function() isLocked})>
    unlockedWith(String? stored) async {
      final app = lockedApp();
      app.container.read(lockDelayProvider.notifier).hydrate(stored);
      final clocks = _Clocks();
      app.lock
        ..clock = (() => clocks.wall)
        ..uptime = (() => clocks.steady);
      await app.lock.unlock('1234');
      return (
        lock: app.lock,
        clocks: clocks,
        isLocked: () => app.container.read(lockProvider).locked,
      );
    }

    test('disguised, the calculator comes back at every trip', () async {
      final app = lockedApp(delay: LockDelay.fifteenMinutes);
      await app.container.read(disguiseProvider.notifier).set(true);
      await app.lock.unlock('1234');
      app.lock
        ..noteHidden()
        ..noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test(
      'a trip whose date was set back by less than it lasted locks',
      () async {
        final app = await unlockedWith('900');
        // The picker opened, the phone was left in front of it for an
        // hour, then the date was set back 55 minutes: the wall clock
        // says five minutes, the one nobody can set says an hour.
        app.lock
          ..expectExcursion()
          ..noteHidden();
        app.clocks
          ..wall = app.clocks.wall.add(const Duration(minutes: 5))
          ..steady += const Duration(hours: 1);
        app.lock.noteResumed();
        expect(app.isLocked(), isTrue);
      },
    );

    test('Immediately locks at the first trip, however short', () async {
      final app = await unlockedWith('0');
      app.lock
        ..noteHidden()
        ..noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('a minute away leaves the app open under it, not at it', () async {
      final app = await unlockedWith('60');
      app.lock.noteHidden();
      app.clocks.pass(const Duration(seconds: 59));
      app.lock.noteResumed();
      expect(app.isLocked(), isFalse);

      app.lock.noteHidden();
      app.clocks.pass(const Duration(seconds: 60));
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('nothing stored, or a delay this build lacks, is a minute', () async {
      for (final stored in [null, '', '1800', 'never']) {
        final app = await unlockedWith(stored);
        app.lock.noteHidden();
        app.clocks.pass(const Duration(seconds: 59));
        app.lock.noteResumed();
        expect(app.isLocked(), isFalse, reason: '$stored');

        app.lock.noteHidden();
        app.clocks.pass(const Duration(seconds: 61));
        app.lock.noteResumed();
        expect(app.isLocked(), isTrue, reason: '$stored');
      }
    });

    test('the count starts at the first sign of leaving', () async {
      // The framework walks the chain back on the way in: the hidden
      // state lands again a beat before the resume, and must not start
      // the count over.
      final app = await unlockedWith('60');
      app.lock.noteHidden();
      app.clocks.pass(const Duration(seconds: 50));
      app.lock.noteHidden();
      app.clocks.pass(const Duration(seconds: 11));
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('a clock set back while away locks', () async {
      final app = await unlockedWith('900');
      app.lock.noteHidden();
      app.clocks
        ..wall = app.clocks.wall.subtract(const Duration(hours: 1))
        ..steady += const Duration(seconds: 30);
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('a clock set forward only locks sooner', () async {
      final app = await unlockedWith('900');
      app.lock.noteHidden();
      app.clocks
        ..wall = app.clocks.wall.add(const Duration(minutes: 20))
        ..steady += const Duration(seconds: 10);
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('the clock nobody can set is enough on its own', () async {
      final app = await unlockedWith('60');
      app.lock.noteHidden();
      app.clocks
        ..wall = app.clocks.wall.add(const Duration(milliseconds: 59500))
        ..steady += const Duration(seconds: 61);
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('a wall clock that fell behind the other was moved', () async {
      final app = await unlockedWith('60');
      app.lock.noteHidden();
      app.clocks
        ..wall = app.clocks.wall.add(const Duration(seconds: 10))
        ..steady += const Duration(seconds: 30);
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    test('a few ticks between the two clocks are no move', () async {
      final app = await unlockedWith('60');
      app.lock.noteHidden();
      app.clocks
        ..wall = app.clocks.wall.add(const Duration(seconds: 30))
        ..steady += const Duration(milliseconds: 31500);
      app.lock.noteResumed();
      expect(app.isLocked(), isFalse);
    });

    test('a trip of its own past ten minutes is left to the delay', () async {
      final app = await unlockedWith('900');
      app.lock
        ..expectExcursion()
        ..noteHidden();
      app.clocks.pass(excursionAllowance + const Duration(minutes: 1));
      app.lock.noteResumed();
      expect(app.isLocked(), isFalse);

      app.lock
        ..expectExcursion()
        ..noteHidden();
      app.clocks.pass(const Duration(minutes: 16));
      app.lock.noteResumed();
      expect(app.isLocked(), isTrue);
    });

    testWidgets('a short trip under the delay comes back open', (tester) async {
      final container = await pumpUnlocked(tester, delay: null);

      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);

      // The home screen dates its figures on a clock that ticks while a
      // line watches it: it stops with the app, here with its container.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('a fresh launch opens locked, whatever the delay', (
      tester,
    ) async {
      final bridge = locked(wallets: [makeMeta()])
        ..appPrefs[Pref.lockDelay] = '900';
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();
      await unlockWithPin(tester, '1234');
      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);

      // Killed a moment later, and opened again: the count lived in
      // memory, and went with it.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Cold storage'), findsNothing);
    });
  });

  group('the screen going off', () {
    test('an unlock still checked when it goes off opens nothing', () async {
      final app = lockedApp(delay: LockDelay.fifteenMinutes);
      final bridge = app.container.read(bridgeProvider) as FakeBridge;
      final gate = Completer<void>();
      bridge.verifyGate = gate;

      // The right PIN, and the power button pressed while the core is
      // still hashing it: whoever wakes the phone did not type it.
      final unlocking = app.lock.unlock('1234');
      app.lock.screenOff();
      gate.complete();
      expect((await unlocking).unlocked, isFalse);
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    testWidgets('takes a PIN half typed with it', (tester) async {
      final screen = FakeScreenOffWatch();
      await tester.pumpWidget(app(locked(), screen: screen));
      await tester.pumpAndSettle();
      await typePin(tester, '123');
      expect(find.text('Enter your PIN'), findsNothing);

      screen.turnOff();
      await tester.pump();
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets('locks at once with Gerfaut in front', (tester) async {
      final screen = FakeScreenOffWatch();
      await pumpUnlocked(tester, delay: '900', screen: screen);
      expect(screen.listening, isTrue);

      screen.turnOff();
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Cold storage'), findsNothing);
    });

    test('locks at the return, whatever the delay', () async {
      final app = lockedApp(delay: LockDelay.fifteenMinutes);
      await app.lock.unlock('1234');
      app.lock
        ..noteHidden()
        ..screenOff()
        ..noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('locks even back from a trip Gerfaut sent the user on', () async {
      final app = lockedApp(delay: LockDelay.fifteenMinutes);
      await app.lock.unlock('1234');
      app.lock
        ..expectExcursion()
        ..noteHidden()
        ..screenOff()
        ..noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('counts for the return after it, and no other', () async {
      final app = lockedApp(delay: LockDelay.fifteenMinutes);
      await app.lock.unlock('1234');
      app.lock
        ..noteHidden()
        ..screenOff()
        ..noteResumed();
      await app.lock.unlock('1234');

      app.lock
        ..noteHidden()
        ..noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });
  });

  group('the PIN pad', () {
    testWidgets('the digits change places from one opening to the next', (
      tester,
    ) async {
      await tester.pumpWidget(app(locked(), random: Random(1)));
      await tester.pumpAndSettle();
      final first = padOrder(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(locked(), random: Random(2)));
      await tester.pumpAndSettle();
      expect(padOrder(tester), isNot(first));
    });

    testWidgets('a refused PIN draws the digits again', (tester) async {
      await tester.pumpWidget(app(locked(), random: Random(3)));
      await tester.pumpAndSettle();
      final before = padOrder(tester);

      await unlockWithPin(tester, '9999');
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(padOrder(tester), isNot(before));
    });

    testWidgets('the shuffle turned off keeps the phone order', (tester) async {
      final bridge = locked()..appPrefs[Pref.lockShuffle] = '0';
      await tester.pumpWidget(app(bridge, random: Random(1)));
      await tester.pumpAndSettle();

      expect(padOrder(tester), [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]);
      // The 0 under the 8, the bottom left cell left empty.
      expect(
        tester.getCenter(find.byKey(const Key('pin.0'))).dx,
        tester.getCenter(find.byKey(const Key('pin.8'))).dx,
      );
    });

    testWidgets('a screen reader keeps the phone order', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(app(locked(), random: Random(1)));
      await tester.pumpAndSettle();

      expect(padOrder(tester), [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]);
    });

    testWidgets('digits go in, one comes out, a long press clears them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();

      await typePin(tester, '123');
      expect(dotsSaid(tester), 'PIN, 3 digits entered');
      expect(find.text('Enter your PIN'), findsNothing);

      await tester.tap(find.byKey(const Key('pin.delete')));
      await tester.pump();
      expect(dotsSaid(tester), 'PIN, 2 digits entered');

      await tester.longPress(find.byKey(const Key('pin.delete')));
      await tester.pump();
      expect(dotsSaid(tester), 'PIN, no digits entered');
      expect(find.text('Enter your PIN'), findsOneWidget);

      // Then the right one, sent by Unlock.
      await unlockWithPin(tester, '1234');
      expect(find.byType(LockScreen), findsNothing);
      handle.dispose();
    });

    testWidgets('twelve digits at most', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();

      await typePin(tester, '1234567890123');
      expect(dotsSaid(tester), 'PIN, 12 digits entered');
      handle.dispose();
    });

    testWidgets('keys as tall as the room allows, never under 48', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final (size, scale, height) in [
        (const Size(400, 800), 1.0, 64.0),
        (const Size(320, 568), 2.0, 48.0),
        (const Size(640, 360), 1.0, 48.0),
      ]) {
        await tester.pumpWidget(const SizedBox());
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(app(locked()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
        for (final key in ['pin.0', 'pin.5', 'pin.delete']) {
          expect(
            tester.getSize(find.byKey(Key(key))).height,
            greaterThanOrEqualTo(height),
            reason: '$key at $size',
          );
        }
        expect(
          tester.getSize(find.byKey(const Key('pin.5'))).height,
          lessThanOrEqualTo(PinPad.keyHeight),
        );
        // Unlock stays pinned in reach without scrolling; the pad
        // scrolls above it when the room runs short.
        expect(find.text('Unlock').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('pin.0')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pin.0')).hitTestable(), findsOneWidget);
        expect(find.text('Unlock').hitTestable(), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a password keeps its field and the phone keyboard', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          locked(
            lock: const AppLock(kind: LockKind.password, biometric: false),
            secret: 'hunter22',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PinPad), findsNothing);
      expectKeyboardKeepsNothing(tester);
      await tester.enterText(find.byType(TextField), 'hunter22');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
    });
  });
}

/// The two clocks the lock reads, moved by hand.
class _Clocks {
  DateTime wall = DateTime(2026, 11, 18, 9);
  Duration steady = const Duration(hours: 3);

  /// Time passes on both, alike.
  void pass(Duration time) {
    wall = wall.add(time);
    steady += time;
  }
}
