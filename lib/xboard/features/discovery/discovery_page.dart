import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'discovery_links.dart';
import 'discovery_provider.dart';

class DiscoveryPage extends ConsumerStatefulWidget {
  const DiscoveryPage({super.key, this.launcher = launchDiscoveryUrl});
  final DiscoveryUrlLauncher launcher;

  @override
  ConsumerState<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends ConsumerState<DiscoveryPage> {
  String? _category;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(discoveryProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(discoveryProvider);
    final strings = AppLocalizations.of(context);
    final labels = {
      'search': strings.discoverySearchCategory,
      'video': strings.discoveryVideoCategory,
      'social': strings.discoverySocialCategory,
      'ai': strings.discoveryAiCategory,
      'developer': strings.discoveryDeveloperCategory,
    };
    final sites = store.filtered(category: _category, query: _query);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.discoveryTitle),
        actions: [
          IconButton(
            tooltip: strings.discoveryRefresh,
            onPressed: store.isLoading ? null : store.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SentinelBackground(
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SentinelPage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SentinelPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.discoveryWebsite,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(Uri.parse(store.catalog.landingPageUrl).host),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => openDiscoveryLink(
                              context,
                              store.catalog.landingPageUrl,
                              launcher: widget.launcher,
                            ),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(strings.discoveryWebsite),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      strings.discoveryHint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        labelText: strings.discoverySearch,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(strings.discoveryAll),
                          selected: _category == null,
                          onSelected: (_) => setState(() => _category = null),
                        ),
                        for (final category in DiscoveryCatalog.categories)
                          ChoiceChip(
                            label: Text(labels[category]!),
                            selected: _category == category,
                            onSelected: (_) =>
                                setState(() => _category = category),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (store.isLoading) const LinearProgressIndicator(),
                    if (store.refreshFailed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(strings.discoveryRefreshFailed),
                            TextButton.icon(
                              onPressed: store.refresh,
                              icon: const Icon(Icons.refresh),
                              label: Text(strings.discoveryRefresh),
                            ),
                          ],
                        ),
                      ),
                    if (sites.isEmpty && !store.isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          store.catalog.sites.isEmpty
                              ? strings.discoveryEmpty
                              : strings.discoveryNoMatches,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 900
                            ? 3
                            : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final site in sites)
                              SizedBox(
                                width: width,
                                child: SentinelPanel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            child: Text(
                                              site.name.characters.first
                                                  .toUpperCase(),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              site.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        Uri.parse(site.url).host,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (site.description.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(site.description),
                                      ],
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: () => openDiscoveryLink(
                                          context,
                                          site.url,
                                          launcher: widget.launcher,
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 18,
                                        ),
                                        label: Text(strings.discoveryOpen),
                                      ),
                                    ],
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
            ],
          ),
        ),
      ),
    );
  }
}
