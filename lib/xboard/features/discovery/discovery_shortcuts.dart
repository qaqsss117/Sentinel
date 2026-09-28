import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'discovery_links.dart';
import 'discovery_provider.dart';

class DiscoveryShortcuts extends ConsumerStatefulWidget {
  const DiscoveryShortcuts({super.key});

  @override
  ConsumerState<DiscoveryShortcuts> createState() => _DiscoveryShortcutsState();
}

class _DiscoveryShortcutsState extends ConsumerState<DiscoveryShortcuts> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(discoveryProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final catalog = ref.watch(discoveryProvider).catalog;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => openDiscoveryLink(context, catalog.landingPageUrl),
          icon: const Icon(Icons.language),
          label: Text(strings.discoveryWebsite),
        ),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/discover'),
          icon: const Icon(Icons.explore_outlined),
          label: Text(strings.discoveryTitle),
        ),
      ],
    );
  }
}
