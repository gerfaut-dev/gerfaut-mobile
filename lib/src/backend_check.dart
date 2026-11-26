// The test that follows every save of a backend, and what it says.
//
// Through Tor a test can take two minutes, and leaving the Network page
// meanwhile must not drop its answer: the tests live here, one per
// network, for as long as the app runs, and the form found again shows
// the test still under way or what it found.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'electrum.dart';
import 'format.dart';
import 'models.dart';
import 'state.dart';

/// What a test is about, as its sentences need it.
class TestedBackend {
  const TestedBackend({required this.electrum, required this.onion});

  /// What [config] reaches: the protocol of its server, and whether that
  /// is a Tor hidden service. The rotation over public servers is
  /// Esplora's; [servers] is the catalogue of the network, when it is
  /// in.
  factory TestedBackend.of(BackendConfig config, List<PublicServer>? servers) {
    final String url;
    final bool electrum;
    switch (config) {
      case CustomElectrum(url: final address):
        url = address;
        electrum = true;
      case CustomEsplora(url: final address):
        url = address;
        electrum = false;
      case PublicEsplora(:final server):
        final chosen = servers?.where((s) => s.id == server).firstOrNull;
        url = chosen?.url ?? '';
        electrum = chosen?.protocol == ServerProtocol.electrum;
    }
    final host = electrum
        ? parseElectrumUrl(url).host
        : (Uri.tryParse(url)?.host ?? '');
    return TestedBackend(
      electrum: electrum,
      onion: RegExp(r'\.onion\.?$', caseSensitive: false).hasMatch(host),
    );
  }

  /// An Electrum server, rather than an Esplora one: the same problem is
  /// said for each in its own words.
  final bool electrum;

  /// A Tor hidden service: the wait is longer, and says so.
  final bool onion;
}

/// The test of a network's stored backend: under way, or what it found.
sealed class BackendTest {
  const BackendTest(this.backend);

  final TestedBackend backend;
}

/// Under way.
class BackendTesting extends BackendTest {
  const BackendTesting(super.backend, {required this.run});

  /// Tells one test from the next, for the answer that lands late.
  final int run;
}

/// Done: what the server answered, what stands in the way, or that it
/// was cancelled.
class BackendTested extends BackendTest {
  const BackendTested(super.backend, this.check);

  final BackendCheck check;
}

/// One test per network, said under Save backend.
class BackendTests extends Notifier<Map<Network, BackendTest>> {
  int _runs = 0;

  @override
  Map<Network, BackendTest> build() => const {};

  /// Whether the backend of [network] is being tested.
  bool testing(Network network) => state[network] is BackendTesting;

  /// Tests the backend stored for [network], unless a test of it is
  /// already under way: one at a time per network. Its answer lands
  /// whatever page is open, unless the test was cancelled, or a newer
  /// one took its place, meanwhile. A command that fails says so as a
  /// failed test, in its own words.
  Future<void> test(Network network, TestedBackend backend) async {
    if (testing(network)) return;
    final run = ++_runs;
    _put(network, BackendTesting(backend, run: run));
    final bridge = ref.read(bridgeProvider);
    BackendCheck check;
    try {
      check = await bridge.checkBackend(network);
    } on BridgeException catch (error) {
      check = BackendFailed(
        host: '',
        tor: false,
        problem: BackendProblem.failed,
        detail: error.message,
      );
    }
    if (!ref.mounted) return;
    final current = state[network];
    if (current is! BackendTesting || current.run != run) return;
    _put(network, BackendTested(backend, check));
  }

  /// Cancel: the test of [network] under way stops, in the core and on
  /// screen at once, and says so. The backend stays saved, untested;
  /// the answer still on its way is dropped.
  void cancel(Network network) {
    final current = state[network];
    if (current is! BackendTesting) return;
    _put(network, BackendTested(current.backend, const BackendCancelled()));
    _cancelInCore(network);
  }

  /// Takes back what the last test of [network] found, or stops the one
  /// under way: the form no longer holds what it was about.
  void clear(Network network) {
    final current = state[network];
    if (current == null) return;
    _put(network, null);
    if (current is BackendTesting) _cancelInCore(network);
  }

  /// Stops the test of [network] in the core, its connections with it.
  /// Nothing to say if that fails: the screen already let it go.
  void _cancelInCore(Network network) {
    try {
      ref.read(bridgeProvider).cancelBackendCheck(network);
    } catch (_) {
      // Already said on screen; the late answer is dropped by its run.
    }
  }

  void _put(Network network, BackendTest? test) {
    final next = {...state};
    if (test == null) {
      next.remove(network);
    } else {
      next[network] = test;
    }
    state = next;
  }
}

final backendTestsProvider =
    NotifierProvider<BackendTests, Map<Network, BackendTest>>(BackendTests.new);

/// A sentence of the core ends without its full stop; one is put after
/// it before another sentence follows.
String _sentence(String detail) {
  final text = detail.trim();
  return RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}

/// What a failed test says the person can do, in the words of the
/// protocol tested: the same as the desktop app's.
String backendFailureWords(
  BackendFailed check, {
  required bool electrum,
  required Network network,
}) {
  final ours = network.label;
  return switch (check.problem) {
    BackendProblem.hostNotFound =>
      'This name does not resolve. Check the spelling of the host.',
    BackendProblem.refused =>
      'The server refused the connection. Check the port, and that the '
          'server is running.',
    BackendProblem.noAnswer =>
      check.tor
          ? 'The onion service does not answer. Check the address and that '
                'your node is online, then test again.'
          : 'The server does not answer. Check the address, and that this '
                'device can reach it: same network, VPN or firewall.',
    BackendProblem.tor =>
      'Tor is not available: ${_sentence(check.detail)} Check Settings › '
          'Network › Tor, then test again.',
    BackendProblem.notTls =>
      electrum
          ? "This port does not use TLS. Turn TLS off, or use the server's "
                'TLS port (often 50002).'
          : 'This address does not use HTTPS. Use http:// instead.',
    BackendProblem.needsTls =>
      electrum
          ? 'This port expects TLS. Turn TLS on.'
          : 'This address expects HTTPS. Use https:// instead.',
    BackendProblem.certificate =>
      electrum
          ? "The server's certificate is not accepted. Press Save backend to "
                'review it.'
          : "No public authority vouches for this server's certificate. Use "
                'one that a public authority signed, or reach the server '
                'through Tor.',
    BackendProblem.notElectrum =>
      'Something answers on this port, but not an Electrum server. Check '
          'the port: Electrum often uses 50001, or 50002 with TLS.',
    BackendProblem.notEsplora =>
      'Something answers at this address, but not an Esplora API. Check '
          'the URL, path included: it often ends in /api.',
    BackendProblem.anotherNetwork => switch (check.serverNetwork) {
      final theirs? =>
        'This server follows ${theirs.label}, not $ours. Use a $ours server.',
      null => 'This server follows another network than $ours.',
    },
    BackendProblem.badChain =>
      "The server's chain does not hold up. Use another server.",
    BackendProblem.serverRefused =>
      'The server refused the request: ${check.detail}',
    BackendProblem.failed => 'The test failed: ${check.detail}',
  };
}

/// The line under "Connected to …": what the server answered, the parts
/// it did not give left out.
String backendReachedLine(BackendReached check) {
  return [
    'Block ${groupThousands('${check.height}')}',
    ?check.software,
    if (check.tor) 'through Tor',
    check.millis < 1000
        ? '${check.millis} ms'
        : '${(check.millis / 1000).toStringAsFixed(1)} s',
  ].join(' · ');
}
