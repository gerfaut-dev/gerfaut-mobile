import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/format.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/price_credit.dart';
import '../../widgets/buttons.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/facts.dart';
import '../../widgets/notice.dart';
import '../../widgets/section_card.dart';
import '../../widgets/select_field.dart';
import '../../widgets/setting_switch.dart';

/// The General section: how amounts are shown, and which theme the app
/// wears. Two cards, Display and Appearance.
class GeneralSection extends ConsumerWidget {
  const GeneralSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final currency = ref.watch(fiatCurrencyProvider);
    // What is on offer, in the core's order: the currencies with the
    // sources that quote each, and the sources by name.
    final table = ref.watch(priceTableProvider).value;
    final chosen = table?.entryOf(currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          icon: LucideIcons.coins,
          title: 'Display',
          children: [
            FieldLabel('Unit', tokens: tokens),
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              'Applies to every amount in the app.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            ChoiceGroup<AmountUnit>(
              label: 'Unit',
              value: ref.watch(unitProvider),
              options: [
                for (final unit in AmountUnit.values)
                  ChoiceOption(value: unit, label: unit.label),
              ],
              onChanged: (unit) => ref.read(unitProvider.notifier).set(unit),
            ),
            const SizedBox(height: GerfautSpacing.md),
            SettingSwitch(
              title: 'Fiat value',
              hint: 'Shows the fiat value next to every amount.',
              value: ref.watch(fiatEnabledProvider),
              onChanged: (value) =>
                  ref.read(fiatEnabledProvider.notifier).set(value),
            ),
            if (ref.watch(fiatEnabledProvider)) ...[
              const SizedBox(height: GerfautSpacing.md),
              FieldLabel('Currency', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              _CurrencyField(
                table: table,
                selected: currency,
                // The core keeps the source able to quote it: only
                // CoinGecko serves the currencies past the common seven.
                onChanged: (currency) =>
                    ref.read(fiatCurrencyProvider.notifier).set(currency),
              ),
              const SizedBox(height: GerfautSpacing.md),
              FieldLabel('Price source', tokens: tokens),
              const SizedBox(height: GerfautSpacing.xs),
              Text(
                'Serves the fiat value and the overview price.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              ChoiceGroup<PriceSource>(
                label: 'Price source',
                value: ref.watch(fiatSourceProvider),
                options: [
                  for (final entry in table?.sources ?? const <SourceEntry>[])
                    ChoiceOption(
                      value: entry.source,
                      label: entry.label,
                      // A source that does not quote the currency is
                      // shown as unavailable, never silently broken.
                      enabled: chosen?.sources.contains(entry.source) ?? false,
                    ),
                ],
                onChanged: (source) =>
                    ref.read(fiatSourceProvider.notifier).set(source),
              ),
              if (chosen?.reach == CurrencyReach.coingeckoOnly) ...[
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'CoinGecko is the only source that quotes '
                  '${currency.code}.',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
              const SizedBox(height: GerfautSpacing.sm),
              _RatePreview(tokens: tokens),
            ],
          ],
        ),
        SectionCard(
          icon: LucideIcons.sunMoon,
          title: 'Appearance',
          children: [
            FieldLabel('Theme', tokens: tokens),
            const SizedBox(height: GerfautSpacing.sm),
            ChoiceGroup<ThemePref>(
              label: 'Theme',
              value: ref.watch(themeProvider),
              options: [
                for (final pref in ThemePref.values)
                  ChoiceOption(
                    value: pref,
                    label: pref.label,
                    icon: _themeIcons[pref],
                  ),
              ],
              onChanged: (pref) => ref.read(themeProvider.notifier).set(pref),
            ),
          ],
        ),
      ],
    );
  }
}

/// Glyph shown before each theme option; the label stays the semantic
/// text.
const Map<ThemePref, IconData> _themeIcons = {
  ThemePref.light: LucideIcons.sun,
  ThemePref.dark: LucideIcons.moon,
  ThemePref.system: LucideIcons.monitor,
};

/// The display currency, every one the core lists: the ones every
/// source quotes first, then the ones CoinGecko alone serves, each group
/// announced.
class _CurrencyField extends StatelessWidget {
  const _CurrencyField({
    required this.table,
    required this.selected,
    required this.onChanged,
  });

  /// Null until the core answered.
  final PriceTable? table;
  final FiatCurrency selected;
  final ValueChanged<FiatCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return GerfautSelect<FiatCurrency>(
      label: 'Display currency',
      value: selected,
      groups: [
        for (final reach in CurrencyReach.values)
          GerfautSelectGroup(
            label: reach == CurrencyReach.every
                ? 'Every source'
                : 'CoinGecko only',
            items: [
              for (final entry in table?.currencies ?? const <CurrencyEntry>[])
                if (entry.reach == reach)
                  // The ISO code, then its name so thirty codes stay
                  // readable.
                  GerfautSelectItem(
                    value: entry.currency,
                    title: entry.currency.code,
                    subtitle: entry.name,
                  ),
            ],
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// The price under the source picker: the rate and its age, and, once
/// the source keeps failing, a note that says why and what happens to
/// the amounts meanwhile.
class _RatePreview extends ConsumerStatefulWidget {
  const _RatePreview({required this.tokens});

  final GerfautTokens tokens;

  @override
  ConsumerState<_RatePreview> createState() => _RatePreviewState();
}

class _RatePreviewState extends ConsumerState<_RatePreview> {
  bool _trying = false;

  Future<void> _retry() async {
    setState(() => _trying = true);
    try {
      await ref.read(priceProvider.notifier).retry();
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final price = ref.watch(priceProvider);
    // The age of a kept quote and the wait of a rate limit both move
    // with the clock.
    ref.watch(relativeClockProvider);
    // A failure of the bridge itself vouches for no reading: said as
    // the wait for one, which the next minute asks again.
    final reading = price.hasError ? null : price.value;
    final quote = reading?.quote;
    final trouble = reading?.trouble;
    final Widget? rate = quote == null
        // The rate on screen is the source's: the screen credits it.
        ? null
        : CreditMark(
            source: quote.source,
            child: Text(
              '1 BTC = ${formatFiatPrice(quote.rate, quote.currency)} · '
              'updated ${relativeTime(quote.at)}',
              style: tokens.figureOf(color: tokens.textMuted),
            ),
          );
    // A single failure is not said: the next ask usually mends it.
    if (trouble == null || !trouble.lasting) {
      return rate ??
          Text(
            'Fetching the current price…',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          );
    }
    final note = GerfautNotice(
      tone: NoticeTone.info,
      message: _troubleText(
        trouble,
        kept: quote != null,
        table: ref.watch(priceTableProvider).value,
        source: ref.watch(fiatSourceProvider),
        currency: ref.watch(fiatCurrencyProvider),
      ),
      // A rate limit is the source's own wait: asking sooner only
      // prolongs it, so there is nothing to try.
      action: trouble.kind == TroubleKind.rateLimited
          ? null
          : SecondaryButton(
              label: _trying ? 'Trying…' : 'Try again',
              onPressed: _trying ? null : _retry,
            ),
      actionsBelow: true,
    );
    if (rate == null) return note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: rate),
        const SizedBox(height: GerfautSpacing.sm),
        note,
      ],
    );
  }
}

/// What the note says of a lasting [trouble]: what is wrong, what the
/// amounts do meanwhile, and what comes next.
String _troubleText(
  PriceTrouble trouble, {
  required bool kept,
  required PriceTable? table,
  required PriceSource source,
  required FiatCurrency currency,
}) {
  String labelOf(PriceSource of) {
    for (final entry in table?.sources ?? const <SourceEntry>[]) {
      if (entry.source == of) return entry.label;
    }
    return 'The price source';
  }

  final name = labelOf(source);
  final what = switch (trouble.kind) {
    TroubleKind.rateLimited =>
      '$name is limiting requests from this '
          'connection.',
    TroubleKind.unreachable => '$name is not answering.',
    TroubleKind.refused => '$name refused the request.',
    TroubleKind.tor => 'Tor is not available, so no price was asked.',
  };
  final until = trouble.kind == TroubleKind.tor
      ? 'until Tor is back.'
      : 'until it answers.';
  final meanwhile = kept
      ? 'Amounts use the last price $until'
      : 'Amounts show without fiat $until';
  final String? next;
  if (trouble.kind == TroubleKind.rateLimited) {
    final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final wait = trouble.nextTry - nowSecs;
    next = wait < 60
        ? 'Gerfaut asks again in a minute.'
        : 'Gerfaut asks again in ${(wait + 59) ~/ 60} min.';
  } else if (trouble.kind != TroubleKind.tor) {
    final other = table
        ?.entryOf(currency)
        ?.sources
        .where((s) => s != source)
        .firstOrNull;
    next = other == null ? null : 'You can also switch to ${labelOf(other)}.';
  } else {
    next = null;
  }
  return [what, meanwhile, ?next].join(' ');
}
