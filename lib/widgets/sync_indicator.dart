import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import 'motion.dart';

/// How old a sync may get before the line that dates it says so. An
/// open app syncs every ten minutes: past thirty, three of those syncs
/// were missed, and the line turns amber behind a clock rather than
/// pass for fresh.
const Duration syncStaleAfter = Duration(minutes: 30);

/// Whether [stamp] is older than [syncStaleAfter].
bool syncIsStale(SyncStamp stamp, {DateTime? now}) =>
    stamp.olderThan(syncStaleAfter, now: now ?? DateTime.now());

/// Data freshness, always visible. While syncing, the last known sync
/// stays on screen, never a spinner alone, never a shimmer. A failed
/// sync is stated with its reason: silence would look like health. A
/// sync that is old says so in amber, behind a clock: a date alone
/// would leave the reader to do the sum.
class SyncIndicator extends ConsumerWidget {
  /// The line of one wallet: a failure is said with its reason, [error].
  const SyncIndicator({
    super.key,
    required this.stamp,
    required this.syncing,
    String? error,
    this.refreshing = false,
  }) : failed = error != null,
       reason = error;

  /// The line of a list of wallets, each with a card of its own: a
  /// failure is said, and its reason stays on the card of its wallet.
  const SyncIndicator.brief({
    super.key,
    required this.stamp,
    required this.syncing,
    required this.failed,
    this.refreshing = false,
  }) : reason = null;

  final SyncStamp? stamp;
  final bool syncing;

  /// What [stamp] came with is being read again: a sync that just ended
  /// has a newer one on its way, and an old stamp is not called old
  /// until the read lands. A failure is said all the same.
  final bool refreshing;

  /// The last sync failed.
  final bool failed;

  /// Why it failed. It shows under the line, on three lines at most:
  /// Gerfaut's own sentences fit, such as the one for a false proof,
  /// and a server's long words are cut. Long-press shows it in full.
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "5 min ago" moves on its own, while the page stays open.
    ref.watch(relativeClockProvider);
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final reason = failed && !syncing ? this.reason : null;
    final kind = _kind();
    // The line fades when what it says changes kind (syncing, synced,
    // failed, old), never when only its words move: "2 min ago" turning
    // into "3 min ago" is the same state and is replaced in place.
    final words = _line(tokens, kind);
    final line = FadeInPlace(
      state: kind,
      child: reason == null ? words : _fullOnLongPress(reason, words),
    );
    // The reason opens its own place under the line, so the rows below
    // move down with it rather than in one jump.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        OpeningPlace(
          child: reason == null
              ? null
              : _fullOnLongPress(
                  reason,
                  Text(
                    reason,
                    style: tokens.label.copyWith(color: tokens.textMuted),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
      ],
    );
  }

  /// Long-press on the line or on the reason shows the reason in full.
  /// Each carries its own tooltip, inside its own animated place: one
  /// tooltip around both would give the line a new parent the moment a
  /// reason arrives, and the line would cut instead of fading.
  Widget _fullOnLongPress(String reason, Widget child) => Tooltip(
    message: reason,
    triggerMode: TooltipTriggerMode.longPress,
    child: child,
  );

  _SyncKind _kind() {
    final stamp = this.stamp;
    if (syncing) return _SyncKind.syncing;
    if (failed) return _SyncKind.failed;
    if (stamp == null) return _SyncKind.never;
    if (!refreshing && syncIsStale(stamp)) return _SyncKind.stale;
    return _SyncKind.synced;
  }

  Widget _line(GerfautTokens tokens, _SyncKind kind) {
    final stamp = this.stamp;
    if (kind == _SyncKind.syncing) {
      return Text(
        stamp == null
            ? syncingWords
            : '$syncingWords last sync ${relativeTime(stamp.at)}',
        style: tokens.label.copyWith(color: tokens.textMuted),
        overflow: TextOverflow.ellipsis,
      );
    }
    // Amber behind a glyph: the colour never says it alone.
    Widget warned(IconData icon, String words) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: tokens.pending),
        const SizedBox(width: GerfautSpacing.xs),
        Flexible(
          child: Text(
            words,
            style: tokens.label.copyWith(color: tokens.pending),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (kind == _SyncKind.failed) {
      return warned(
        LucideIcons.triangleAlert,
        stamp == null
            ? 'Sync failed'
            : 'Sync failed · last sync ${relativeTime(stamp.at)}',
      );
    }
    if (stamp == null) {
      return Text(
        'Never synced',
        style: tokens.label.copyWith(color: tokens.textMuted),
        overflow: TextOverflow.ellipsis,
      );
    }
    final words = 'Synced ${relativeTime(stamp.at)} · ${stamp.backend}';
    if (kind == _SyncKind.stale) {
      return warned(LucideIcons.clockAlert, words);
    }
    return Text(
      words,
      style: tokens.label.copyWith(color: tokens.textMuted),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// What the line says, as far as its fade is concerned: a new kind
/// fades in, the same kind with newer words does not.
enum _SyncKind { syncing, synced, never, failed, stale }
