import 'package:flutter/material.dart';
import 'package:fl_clash/l10n/l10n.dart';
import '../utils/price_calculator.dart';

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.periods,
    required this.selectedPeriod,
    required this.onPeriodSelected,
    this.couponType,
    this.couponValue,
  });
  final List<Map<String, dynamic>> periods;
  final String? selectedPeriod;
  final ValueChanged<String> onPeriodSelected;
  final int? couponType;
  final int? couponValue;

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).xboardSelectPaymentPeriod,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
            final count = largeText || constraints.maxWidth < 300
                ? 1
                : constraints.maxWidth >= 600
                ? 3
                : 2;
            final width = (constraints.maxWidth - (count - 1) * 12) / count;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final period in periods)
                  SizedBox(
                    width: width,
                    child: Builder(
                      builder: (context) {
                        final selected = selectedPeriod == period['period'];
                        final original =
                            (period['price'] as num?)?.toDouble() ?? 0;
                        final price = selected && couponType != null
                            ? PriceCalculator.calculateFinalPrice(
                                original,
                                couponType,
                                couponValue,
                              )
                            : original;
                        return Semantics(
                          selected: selected,
                          child: Material(
                            color: selected
                                ? scheme.primaryContainer
                                : scheme.surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: selected
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () =>
                                  onPeriodSelected(period['period'] as String),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      size: 20,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      period['label'] as String,
                                      style: TextStyle(
                                        color: selected
                                            ? scheme.onPrimaryContainer
                                            : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      PriceCalculator.formatPrice(price),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? scheme.onPrimaryContainer
                                            : scheme.primary,
                                      ),
                                    ),
                                    if (price < original)
                                      Text(
                                        PriceCalculator.formatPrice(original),
                                        style: TextStyle(
                                          decoration:
                                              TextDecoration.lineThrough,
                                          color: selected
                                              ? scheme.onPrimaryContainer
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
