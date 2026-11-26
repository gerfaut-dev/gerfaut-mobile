import 'package:flutter/material.dart';

import '../src/models.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'dialog.dart';
import 'focus_ring.dart';
import 'icon_chip.dart';
import 'wallet_icon.dart';

/// The title of a wallet's page: the wallet's icon in the chip its home
/// card wears, then its name. Two targets side by side, neither drawn
/// as a button: the icon opens the picker the settings open, the name
/// opens the rename dialog. What says so is the ink under the finger
/// and the label read out loud.
///
/// The name carries the page's heading itself: the bar that holds this
/// title has to leave its own out ([GerfautAppBar.titleNamesItself]).
///
/// Neither waits for a sync: both write a field of the wallet's own,
/// which a sync never writes back over, and an icon that answered
/// nothing for the length of a first sync would look broken.
class WalletTitle extends StatelessWidget {
  const WalletTitle({super.key, required this.wallet, required this.onRename});

  /// Null until the wallet has loaded: nothing to show or change yet.
  final WalletMeta? wallet;

  /// Opens the rename dialog on the current name.
  final ValueChanged<String> onRename;

  /// The chip's own room inside its target, on either side.
  static const double _chipInset = (GerfautTouch.target - IconChip.side) / 2;

  @override
  Widget build(BuildContext context) {
    final wallet = this.wallet;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wallet != null) ...[
            _IconTarget(wallet: wallet),
            // The home card's gap between the chip and the name, less
            // what the target already leaves beside the chip.
            const SizedBox(width: GerfautSpacing.gutter - _chipInset),
          ],
          // A long name gives way to its ellipsis, never the icon.
          Flexible(
            child: _NameTarget(name: wallet?.name, onRename: onRename),
          ),
        ],
      ),
    );
  }
}

class _IconTarget extends StatelessWidget {
  const _IconTarget({required this.wallet});

  final WalletMeta wallet;

  Future<void> _change(BuildContext context) {
    return changeWalletIcon(
      context,
      wallet,
      onFailure: (message) => showGerfautDialog<void>(
        context: context,
        builder: (_) => _IconFailureDialog(message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // Read as the glyph worn, then what a tap does: "Snowflake, Change
    // this wallet's icon". The tooltip is that second part; a label of
    // its own would say it twice.
    return Semantics(
      button: true,
      child: Tooltip(
        message: "Change this wallet's icon",
        child: FocusRing(
          child: InkWell(
            borderRadius: BorderRadius.circular(GerfautRadius.md),
            // The ring says where the focus is; a tint would say it
            // twice.
            focusColor: Colors.transparent,
            onTap: () => _change(context),
            child: SizedBox.square(
              dimension: GerfautTouch.target,
              child: Center(
                // Neutral ink, as on the home card: the accent is for
                // what is selected, and this is the wallet's mark.
                child: IconChip.glyph(
                  glyph: WalletGlyph(
                    wallet.icon,
                    semanticLabel: wallet.icon.label,
                  ),
                  ink: tokens.textMuted,
                  fill: tokens.surfaceSunken,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NameTarget extends StatelessWidget {
  const _NameTarget({required this.name, required this.onRename});

  final String? name;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final name = this.name;
    // The page's heading and its name, as the bar's own title would be:
    // read when the page opens, and reached by heading navigation. Put
    // here rather than around the whole title, which the icon shares.
    return Semantics(
      header: true,
      namesRoute: true,
      button: true,
      child: Tooltip(
        // The tooltip is the label a screen reader reads out after the
        // name: a second Semantics label would say it twice.
        message: 'Rename this wallet',
        child: InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.md),
          onTap: name == null ? null : () => onRename(name),
          // No padding of its own: the name starts where the icon's
          // target ends, or against the back arrow while there is none.
          child: Container(
            constraints: const BoxConstraints(minHeight: GerfautTouch.target),
            alignment: Alignment.centerLeft,
            child: Text(
              name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// What the core said when it refused the icon. Not a toast: an error
/// does not go away by itself.
class _IconFailureDialog extends StatelessWidget {
  const _IconFailureDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      // The core's words can run long at a large text size.
      scrollable: true,
      title: Text('Icon not saved', style: tokens.h2),
      content: Text(message, style: tokens.bodySmall),
      actions: [
        PrimaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
