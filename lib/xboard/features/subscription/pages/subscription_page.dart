import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});
  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(xboardUserProvider.notifier).refreshSubscriptionInfo();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = AppLocalizations.of(
            context,
          ).xboardFailedToGetSubscriptionInfo,
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted)
      XBoardNotification.showSuccess(
        AppLocalizations.of(context).xboardSubscriptionLinkCopied,
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final url = ref.watch(subscriptionInfoProvider)?.subscribeUrl;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.xboardSubscriptionInfo),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: SentinelPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SentinelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.link_rounded, color: scheme.primary, size: 32),
                    const SizedBox(height: 16),
                    Text(
                      l10n.xboardSubscriptionLink,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const LinearProgressIndicator()
                    else if (_error != null)
                      Text(_error!, style: TextStyle(color: scheme.error))
                    else if (url == null || url.isEmpty) ...[
                      Text(l10n.xboardNoAvailableSubscription),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context.go('/plans'),
                        child: Text(l10n.xboardPlans),
                      ),
                    ] else ...[
                      SelectableText(
                        url,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _copy(url),
                        icon: const Icon(Icons.copy),
                        label: Text(l10n.xboardCopyLink),
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
                      l10n.xboardUsageInstructions,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.xboardCopySubscriptionLinkAbove),
                    const SizedBox(height: 8),
                    Text(l10n.xboardAddLinkToConfig),
                    const SizedBox(height: 8),
                    Text(l10n.xboardUpdateSubscriptionRegularly),
                    const Divider(height: 32),
                    Text(
                      l10n.xboardKeepSubscriptionLinkSafe,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
