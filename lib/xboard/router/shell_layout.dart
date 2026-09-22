import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/navigation/desktop_navigation_rail.dart';
import '../widgets/navigation/mobile_navigation_bar.dart';

class AdaptiveShellLayout extends StatelessWidget {
  const AdaptiveShellLayout({super.key, required this.child});
  final StatefulNavigationShell child;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final desktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;
    void select(int index) => child.goBranch(index);
    return PopScope(
      canPop: desktop || child.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !desktop) child.goBranch(0);
      },
      child: desktop
          ? Row(
              children: [
                DesktopNavigationRail(
                  selectedIndex: child.currentIndex,
                  onDestinationSelected: select,
                  extended: MediaQuery.sizeOf(context).width >= 1200,
                ),
                Expanded(child: child),
              ],
            )
          : Scaffold(
              body: child,
              bottomNavigationBar: MobileNavigationBar(
                selectedIndex: child.currentIndex,
                onDestinationSelected: select,
              ),
            ),
    );
  }
}
