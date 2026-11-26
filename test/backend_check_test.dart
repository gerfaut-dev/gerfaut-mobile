// The connection test that follows every save of a backend: the wait,
// what the server answered, what stands in the way, and when it goes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart' show themeFrom;
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/notice.dart';

import 'core_fixtures.dart';
import 'fakes.dart';

/// The settings opened on [section], or on the root list of sections.
Widget _app(FakeBridge bridge, {SettingsSection? section}) {
  return ProviderScope(
    retry: noRetry,
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
    child: creditedApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: SettingsScreen(section: section),
    ),
  );
}

/// A workspace whose mainnet backend is [backend], so saving it is one
/// tap.
FakeBridge _pointedAt(BackendConfig backend) {
  return FakeBridge(
    settings: Settings(
      preferences: kPreferences,
      activeNetwork: Network.mainnet,
      backends: {Network.mainnet: backend},
      appPrefs: const {},
    ),
  );
}

FakeBridge _ownElectrum() =>
    _pointedAt(const CustomElectrum(url: 'ssl://node.local:50002'));

Future<void> _open(WidgetTester tester, FakeBridge bridge) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(bridge, section: SettingsSection.network));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save backend'));
  await tester.pumpAndSettle();
}

bool _saveBusy(WidgetTester tester) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Save backend'))
    .busy;

final Finder _testAgain = find.widgetWithText(SecondaryButton, 'Test again');
final Finder _cancel = find.widgetWithText(SecondaryButton, 'Cancel');

/// Saves the backend in the form, and stops while its test runs.
Future<void> _saveAndWait(WidgetTester tester) async {
  await tester.tap(find.text('Save backend'));
  // The spinner turns: settling would never end.
  await tester.pump();
  await tester.pump();
}

void _expectCancelled() {
  expect(find.text('Test cancelled'), findsOneWidget);
  expect(find.text('The backend is saved, but not tested.'), findsOneWidget);
  expect(_testAgain, findsOneWidget);
  expect(find.text('Testing the connection…'), findsNothing);
  expect(_cancel, findsNothing);
  // Nothing went wrong: no panel, no icon.
  expect(find.byType(GerfautNotice), findsNothing);
}

/// The focus node of the button labelled [label], as the keyboard
/// sees it.
FocusNode _focusOf(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label)));

/// What the core sends for a failure of [problem] on node.local.
BackendCheck _failed(
  String problem, {
  bool tor = false,
  String detail = 'could not connect',
  String? serverNetwork,
}) => backendCheckCase('refused', {
  'host': 'node.local:50002',
  'problem': problem,
  'tor': tor,
  'detail': detail,
  'server_network': serverNetwork,
});

void main() {
  testWidgets('a save is followed by a test, said while it runs', (
    tester,
  ) async {
    final bridge = _ownElectrum();
    final gate = Completer<void>();
    bridge.checkBackendGate = gate;
    await _open(tester, bridge);
    await tester.tap(find.text('Save backend'));
    // The spinner turns: settling would never end.
    await tester.pump();
    await tester.pump();

    expect(bridge.checkedBackends, [Network.mainnet]);
    expect(find.text('Setting saved'), findsOneWidget);
    expect(find.text('Testing the connection…'), findsOneWidget);
    // One test at a time: Save backend is busy, Test again is gone.
    expect(_saveBusy(tester), isTrue);
    expect(_testAgain, findsNothing);
    // Heard as it changes.
    expect(
      tester
          .getSemantics(find.text('Testing the connection…'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    await tester.tap(find.text('Save backend'));
    await tester.pump();
    expect(bridge.checkedBackends, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Testing the connection…'), findsNothing);
    expect(_saveBusy(tester), isFalse);
  });

  testWidgets('a server reached says its block, software and time', (
    tester,
  ) async {
    final bridge = _ownElectrum();
    await _open(tester, bridge);
    await _save(tester);

    expect(
      find.text('Connected to electrum.example.org:50002', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Block 912 345 · Fulcrum 2.1.3 · 840 ms'), findsOneWidget);
    expect(_testAgain, findsOneWidget);
    // Not a warning: no panel.
    expect(find.byType(GerfautNotice), findsNothing);
  });

  testWidgets('an onion reached through Tor says the longer wait, then Tor', (
    tester,
  ) async {
    const onion =
        'fixturefixturefixturefixturefixturefixturefixturefixture.onion';
    final bridge = _pointedAt(
      const CustomEsplora(url: 'http://$onion/api', ownNode: true),
    );
    final gate = Completer<void>();
    bridge.checkBackendGate = gate;
    bridge.onCheckBackend = (_) => backendCheckCase('reached_esplora_over_tor');
    await _open(tester, bridge);
    await tester.tap(find.text('Save backend'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Testing the connection through Tor. This can take a minute or two.',
      ),
      findsOneWidget,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Connected to $onion', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Block 912 345 · through Tor · 14.2 s'), findsOneWidget);
  });

  group('a failure says what to do, in amber', () {
    for (final (what, backend, check, sentence) in [
      (
        'a port nothing listens on',
        const CustomElectrum(url: 'tcp://node.local:50002'),
        _failed('refused'),
        'The server refused the connection. Check the port, and that the '
            'server is running.',
      ),
      (
        'TLS on a plain Electrum port',
        const CustomElectrum(url: 'ssl://node.local:50002'),
        _failed('not_tls'),
        "This port does not use TLS. Turn TLS off, or use the server's TLS "
            'port (often 50002).',
      ),
      (
        'HTTPS on a plain Esplora address',
        const CustomEsplora(url: 'https://node.local:50002/api'),
        _failed('not_tls'),
        'This address does not use HTTPS. Use http:// instead.',
      ),
      (
        'a server of another network',
        const CustomElectrum(url: 'ssl://node.local:50002'),
        _failed('another_network', serverNetwork: 'testnet4'),
        'This server follows Testnet 4, not Mainnet. Use a Mainnet server.',
      ),
      (
        'an onion service offline',
        const CustomElectrum(url: 'tcp://node.local:50002'),
        _failed('no_answer', tor: true),
        'The onion service does not answer. Check the address and that your '
            'node is online, then test again.',
      ),
      (
        'Tor out of reach',
        const CustomElectrum(url: 'tcp://node.local:50002'),
        _failed('tor', tor: true, detail: 'the Tor proxy refused'),
        'Tor is not available: the Tor proxy refused. Check Settings › '
            'Network › Tor, then test again.',
      ),
    ]) {
      testWidgets(what, (tester) async {
        final bridge = _pointedAt(backend);
        bridge.onCheckBackend = (_) => check;
        await _open(tester, bridge);
        await _save(tester);

        final notice = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
        expect(notice.message, 'Could not connect to node.local:50002');
        expect(notice.hint, sentence);
        // A backend that does not answer loses neither funds nor
        // privacy: never red.
        expect(notice.tone, NoticeTone.info);
        expect(_testAgain, findsOneWidget);
      });
    }

    testWidgets('a command that fails is a failed test in its words', (
      tester,
    ) async {
      final bridge = _ownElectrum();
      bridge.onCheckBackend = (_) =>
          throw coreFailure('vault', 'the vault could not be read');
      await _open(tester, bridge);
      await _save(tester);

      final notice = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(notice.message, 'Could not connect');
      expect(notice.hint, 'The test failed: the vault could not be read');
    });
  });

  testWidgets('Test again tests the stored backend once more', (tester) async {
    final bridge = _ownElectrum();
    bridge.onCheckBackend = (_) => _failed('refused');
    await _open(tester, bridge);
    await _save(tester);
    expect(find.text('Could not connect to node.local:50002'), findsOneWidget);

    final gate = Completer<void>();
    bridge.checkBackendGate = gate;
    bridge.onCheckBackend = null;
    await tester.tap(_testAgain);
    await tester.pump();
    await tester.pump();
    expect(bridge.checkedBackends, [Network.mainnet, Network.mainnet]);
    expect(find.text('Could not connect to node.local:50002'), findsNothing);
    expect(find.text('Testing the connection…'), findsOneWidget);
    expect(_testAgain, findsNothing);
    // Nothing is saved again.
    expect(bridge.inspectedCertificates, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Connected to electrum.example.org:50002', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('an edit of the form takes the result back', (tester) async {
    final bridge = _ownElectrum();
    await _open(tester, bridge);
    await _save(tester);
    expect(_testAgain, findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'other.local');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Connected to', findRichText: true),
      findsNothing,
    );
    expect(_testAgain, findsNothing);
  });

  group('Cancel', () {
    testWidgets('is offered under the wait, and read out with what it stops', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final bridge = _ownElectrum();
      bridge.checkBackendGate = Completer<void>();
      await _open(tester, bridge);
      await _saveAndWait(tester);

      expect(_cancel, findsOneWidget);
      // Under the words, the phone being narrow.
      expect(
        tester.getTopLeft(_cancel).dy,
        greaterThan(
          tester.getBottomLeft(find.text('Testing the connection…')).dy,
        ),
      );
      expect(
        find.bySemanticsLabel('Cancel the connection test'),
        findsOneWidget,
      );
      handle.dispose();
    });

    for (final late in ['reached_electrum', 'refused', 'cancelled']) {
      testWidgets('stops the test at once, a late $late answer dropped', (
        tester,
      ) async {
        final bridge = _ownElectrum();
        final gate = Completer<void>();
        bridge.checkBackendGate = gate;
        bridge.onCheckBackend = (_) => backendCheckCase(late);
        await _open(tester, bridge);
        await _saveAndWait(tester);
        expect(_saveBusy(tester), isTrue);

        await tester.tap(_cancel);
        await tester.pump();
        _expectCancelled();
        expect(bridge.cancelledBackendChecks, [Network.mainnet]);
        expect(_saveBusy(tester), isFalse);
        // The backend stays saved: Cancel takes nothing back.
        expect(bridge.savedBackends, hasLength(1));

        gate.complete();
        await tester.pumpAndSettle();
        _expectCancelled();
        expect(bridge.cancelledBackendChecks, hasLength(1));
      });
    }

    testWidgets('Test again after it tests once more', (tester) async {
      final bridge = _ownElectrum();
      bridge.checkBackendGate = Completer<void>();
      await _open(tester, bridge);
      await _saveAndWait(tester);
      await tester.tap(_cancel);
      await tester.pump();

      bridge.checkBackendGate = null;
      await tester.tap(_testAgain);
      await tester.pumpAndSettle();
      expect(bridge.checkedBackends, [Network.mainnet, Network.mainnet]);
      expect(
        find.text(
          'Connected to electrum.example.org:50002',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('pressed from the keyboard hands the focus to Test again', (
      tester,
    ) async {
      final bridge = _ownElectrum();
      bridge.checkBackendGate = Completer<void>();
      await _open(tester, bridge);
      await _saveAndWait(tester);

      _focusOf(tester, 'Cancel').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(find.text('Test cancelled'), findsOneWidget);
      expect(_focusOf(tester, 'Test again').hasFocus, isTrue);

      // And back: Test again pressed hands it to the new Cancel.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(_cancel, findsOneWidget);
      expect(_focusOf(tester, 'Cancel').hasFocus, isTrue);
    });

    testWidgets('focused as the test ends, the focus goes to Test again', (
      tester,
    ) async {
      final bridge = _ownElectrum();
      final gate = Completer<void>();
      bridge.checkBackendGate = gate;
      await _open(tester, bridge);
      await _saveAndWait(tester);
      _focusOf(tester, 'Cancel').requestFocus();
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();
      expect(_focusOf(tester, 'Test again').hasFocus, isTrue);
      expect(bridge.cancelledBackendChecks, isEmpty);
    });
  });

  testWidgets('a test the core cancelled says so the same way', (tester) async {
    final bridge = _ownElectrum();
    bridge.onCheckBackend = (_) => backendCheckCase('cancelled');
    await _open(tester, bridge);
    await _save(tester);

    _expectCancelled();
    expect(bridge.cancelledBackendChecks, isEmpty);
  });

  testWidgets('an edit during a test cancels it, and that network\'s alone', (
    tester,
  ) async {
    final bridge = FakeBridge(
      settings: Settings(
        preferences: kPreferences,
        activeNetwork: Network.mainnet,
        backends: {
          Network.mainnet: const CustomElectrum(url: 'ssl://node.local:50002'),
          Network.signet: const CustomElectrum(url: 'ssl://node.local:60002'),
        },
        appPrefs: const {},
      ),
    );
    final gate = Completer<void>();
    bridge.checkBackendGate = gate;
    await _open(tester, bridge);
    await _saveAndWait(tester);
    await tester.tap(find.text('Signet'));
    await tester.pump();
    await tester.pump();
    await _saveAndWait(tester);
    expect(bridge.checkedBackends, [Network.mainnet, Network.signet]);

    await tester.enterText(find.byType(TextField).first, 'other.local');
    await tester.pump();
    expect(bridge.cancelledBackendChecks, [Network.signet]);
    expect(find.text('Testing the connection…'), findsNothing);
    expect(find.text('Test cancelled'), findsNothing);
    expect(_testAgain, findsNothing);
    expect(_saveBusy(tester), isFalse);

    // Mainnet's test runs on, and its answer still lands.
    await tester.tap(find.text('Mainnet'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Testing the connection…'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Connected to electrum.example.org:50002', findRichText: true),
      findsOneWidget,
    );
    expect(bridge.cancelledBackendChecks, [Network.signet]);
  });

  testWidgets('the result outlives the page, and is its network\'s own', (
    tester,
  ) async {
    final bridge = _ownElectrum();
    final gate = Completer<void>();
    bridge.checkBackendGate = gate;
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save backend'));
    await tester.pump();
    await tester.pump();

    // Left while the test runs; its answer lands meanwhile.
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(
      find.text('Connected to electrum.example.org:50002', findRichText: true),
      findsOneWidget,
    );
    // Leaving did not cancel it.
    expect(bridge.cancelledBackendChecks, isEmpty);

    // Another network has no result of its own yet.
    await tester.tap(find.text('Signet'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Connected to', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('no test after a save the core refused', (tester) async {
    final bridge = _ownElectrum();
    bridge.onSetBackend = (_, _) =>
        throw coreFailure('invalid_input', 'the host has a port in it');
    await _open(tester, bridge);
    await _save(tester);

    expect(find.text('the host has a port in it'), findsOneWidget);
    expect(bridge.checkedBackends, isEmpty);
    expect(find.text('Testing the connection…'), findsNothing);
  });

  group('a certificate to accept', () {
    const unknown = UnknownCertificate(
      fingerprint:
          '4B:CD:74:1F:2A:39:58:67:76:85:94:A3:B2:C1:D0:EF:'
          '0E:1D:2C:3B:4A:59:68:77:86:95:A4:B3:C2:D1:E0:FF',
      reason: 'self-signed',
    );

    testWidgets('refused: nothing saved, nothing tested', (tester) async {
      final bridge = _ownElectrum();
      bridge.onInspectCertificate = (_) => unknown;
      await _open(tester, bridge);
      await _save(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(bridge.savedBackends, isEmpty);
      expect(bridge.checkedBackends, isEmpty);
    });

    testWidgets('accepted: saved with it, then tested', (tester) async {
      final bridge = _ownElectrum();
      bridge.onInspectCertificate = (_) => unknown;
      await _open(tester, bridge);
      await _save(tester);
      await tester.tap(find.text('Accept and save'));
      await tester.pumpAndSettle();

      expect(bridge.trustedCertificates, hasLength(1));
      expect(bridge.checkedBackends, [Network.mainnet]);
      expect(_testAgain, findsOneWidget);
    });
  });
}
