import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/count_badge.dart';
import '../widgets/fitted_text.dart';
import '../widgets/load_failure.dart';
import '../widgets/motion.dart';
import '../widgets/notice.dart';
import '../widgets/status_pill.dart';
import '../widgets/toast.dart';
import '../widgets/readable_width.dart';
import '../widgets/dialog.dart';

/// Side of the small QR code in the address block; tapping it opens the
/// large one.
const double _qrSide = 140;

/// Rows an address card shows before "Show all".
const int _collapsedRows = 5;

/// How far past the next unused address the screen peeks: the core
/// derives no more upcoming addresses than this at once.
const int maxReceivePeek = 200;

/// The longest run of unused addresses, one after the other on the
/// derivation path, before the one at [position] in [entries].
///
/// This is what the gap limit counts: software that scans stops after
/// that many unused addresses in a row. The core skips an upcoming
/// address a payment already reached, so a jump in the indexes is a
/// used address, and the run starts over after it. Every address
/// before the first entry, the next unused one, is used.
int unusedInARow(List<AddressEntry> entries, int position) {
  var longest = 0;
  var run = 0;
  for (var k = 0; k < position; k++) {
    if (k > 0 && entries[k].index != entries[k - 1].index + 1) run = 0;
    run += 1;
    if (run > longest) longest = run;
  }
  return longest;
}

/// Receive: the next unused address first, with its QR code, copy with
/// explicit feedback and a way to skip ahead; then the audit of every
/// revealed address, external and change in their own cards. The whole
/// screen scrolls as one. Single-address wallets show their one address
/// and one card.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  bool _copied = false;

  /// Peek distance past the next unused address, in addresses offered:
  /// the core skips one a payment already reached, so this is not an
  /// index. Each address the screen shows is kept revealed: shown, it
  /// counts as handed out, a sync watches it, and New address never
  /// offers it again. Leaving the screen returns to the first unused one.
  int _offset = 0;

  /// What New address is doing.
  _NewAddress _newAddress = const _NewAddressIdle();

  /// Addresses already asked to be kept revealed, by wallet and index:
  /// asked once each, and again the next time one shows after a failure.
  final Set<(String, int)> _revealAsked = {};

  /// Every address shown in this visit, by wallet and index: New address
  /// passes them over before the core has kept them revealed, and even
  /// if it failed to.
  final Set<(String, int)> _shownHere = {};

  /// The address on screen, by wallet and index, and whether it was
  /// shown before it got there: revealed by an earlier visit or a sync,
  /// or seen earlier in this visit. Read once, on arrival: the screen
  /// reveals the address it shows, and that must not count.
  (String, int)? _onScreen;
  bool _shownBefore = false;

  /// The list last on screen, kept while the next one is read: a longer
  /// peek is another request, and the address stays in view meanwhile.
  List<AddressEntry>? _shown;

  @override
  void didUpdateWidget(ReceiveScreen old) {
    super.didUpdateWidget(old);
    // Another wallet: offsets are not comparable, and what New address
    // was doing concerns the one left.
    if (old.walletId != widget.walletId) {
      _offset = 0;
      _newAddress = const _NewAddressIdle();
      _shown = null;
    }
  }

  /// Moves to [offset], and New address starts over from there.
  void _moveTo(int offset) {
    setState(() {
      _offset = offset;
      _newAddress = const _NewAddressIdle();
    });
  }

  /// New address: reads every upcoming address afresh, the list asked
  /// after the press and not one cached before it.
  void _seekNewAddress() {
    ref.invalidate(
      receiveProvider((walletId: widget.walletId, lookahead: maxReceivePeek)),
    );
    setState(() => _newAddress = _NewAddressSeeking());
  }

  /// The long list is in: the screen moves to the first address past the
  /// one shown that was never revealed. None within reach: it stays, and
  /// says so.
  void _settleSeek(
    _NewAddressSeeking seek,
    List<AddressEntry> list,
    int position,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Another press, a move or a wallet switch came first.
      if (!mounted || !identical(_newAddress, seek)) return;
      var fresh = -1;
      for (var at = position + 1; at < list.length; at++) {
        if (!list[at].revealed &&
            !_shownHere.contains((widget.walletId, list[at].index))) {
          fresh = at;
          break;
        }
      }
      setState(() {
        if (fresh < 0) {
          _newAddress = const _NewAddressNone();
        } else {
          _newAddress = const _NewAddressIdle();
          _offset = fresh;
        }
      });
    });
  }

  /// On screen: kept revealed. A single address has nothing to reveal
  /// and says it was always given.
  void _keepRevealed(AddressEntry entry) {
    final key = (widget.walletId, entry.index);
    if (key != _onScreen) {
      _onScreen = key;
      _shownBefore = entry.revealed || _shownHere.contains(key);
    }
    _shownHere.add(key);
    if (entry.revealed) return;
    if (!_revealAsked.add(key)) return;
    final container = ProviderScope.containerOf(context, listen: false);
    keepReceiveAddressRevealed(container, key.$1, key.$2).catchError((_) {
      _revealAsked.remove(key);
    });
  }

  Future<void> _copy(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(Toast('Copied'));
    await Future<void>.delayed(GerfautMotion.hold);
    if (mounted) setState(() => _copied = false);
  }

  void _enlarge(String address) {
    showGerfautDialog<void>(
      context: context,
      barrierLabel: 'Close',
      builder: (_) => _QrDialog(address: address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final meta = ref.watch(snapshotProvider(widget.walletId)).value?.meta;
    final single = meta?.isSingleAddress ?? false;
    final gapLimit = meta?.gapLimit ?? 20;
    // A sync read the wallet again since none was found: a payment may
    // have freed addresses within reach, so New address comes back.
    ref.listen(snapshotProvider(widget.walletId), (before, after) {
      final reread = (before?.isLoading ?? false) && !after.isLoading;
      if (reread && _newAddress is _NewAddressNone) {
        setState(() => _newAddress = const _NewAddressIdle());
      }
    });
    // One more than the address on display: whether the core has a next
    // one to give is then known before the button is pressed. As far as
    // the screen looks while New address seeks one never shown.
    final seek = _newAddress;
    final addresses = ref.watch(
      receiveProvider((
        walletId: widget.walletId,
        lookahead: seek is _NewAddressSeeking
            ? maxReceivePeek
            : min(_offset + 1, maxReceivePeek),
      )),
    );
    final fresh = addresses.value;
    if (fresh != null) _shown = fresh;
    final list = _shown;
    final position = list == null ? 0 : min(_offset, list.length - 1);
    if (seek is _NewAddressSeeking && fresh != null && !addresses.isLoading) {
      _settleSeek(seek, fresh, position);
    }
    final entry = list == null || list.isEmpty ? null : list[position];
    if (entry != null) _keepRevealed(entry);
    // A descriptor without a wildcard has one address, and the core
    // gives it once: nothing to skip to, ever.
    final oneAddress = single || (list != null && list.length == 1);
    final hasNext =
        list != null && list.length > _offset + 1 && _offset < maxReceivePeek;
    final audit = ref.watch(addressListProvider(widget.walletId));

    return Scaffold(
      appBar: GerfautAppBar.text('Receive'),
      body: SafeArea(
        child: ReadableWidth(
          // The address page scrolls and stays out of any fade; only the
          // bounded line standing in for it fades between its states.
          child: addresses.hasError
              ? FadeInPlace(
                  state: 'error',
                  child: LoadFailure(
                    what: 'The receive address',
                    error: addresses.error,
                    onRetry: () => ref.invalidate(receiveProvider),
                  ),
                )
              : entry == null
              ? FadeInPlace(
                  state: 'loading',
                  child: Center(
                    child: Text(
                      'Deriving address…',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(GerfautSpacing.md),
                  children: [
                    _AddressBlock(
                      entry: entry,
                      single: single,
                      oneAddress: oneAddress,
                      // One address to give is always the one shown
                      // before: nothing to warn about.
                      shownBefore: !oneAddress && _shownBefore,
                      offset: _offset,
                      gap: unusedInARow(list!, min(_offset, list.length - 1)),
                      hasNext: hasNext,
                      gapLimit: gapLimit,
                      copied: _copied,
                      onCopy: () => _copy(entry.address),
                      onEnlarge: () => _enlarge(entry.address),
                      onNext: () => _moveTo(min(_offset + 1, maxReceivePeek)),
                      onFirst: () => _moveTo(0),
                      newAddress: seek,
                      onNewAddress: _seekNewAddress,
                    ),
                    const SizedBox(height: GerfautSpacing.lg),
                    ..._auditCards(tokens, audit, single, meta?.network),
                  ],
                ),
        ),
      ),
    );
  }

  /// The revealed addresses, one card per keychain.
  List<Widget> _auditCards(
    GerfautTokens tokens,
    AsyncValue<AddressList> audit,
    bool single,
    Network? network,
  ) {
    final list = audit.value;
    if (list == null && audit.hasError) {
      return [
        LoadFailure(
          what: 'The addresses',
          error: audit.error,
          centered: false,
          onRetry: () => ref.invalidate(addressListProvider(widget.walletId)),
        ),
      ];
    }
    // The network comes with the wallet, which is in hand whenever this
    // page is: an address's fiat value depends on it.
    if (list == null || network == null) {
      return [
        Text(
          'Loading addresses…',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ];
    }
    return [
      if (single)
        _AddressCard(
          title: 'Watched address',
          rows: list.external,
          network: network,
        )
      else ...[
        _AddressCard(
          title: 'External',
          hint: 'Receive addresses, in derivation order.',
          rows: list.external,
          network: network,
        ),
        const SizedBox(height: GerfautSpacing.gutter),
        _AddressCard(
          title: 'Change',
          hint: 'Internal addresses used by outgoing transactions.',
          rows: list.internal,
          network: network,
          emptyText: 'No change addresses revealed yet.',
        ),
      ],
      if (list.truncated) ...[
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'Long keychains are capped: only the first 200 addresses of each '
          'are listed.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
    ];
  }
}

/// What New address is doing.
sealed class _NewAddress {
  const _NewAddress();
}

/// Waiting for a press.
final class _NewAddressIdle extends _NewAddress {
  const _NewAddressIdle();
}

/// Reading every upcoming address for one never shown. Each press makes
/// its own: an answer for an earlier press is told apart and dropped.
final class _NewAddressSeeking extends _NewAddress {}

/// Every upcoming address within reach was shown before.
final class _NewAddressNone extends _NewAddress {
  const _NewAddressNone();
}

/// The address on offer: a small QR code beside its identity, the full
/// address in mono, the actions, and the warnings that go with it.
class _AddressBlock extends StatelessWidget {
  const _AddressBlock({
    required this.entry,
    required this.single,
    required this.oneAddress,
    required this.shownBefore,
    required this.offset,
    required this.gap,
    required this.hasNext,
    required this.gapLimit,
    required this.copied,
    required this.onCopy,
    required this.onEnlarge,
    required this.onNext,
    required this.onFirst,
    required this.newAddress,
    required this.onNewAddress,
  });

  final AddressEntry entry;
  final bool single;

  /// Only one address to give, a watched one or a descriptor without a
  /// wildcard: no way to skip ahead.
  final bool oneAddress;

  /// Shown before it reached the screen: on an earlier visit, after a
  /// restart too, or earlier in this one.
  final bool shownBefore;
  final int offset;

  /// The longest run of unused addresses before the one on offer.
  final int gap;

  /// Whether the core has another address past this one to offer.
  final bool hasNext;
  final int gapLimit;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onEnlarge;
  final VoidCallback onNext;
  final VoidCallback onFirst;

  /// What New address is doing.
  final _NewAddress newAddress;
  final VoidCallback onNewAddress;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final label = single
        ? 'WATCHED ADDRESS'
        : offset == 0
        ? 'NEXT UNUSED ADDRESS · INDEX ${entry.index}'
        : 'UNUSED ADDRESS · INDEX ${entry.index}';
    final addressStyle = tokens.data.copyWith(
      fontSize: tokens.body.fontSize,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Enlarge the address QR code',
              child: InkWell(
                borderRadius: BorderRadius.circular(GerfautRadius.lg),
                onTap: onEnlarge,
                child: _QrCard(address: entry.address, side: _qrSide),
              ),
            ),
            const SizedBox(width: GerfautSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: tokens.label.copyWith(color: tokens.textMuted),
                  ),
                  if (entry.derivation != null) ...[
                    const SizedBox(height: GerfautSpacing.sm),
                    Text(
                      'DERIVATION PATH',
                      style: tokens.label.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(entry.derivation!, style: tokens.data),
                  ],
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'Tap the code to enlarge it.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.md),
        Container(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
          ),
          child: BalancedLines(
            text: entry.address,
            style: addressStyle,
            child: SelectableText(entry.address, style: addressStyle),
          ),
        ),
        // Still the first address nobody paid, so still the one offered:
        // whoever was shown it may have kept it. Read before copying; the
        // choice is the user's, so amber, and no block.
        if (shownBefore) ...[
          const SizedBox(height: GerfautSpacing.md),
          const GerfautNotice(
            tone: NoticeTone.info,
            message:
                'This address may have been shown before. Make sure it was '
                'not already used or given to someone.',
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        PrimaryButton(
          label: copied ? 'Copied' : 'Copy address',
          icon: copied ? LucideIcons.check : LucideIcons.copy,
          expand: true,
          onPressed: onCopy,
        ),
        if (!oneAddress) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Next address',
                  icon: LucideIcons.skipForward,
                  onPressed: hasNext ? onNext : null,
                ),
              ),
              if (offset > 0) ...[
                const SizedBox(width: GerfautSpacing.sm),
                SecondaryButton(
                  label: 'First unused',
                  icon: LucideIcons.rotateCcw,
                  onPressed: onFirst,
                ),
              ],
            ],
          ),
          // With the note: the way to an address nobody was shown, for
          // whoever would rather not use this one. Not where the screen
          // can go no further, nor once it found none within reach.
          if (shownBefore && hasNext && newAddress is! _NewAddressNone) ...[
            const SizedBox(height: GerfautSpacing.sm),
            SecondaryButton(
              label: 'New address',
              icon: LucideIcons.plus,
              expand: true,
              busy: newAddress is _NewAddressSeeking,
              onPressed: onNewAddress,
            ),
          ],
          if (newAddress is _NewAddressNone) ...[
            const SizedBox(height: GerfautSpacing.sm),
            // It lands in reaction to the tap, and nothing else on the
            // screen says why the address did not change.
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                'Every address within $maxReceivePeek of the first unused '
                'one was shown before. Use one of them, or wait for a '
                'payment to free the next ones.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ),
          ],
          if (!hasNext && offset > 0) ...[
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              'Gerfaut offers at most $maxReceivePeek addresses past the '
              'next unused one.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ],
        ],
        if (!oneAddress && gap >= gapLimit) ...[
          const SizedBox(height: GerfautSpacing.md),
          // Peeking this far outruns what scanning software derives:
          // state it in the pending tint, not as an alarm.
          GerfautNotice(
            tone: NoticeTone.info,
            message:
                '$gap unused addresses in a row come before this one, '
                'beyond the gap limit of $gapLimit: other wallet software may '
                'not detect funds received here.',
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        // The one warning that must not read as small print: a
        // highlighted panel, not a muted footnote.
        const GerfautNotice(
          tone: NoticeTone.alert,
          message:
              'Verify this address on your signing device before sharing it.',
          hint:
              'Gerfaut only watches: it never holds the private keys behind '
              'it.',
        ),
      ],
    );
  }
}

/// A QR code on its white card. QR codes stay dark on light in every
/// theme: scanners expect it.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.address, required this.side});

  final String address;
  final double side;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      width: side,
      height: side,
      padding: const EdgeInsets.all(GerfautSpacing.sm),
      decoration: BoxDecoration(
        color: GerfautQr.background,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: QrImageView(
        data: address,
        backgroundColor: GerfautQr.background,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: GerfautQr.foreground,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: GerfautQr.foreground,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// The QR code at a size a camera reads from across a table, on a
/// white card over the dimmed page. A tap anywhere, Escape or back
/// closes it.
class _QrDialog extends StatelessWidget {
  const _QrDialog({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // The lines under the code keep their room: the address, up to
    // three lines, and the way out.
    const under = 160.0;
    final side = max(
      120.0,
      min(size.width, size.height - under) - 2 * GerfautSpacing.xl,
    );
    final addressStyle = GerfautTokens.dark.data.copyWith(
      color: GerfautTokens.dark.text,
      decoration: TextDecoration.none,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          button: true,
          label: 'Close the address QR code',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QrCard(address: address, side: side),
                  const SizedBox(height: GerfautSpacing.md),
                  // The address under its code, whole, as on the desktop
                  // app: whoever scans it can compare both ends with
                  // what their screen shows.
                  SizedBox(
                    width: side,
                    child: BalancedLines(
                      text: address,
                      style: addressStyle,
                      alignment: Alignment.center,
                      child: Text(
                        address,
                        textAlign: TextAlign.center,
                        style: addressStyle,
                      ),
                    ),
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  Text(
                    'Tap anywhere to close',
                    // The line sits on the dimmed barrier in both themes:
                    // the dark theme's text is the one that reads on it.
                    style: GerfautTokens.dark.bodySmall.copyWith(
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One keychain: a card with its label, a hint, the first rows and a
/// way to unfold the rest. Each card unfolds on its own.
class _AddressCard extends StatefulWidget {
  const _AddressCard({
    required this.title,
    required this.rows,
    required this.network,
    this.hint,
    this.emptyText,
  });

  final String title;

  /// What the keychain is, when its name alone does not say.
  final String? hint;
  final List<AddressRow> rows;
  final Network network;

  /// Shown in place of the rows when the keychain has none.
  final String? emptyText;

  @override
  State<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends State<_AddressCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final rows = widget.rows;
    final indexSlot = _indexSlot(context, tokens, _indexDigits(rows));
    final shown = _expanded ? rows : rows.take(_collapsedRows).toList();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: tokens.label.copyWith(color: tokens.textMuted),
                    ),
                    if (rows.isNotEmpty) ...[
                      const SizedBox(width: GerfautSpacing.xs),
                      CountBadge(count: rows.length),
                    ],
                  ],
                ),
                if (widget.hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.hint!,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: GerfautSpacing.sm),
          if (rows.isEmpty && widget.emptyText != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GerfautSpacing.md,
              ),
              child: Text(
                widget.emptyText!,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            )
          else
            for (final row in shown) ...[
              Divider(height: 1, thickness: 1, color: tokens.border),
              _AddressRowTile(
                row: row,
                network: widget.network,
                indexSlot: indexSlot,
              ),
            ],
          if (rows.length > _collapsedRows) ...[
            Divider(height: 1, thickness: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.only(
                left: GerfautSpacing.sm,
                top: GerfautSpacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DisclosureButton(
                  label: _expanded ? 'Show less' : 'Show all ${rows.length}',
                  open: _expanded,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How many digits the longest index of [rows] has, two at least.
int _indexDigits(List<AddressRow> rows) {
  var widest = 2;
  for (final row in rows) {
    final digits = '${row.index}'.length;
    if (digits > widest) widest = digits;
  }
  return widest;
}

/// The width of the index column: [digits] digits in the figure style
/// at the text size in force, and the gap before the address; 36 at
/// least, the slot it had at the default size.
double _indexSlot(BuildContext context, GerfautTokens tokens, int digits) {
  final painter = TextPainter(
    text: TextSpan(text: '0' * digits, style: tokens.figureOf()),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width + GerfautSpacing.sm;
  painter.dispose();
  return width < 36 ? 36 : width;
}

/// One revealed address: index, chip, usage, balance. Never shorter than
/// a touch target.
class _AddressRowTile extends StatelessWidget {
  const _AddressRowTile({
    required this.row,
    required this.network,
    required this.indexSlot,
  });

  final AddressRow row;
  final Network network;

  /// Width of the index column, measured once for the whole list.
  final double indexSlot;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: GerfautTouch.target),
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm,
      ),
      child: Row(
        children: [
          // The derivation index anchors the row; a slot of one width
          // keeps the address column aligned. It is measured for the
          // longest index of the list at the text size in force, so an
          // index stays on one line at any size and the address keeps
          // the rest.
          SizedBox(
            width: indexSlot,
            child: Text(
              '${row.index}',
              style: tokens.figureOf(color: tokens.textMuted),
            ),
          ),
          Expanded(child: AddressChip(value: row.address, head: 8, tail: 6)),
          const SizedBox(width: GerfautSpacing.sm),
          AddressStatePill(used: row.used),
          const SizedBox(width: GerfautSpacing.sm),
          if (row.balanceSats > 0)
            StackedAmount(sats: row.balanceSats, network: network)
          else
            Text('—', style: tokens.figureOf(color: tokens.textMuted)),
        ],
      ),
    );
  }
}
