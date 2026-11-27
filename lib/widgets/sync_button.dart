import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'motion.dart';

/// The sync action in an app bar: the arrows turn while the sync runs.
///
/// A greyed out button says the action is unavailable, which is not the
/// news here: the news is that work is under way. So the icon keeps its
/// full colour and turns instead. The movement is never the only
/// channel, the freshness line says "Syncing…" in words at the same
/// time, and a device asking for less motion gets the still icon.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.syncing, required this.onPressed});

  final bool syncing;

  /// Ignored while [syncing]: a second sync would only queue behind the
  /// first one. Null when there is nothing to sync at all.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return IconButton(
      tooltip: syncing ? 'Syncing…' : 'Sync',
      onPressed: syncing ? null : onPressed,
      style: IconButton.styleFrom(
        foregroundColor: tokens.text,
        // Busy is not unavailable: while it turns the icon keeps its
        // colour, and only a button with nothing to sync greys out.
        disabledForegroundColor: syncing ? tokens.text : tokens.textMuted,
      ),
      icon: TurningIcon(
        turning: syncing,
        icon: LucideIcons.refreshCw,
        size: 20,
      ),
    );
  }
}
