import 'dart:async';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/theme/sentinel_assets.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentGatewayPage extends StatefulWidget {
  const PaymentGatewayPage({
    super.key,
    required this.paymentUrl,
    required this.tradeNo,
    this.orderApi,
    this.launchPayment,
  });
  final String paymentUrl;
  final String tradeNo;
  final OrderApi? orderApi;
  final Future<bool> Function(Uri)? launchPayment;

  @override
  State<PaymentGatewayPage> createState() => _PaymentGatewayPageState();
}

class _PaymentGatewayPageState extends State<PaymentGatewayPage> {
  Timer? _pollTimer;
  Timer? _initialCheck;
  Timer? _returnTimer;
  bool _opening = false;
  bool _checking = false;
  String? _error;
  int? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openPayment();
      _initialCheck = Timer(const Duration(seconds: 3), _checkPayment);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _initialCheck?.cancel();
    _returnTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPayment() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final uri = Uri.parse(widget.paymentUrl);
      final opened = widget.launchPayment != null
          ? await widget.launchPayment!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) throw StateError(l10n.xboardFailedToOpenPaymentLink);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkPayment(),
      );
    } catch (_) {
      if (mounted) setState(() => _error = l10n.xboardFailedToOpenPaymentLink);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _copyPaymentUrl() async {
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: widget.paymentUrl));
      if (mounted) XBoardNotification.showSuccess(l10n.xboardPaymentLinkCopied);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.xboardCopyFailed);
    }
  }

  Future<void> _checkPayment() async {
    if (_checking || !mounted || _status == 3) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final orders = await (widget.orderApi ?? XBoardSDK.instance.order)
          .getOrders();
      if (!mounted) return;
      final order = orders.firstWhere(
        (order) => order.tradeNo == widget.tradeNo,
        orElse: () => const OrderModel(status: -1),
      );
      setState(() {
        _status = order.status;
        if (_status == -1) _error = l10n.xboardOrderNotFound;
      });
      if (_status == 2 || _status == 3) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
      if (_status == 3) {
        // Only a confirmed backend result can complete the payment flow.
        _returnTimer = Timer(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = l10n.xboardFailedToCheckPaymentStatus);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final success = _status == 3;
    final statusColor = _error != null
        ? scheme.error
        : success
        ? SentinelColors.of(context).success
        : scheme.primary;
    final statusText =
        _error ??
        (success
            ? l10n.xboardPaymentSuccess
            : _status == 2
            ? l10n.xboardPaymentCancelled
            : l10n.xboardWaitingForPayment);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.xboardPaymentGateway)),
      body: SingleChildScrollView(
        child: SentinelPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SentinelPanel(
                child: Column(
                  children: [
                    if (_opening || _checking)
                      const SentinelAnimation(
                        asset: SentinelAssets.loading,
                        size: 88,
                        fallback: Icons.hourglass_top_rounded,
                      )
                    else
                      Icon(
                        success
                            ? Icons.check_circle_rounded
                            : _error != null
                            ? Icons.error_outline_rounded
                            : Icons.payment_rounded,
                        size: 56,
                        color: statusColor,
                      ),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        statusText,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: statusColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.xboardPaymentPageOpenedCompleteAndReturn,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (_pollTimer != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.xboardAutoCheckEvery5Seconds,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SentinelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.xboardPaymentInfo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.xboardOrderNumber,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(widget.tradeNo),
                    const Divider(height: 32),
                    Text(
                      l10n.xboardPaymentLink,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      widget.paymentUrl,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _opening ? null : _openPayment,
                          icon: const Icon(Icons.open_in_browser),
                          label: Text(l10n.xboardReopenPayment),
                        ),
                        OutlinedButton.icon(
                          onPressed: _copyPaymentUrl,
                          icon: const Icon(Icons.copy),
                          label: Text(l10n.xboardCopyPaymentLink),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.xboardOperationTips,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.xboardCompletePaymentInBrowser),
              Text(l10n.xboardReturnAfterPaymentAutoDetect),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _checking || success ? null : _checkPayment,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _checking ? l10n.xboardChecking : l10n.xboardCheckStatus,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(l10n.xboardReturn),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
