import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import 'drawn_wallet_glyphs.dart';
import 'facts.dart';
import 'focus_ring.dart';
import 'stroke_glyph.dart';
import 'toast.dart';

/// Where a wallet icon's drawing comes from: Lucide for the symbols,
/// a stroked path of this app for the signing devices Lucide has none
/// of.
sealed class WalletGlyphSource {
  const WalletGlyphSource();
}

/// A glyph of the Lucide font.
final class LucideGlyph extends WalletGlyphSource {
  const LucideGlyph(this.data);

  final IconData data;
}

/// A glyph drawn for this app, in Lucide's grammar.
final class DrawnGlyph extends WalletGlyphSource {
  const DrawnGlyph(this.path);

  /// The drawing, in [StrokeGlyph]'s 24 unit box.
  final Path path;
}

/// The drawing behind each wallet icon. The switch is exhaustive, so
/// an icon the core adds does not build until it is drawn here.
WalletGlyphSource walletGlyphSource(WalletIcon icon) {
  return switch (icon) {
    WalletIcon.wallet => const LucideGlyph(LucideIcons.wallet),
    WalletIcon.key => const LucideGlyph(LucideIcons.key),
    WalletIcon.shield => const LucideGlyph(LucideIcons.shield),
    WalletIcon.mapPin => const LucideGlyph(LucideIcons.mapPin),
    WalletIcon.snowflake => const LucideGlyph(LucideIcons.snowflake),
    WalletIcon.landmark => const LucideGlyph(LucideIcons.landmark),
    WalletIcon.piggyBank => const LucideGlyph(LucideIcons.piggyBank),
    WalletIcon.swivelKey => DrawnGlyph(DrawnWalletGlyphs.swivelKey),
    WalletIcon.slimStick => DrawnGlyph(DrawnWalletGlyphs.slimStick),
    WalletIcon.usbStick => DrawnGlyph(DrawnWalletGlyphs.usbStick),
    WalletIcon.twoButtonDevice => DrawnGlyph(DrawnWalletGlyphs.twoButtonDevice),
    WalletIcon.squareTouchscreen => DrawnGlyph(
      DrawnWalletGlyphs.squareTouchscreen,
    ),
    WalletIcon.wheelDevice => DrawnGlyph(DrawnWalletGlyphs.wheelDevice),
    WalletIcon.pocketScreen => DrawnGlyph(DrawnWalletGlyphs.pocketScreen),
    WalletIcon.wideScreenBar => DrawnGlyph(DrawnWalletGlyphs.wideScreenBar),
    WalletIcon.curvedSlate => DrawnGlyph(DrawnWalletGlyphs.curvedSlate),
    WalletIcon.framedSlate => DrawnGlyph(DrawnWalletGlyphs.framedSlate),
    WalletIcon.keypadBar => DrawnGlyph(DrawnWalletGlyphs.keypadBar),
    WalletIcon.calculator => DrawnGlyph(DrawnWalletGlyphs.calculator),
    WalletIcon.keyboardDevice => DrawnGlyph(DrawnWalletGlyphs.keyboardDevice),
    WalletIcon.touchPhone => DrawnGlyph(DrawnWalletGlyphs.touchPhone),
    WalletIcon.airGappedPhone => DrawnGlyph(DrawnWalletGlyphs.airGappedPhone),
    WalletIcon.screenCard => DrawnGlyph(DrawnWalletGlyphs.screenCard),
    WalletIcon.nfcCard => DrawnGlyph(DrawnWalletGlyphs.nfcCard),
    WalletIcon.chipCard => DrawnGlyph(DrawnWalletGlyphs.chipCard),
    WalletIcon.cardSet => DrawnGlyph(DrawnWalletGlyphs.cardSet),
    WalletIcon.deviceWithCards => DrawnGlyph(DrawnWalletGlyphs.deviceWithCards),
    WalletIcon.nfcPaddle => DrawnGlyph(DrawnWalletGlyphs.nfcPaddle),
    WalletIcon.fingerprintPebble => DrawnGlyph(
      DrawnWalletGlyphs.fingerprintPebble,
    ),
    WalletIcon.cameraStick => DrawnGlyph(DrawnWalletGlyphs.cameraStick),
    WalletIcon.joystickBoard => DrawnGlyph(DrawnWalletGlyphs.joystickBoard),
    WalletIcon.scannerBoard => DrawnGlyph(DrawnWalletGlyphs.scannerBoard),
  };
}

/// A wallet's icon, whichever way it is drawn. Size and colour come
/// from the surrounding [IconTheme] unless set, as they do for [Icon].
class WalletGlyph extends StatelessWidget {
  const WalletGlyph(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final WalletIcon icon;

  /// Falls back to the ambient icon theme.
  final double? size;

  /// Falls back to the ambient icon theme.
  final Color? color;

  /// Said out loud when no text beside the glyph names it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return switch (walletGlyphSource(icon)) {
      LucideGlyph(:final data) => Icon(
        data,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      ),
      DrawnGlyph(:final path) => StrokeGlyph(
        path,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      ),
    };
  }
}

/// Offers the wallet icons for [wallet] and stores the one picked: the
/// one way a wallet's icon changes, wherever it is asked from. Every
/// view that wears the glyph is read again with it, the home card and
/// the wallet's own page included, and a saved change is confirmed.
///
/// Nothing is written when the picker is dismissed or the glyph already
/// worn is picked. [onSaving] runs once a new one is on its way;
/// [onFailure] gets what the core said when it refused, for the screen
/// to show where it shows its other errors.
Future<void> changeWalletIcon(
  BuildContext context,
  WalletMeta wallet, {
  VoidCallback? onSaving,
  required void Function(String message) onFailure,
}) async {
  final chosen = await WalletIconPicker.show(context, current: wallet.icon);
  if (chosen == null || chosen == wallet.icon || !context.mounted) return;
  onSaving?.call();
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(bridgeProvider).setWalletIcon(wallet.id, chosen);
    container.invalidate(walletsProvider);
    container.invalidate(snapshotProvider(wallet.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(Toast('Setting saved'));
    }
  } catch (error) {
    if (context.mounted) onFailure('$error');
  }
}

/// Picks the glyph a wallet shows beside its name: the symbols, then
/// the signing devices, each section a grid under its heading, the
/// current one outlined in the accent. Tapping one answers and closes;
/// tapping outside answers nothing.
class WalletIconPicker extends StatelessWidget {
  const WalletIconPicker({super.key, required this.current});

  /// Opens the picker over [context]. Null when it was dismissed.
  static Future<WalletIcon?> show(
    BuildContext context, {
    required WalletIcon current,
  }) {
    return showModalBottomSheet<WalletIcon>(
      context: context,
      // Free of the default cap at nine sixteenths of the screen: the
      // sheet sets its own, [maxHeightFactor].
      isScrollControlled: true,
      builder: (_) => WalletIconPicker(current: current),
    );
  }

  /// A tile is a comfortable target, past the touch target floor.
  static const double tileSize = 56;

  /// How much of the screen the sheet may take: the tiles do not all
  /// fit on a small phone, and past this they scroll.
  static const double maxHeightFactor = 0.85;

  final WalletIcon current;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final media = MediaQuery.of(context);
    bool drawn(WalletIcon icon) => walletGlyphSource(icon) is DrawnGlyph;
    void pick(WalletIcon icon) => Navigator.of(context).pop(icon);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: media.size.height * maxHeightFactor,
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: GerfautSpacing.md,
          right: GerfautSpacing.md,
          top: GerfautSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The title stays put while the tiles scroll under it.
            Text('Wallet icon', style: tokens.h2),
            const SizedBox(height: GerfautSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                // Past the keyboard, and past the gesture bar: the last
                // row of tiles has to clear both to be tapped.
                padding: EdgeInsets.only(
                  bottom:
                      media.viewInsets.bottom +
                      media.padding.bottom +
                      GerfautSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconSection(
                      title: 'Symbols',
                      icons: [
                        for (final icon in WalletIcon.values)
                          if (!drawn(icon)) icon,
                      ],
                      current: current,
                      onPick: pick,
                    ),
                    const SizedBox(height: GerfautSpacing.lg),
                    _IconSection(
                      title: 'Devices',
                      icons: [
                        for (final icon in WalletIcon.values)
                          if (drawn(icon)) icon,
                      ],
                      current: current,
                      onPick: pick,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One section of the picker: its heading, then its tiles in the
/// core's order.
class _IconSection extends StatelessWidget {
  const _IconSection({
    required this.title,
    required this.icons,
    required this.current,
    required this.onPick,
  });

  final String title;
  final List<WalletIcon> icons;
  final WalletIcon current;
  final ValueChanged<WalletIcon> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A heading for a screen reader too, said as the word rather
        // than spelled out in capitals.
        Semantics(
          header: true,
          label: title,
          excludeSemantics: true,
          child: FieldLabel(title, tokens: tokens),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Wrap(
          spacing: GerfautSpacing.sm,
          runSpacing: GerfautSpacing.sm,
          children: [
            for (final icon in icons)
              if (icon == current)
                _InView(
                  child: _IconTile(
                    icon: icon,
                    selected: true,
                    onTap: () => onPick(icon),
                  ),
                )
              else
                _IconTile(
                  icon: icon,
                  selected: false,
                  onTap: () => onPick(icon),
                ),
          ],
        ),
      ],
    );
  }
}

/// Scrolls its child into view once the sheet has opened: the current
/// icon may sit past the fold on a small phone, and the sheet opens at
/// its top.
class _InView extends StatefulWidget {
  const _InView({required this.child});

  final Widget child;

  @override
  State<_InView> createState() => _InViewState();
}

class _InViewState extends State<_InView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.ensureVisible(context, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One choice of the grid. The outline says which one is on, and so
/// does the announced state: an outline is not heard. The tap is on the
/// semantics node itself: with the child's excluded, a screen reader
/// has no other way to activate the tile.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final WalletIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: icon.label,
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        child: InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.md),
          focusColor: Colors.transparent,
          onTap: onTap,
          child: Container(
            width: WalletIconPicker.tileSize,
            height: WalletIconPicker.tileSize,
            decoration: BoxDecoration(
              color: selected ? tokens.surfaceSunken : tokens.surface,
              borderRadius: BorderRadius.circular(GerfautRadius.md),
              border: Border.all(
                color: selected ? tokens.primary : tokens.border,
                width: selected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: WalletGlyph(
              icon,
              size: 24,
              color: selected ? tokens.primary : tokens.text,
            ),
          ),
        ),
      ),
    );
  }
}
