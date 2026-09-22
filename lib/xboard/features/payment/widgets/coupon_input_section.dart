import 'package:flutter/material.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';

class CouponInputSection extends StatelessWidget {
  const CouponInputSection({
    super.key,
    required this.controller,
    required this.isValidating,
    required this.onValidate,
    required this.onChanged,
    this.isValid,
    this.errorMessage,
    this.discountAmount,
  });
  final TextEditingController controller;
  final bool isValidating;
  final bool? isValid;
  final String? errorMessage;
  final double? discountAmount;
  final VoidCallback onValidate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              l10n.xboardCouponOptional,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (isValid == true && discountAmount != null)
              Text(
                '-¥${discountAmount!.toStringAsFixed(2)}',
                style: TextStyle(color: SentinelColors.of(context).success),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          enabled: !isValidating,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: l10n.xboardEnterCouponCode,
            errorText: errorMessage,
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            suffixIcon: isValid == true
                ? Icon(
                    Icons.check_circle,
                    color: SentinelColors.of(context).success,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: isValidating
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    onValidate();
                  },
            icon: isValidating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.local_offer_outlined, size: 18),
            label: Text(l10n.xboardVerify),
          ),
        ),
      ],
    );
  }
}
