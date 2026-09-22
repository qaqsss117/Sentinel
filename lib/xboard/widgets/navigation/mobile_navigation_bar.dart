import 'package:flutter/material.dart';
import 'package:fl_clash/l10n/l10n.dart';

/// 移动端底部导航栏
class MobileNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;

  const MobileNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);

    return NavigationBar(
      selectedIndex: selectedIndex,
      height: 76,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home, size: 22),
          label: appLocalizations.xboardHome,
        ),
        NavigationDestination(
          icon: const Icon(Icons.shopping_bag_outlined, size: 22),
          selectedIcon: const Icon(Icons.shopping_bag, size: 22),
          label: appLocalizations.xboardPlans,
        ),
        NavigationDestination(
          icon: const Icon(Icons.support_agent_outlined, size: 22),
          selectedIcon: const Icon(Icons.support_agent, size: 22),
          label: appLocalizations.onlineSupport,
        ),
        NavigationDestination(
          icon: const Icon(Icons.people, size: 22),
          label: appLocalizations.invite,
        ),
      ],
      onDestinationSelected: onDestinationSelected,
    );
  }
}
