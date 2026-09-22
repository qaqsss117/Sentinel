import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/subscription/providers/xboard_subscription_provider.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import '../widgets/plan_description_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PlansView extends ConsumerStatefulWidget {
  const PlansView({super.key});
  @override
  ConsumerState<PlansView> createState() => _PlansViewState();
}

class _PlansViewState extends ConsumerState<PlansView> {
  bool _hasCheckedUrlParams = false; // 标记是否已检查URL参数

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final subscriptionNotifier = ref.read(
        xboardSubscriptionProvider.notifier,
      );
      subscriptionNotifier.autoRefreshIfNeeded();

      // 检查URL参数中是否有planId
      _checkUrlParams();
    });
  }

  void _checkUrlParams() {
    if (_hasCheckedUrlParams) return;
    _hasCheckedUrlParams = true;

    // 获取URL参数
    final state = GoRouterState.of(context);
    final planIdStr = state.uri.queryParameters['planId'];

    if (planIdStr != null) {
      final planId = int.tryParse(planIdStr);
      if (planId != null) {
        // 查找对应的套餐
        final plans = ref.read(xboardSubscriptionProvider);
        DomainPlan? plan;
        try {
          plan = plans.firstWhere((p) => p.id == planId);
        } catch (e) {
          plan = null;
        }

        if (plan != null) {
          context.push('/plans/purchase', extra: plan);
        }
      }
    }
  }

  Future<void> _refreshPlans() async {
    final subscriptionNotifier = ref.read(xboardSubscriptionProvider.notifier);
    await subscriptionNotifier.refreshPlans();
  }

  String _formatPrice(double? price) {
    if (price == null) return '-';
    return '¥${price.toStringAsFixed(2)}';
  }

  String _formatTraffic(double transferEnable) {
    if (transferEnable >= 1024) {
      return '${(transferEnable / 1024).toStringAsFixed(1)}TB';
    }
    return '${transferEnable.toStringAsFixed(0)}GB';
  }

  String _getLowestPrice(DomainPlan plan) {
    List<double> prices = [];
    if (plan.monthlyPrice != null) prices.add(plan.monthlyPrice!);
    if (plan.quarterlyPrice != null) prices.add(plan.quarterlyPrice!);
    if (plan.halfYearlyPrice != null) prices.add(plan.halfYearlyPrice!);
    if (plan.yearlyPrice != null) prices.add(plan.yearlyPrice!);
    if (plan.twoYearPrice != null) prices.add(plan.twoYearPrice!);
    if (plan.threeYearPrice != null) prices.add(plan.threeYearPrice!);
    if (plan.onetimePrice != null) prices.add(plan.onetimePrice!);
    if (prices.isEmpty) return '-';
    final lowestPrice = prices.reduce((a, b) => a < b ? a : b);
    return _formatPrice(lowestPrice);
  }

  String _getSpeedLimitText(DomainPlan plan) {
    if (plan.speedLimit == null) {
      return AppLocalizations.of(context).xboardUnlimited; // 不限速
    }
    return '${plan.speedLimit} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(xboardSubscriptionProvider);
    final state = ref.watch(userUIStateProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshPlans,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SentinelPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SentinelPageHeading(
                    title: l10n.xboardPlans,
                    subtitle: l10n.xboardEnjoyFastNetworkExperience,
                    trailing: IconButton(
                      onPressed: _refreshPlans,
                      tooltip: l10n.refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  if (state.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.errorMessage != null)
                    SentinelPanel(
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.xboardLoadingFailed,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.errorMessage!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _refreshPlans,
                            child: Text(l10n.xboardRetry),
                          ),
                        ],
                      ),
                    )
                  else if (plans.isEmpty)
                    SentinelPanel(
                      child: Column(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 48),
                          const SizedBox(height: 16),
                          Text(l10n.xboardNoAvailableSubscription),
                        ],
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final count = constraints.maxWidth >= 1050
                            ? 3
                            : constraints.maxWidth >= 680
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (count - 1) * 20) / count;
                        return Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            for (final plan in plans)
                              SizedBox(
                                width: width,
                                child: SentinelPlanCard(
                                  plan: plan,
                                  price: _getLowestPrice(plan),
                                  traffic: _formatTraffic(
                                    plan.transferQuota.toDouble(),
                                  ),
                                  speed: _getSpeedLimitText(plan),
                                  onPurchase: () => context.push(
                                    '/plans/purchase',
                                    extra: plan,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SentinelPlanCard extends StatelessWidget {
  const SentinelPlanCard({
    super.key,
    required this.plan,
    required this.price,
    required this.traffic,
    required this.speed,
    required this.onPurchase,
  });
  final DomainPlan plan;
  final String price;
  final String traffic;
  final String speed;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return SentinelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.workspace_premium_outlined,
                color: scheme.primary,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(plan.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            price,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              Text(
                '${l10n.xboardTraffic}: $traffic',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              Text(
                '${l10n.xboardSpeedLimit}: $speed',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (plan.description?.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            PlanDescriptionWidget(content: plan.description!),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: plan.hasPrice ? onPurchase : null,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(l10n.xboardBuyNow),
          ),
        ],
      ),
    );
  }
}
