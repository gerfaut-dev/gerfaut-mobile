import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';

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
    final stamp = this.stamp;
    if (syncing) {
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
    if (failed) {
      final line = warned(
        LucideIcons.triangleAlert,
        stamp == null
            ? 'Sync failed'
            : 'Sync failed · last sync ${relativeTime(stamp.at)}',
      );
      final reason = this.reason;
      if (reason == null) return line;
      return Tooltip(
        message: reason,
        triggerMode: TooltipTriggerMode.longPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line,
            Text(
              reason,
              style: tokens.label.copyWith(color: tokens.textMuted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
    if (!refreshing && syncIsStale(stamp)) {
      return warned(LucideIcons.clockAlert, words);
    }
    return Text(
      words,
      style: tokens.label.copyWith(color: tokens.textMuted),
      overflow: TextOverflow.ellipsis,
    );
  }
}
