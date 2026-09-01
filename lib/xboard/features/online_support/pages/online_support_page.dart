import 'dart:io';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/xboard/config/core/service_locator.dart';
import 'package:fl_clash/xboard/config/services/online_support_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class OnlineSupportPage extends StatefulWidget {
  const OnlineSupportPage({super.key});

  @override
  State<OnlineSupportPage> createState() => _OnlineSupportPageState();
}

class _OnlineSupportPageState extends State<OnlineSupportPage> {
  bool _launching = false;

  Uri? get _supportUri {
    try {
      final config = ServiceLocator.get<OnlineSupportService>()
          .getFirstAvailableConfig();
      final uri = Uri.tryParse(config?.url ?? '');
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return null;
      }
      return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openSupport() async {
    final uri = _supportUri;
    if (uri == null || _launching) return;

    setState(() => _launching = true);
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;

    setState(() => _launching = false);
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open customer support')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    final supportUri = _supportUri;
    final scaffold = Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(title: Text(AppLocalizations.of(context).onlineSupportTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.support_agent,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  AppLocalizations.of(context).onlineSupportTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: supportUri == null || _launching ? null : _openSupport,
                  icon: _launching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: const Text('Open customer support'),
                ),
                if (supportUri == null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Customer support is not configured.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (isDesktop) return scaffold;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/');
      },
      child: scaffold,
    );
  }
}