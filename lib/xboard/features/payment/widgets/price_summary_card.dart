import 'package:flutter/material.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';
import '../utils/price_calculator.dart';

class PriceSummaryCard extends StatelessWidget {
  const PriceSummaryCard({
    super.key,
    required this.originalPrice,
    this.finalPrice,
    this.discountAmount,
    this.userBalance,
  });
  final double originalPrice;
  final double? finalPrice;
  final double? discountAmount;
  final double? userBalance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final price = finalPrice ?? originalPrice;
    final balance = (userBalance ?? 0).clamp(0.0, double.infinity);
    final applied = balance.clamp(0.0, price);
    Widget row(
      String label,
      double value, {
      bool discount = false,
      bool total = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 20,
        runSpacing: 6,
        children: [
          Text(
            label,
            style: total ? Theme.of(context).textTheme.titleMedium : null,
          ),
          Text(
            '${discount ? '-' : ''}${PriceCalculator.formatPrice(value)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: total ? 28 : 15,
              color: total
                  ? Theme.of(context).colorScheme.primary
                  : discount
                  ? SentinelColors.of(context).success
                  : null,
            ),
          ),
        ],
      ),
    );
    return SentinelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((discountAmount ?? 0) > 0) ...[
            row(l10n.sentinelOriginalPrice, originalPrice),
            row(l10n.sentinelDiscount, discountAmount!, discount: true),
          ],
          if (applied > 0)
            row(l10n.sentinelBalanceDeduction, applied, discount: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),
          row(l10n.sentinelTotal, price - applied, total: true),
          if (balance > price)
            row(l10n.sentinelRemainingBalance, balance - price),
        ],
      ),
    );
  }
}
