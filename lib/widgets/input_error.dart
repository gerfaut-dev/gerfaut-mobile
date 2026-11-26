import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// What was refused in a field, under it: in the text colour with its
/// glyph, never the grey of a hint, and never red, which is kept for
/// what happens on chain. Said aloud as it appears. The desktop app's
/// `InputError`, for a wallet or a transaction the core will not read.
class InputError extends StatelessWidget {
  const InputError(this.headline, {super.key, this.detail});

  /// The sentence: what was refused.
  final String headline;

  /// The words under it, when the sentence has a reason apart.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final detail = this.detail;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.circleAlert, size: 16, color: tokens.text),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: tokens.bodySmall.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: tokens.bodySmall.copyWith(
                      fontSize: 12,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
