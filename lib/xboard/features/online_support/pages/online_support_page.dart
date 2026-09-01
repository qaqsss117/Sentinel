import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/xboard/config/core/service_locator.dart';
import 'package:fl_clash/xboard/config/services/online_support_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

class OnlineSupportPage extends StatefulWidget {
  const OnlineSupportPage({super.key});

  @override
  State<OnlineSupportPage> createState() => _OnlineSupportPageState();
}

class _OnlineSupportPageState extends State<OnlineSupportPage> {
  static const _sdkStateHandler = 'crispSdkState';

  Key _webViewKey = UniqueKey();
  bool _isLoading = true;
  bool _hasLoadError = false;

  String? get _websiteId {
    try {
      return ServiceLocator.get<OnlineSupportService>()
          .getFirstAvailableConfig()
          ?.crispWebsiteId;
    } catch (_) {
      return null;
    }
  }

  String _buildSdkDocument(String websiteId) {
    final encodedWebsiteId = jsonEncode(websiteId);
    final encodedLocale = jsonEncode(Localizations.localeOf(context).languageCode);
    final colorMode = Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
  </style>
</head>
<body>
  <script>
    window.\$crisp = [];
    window.CRISP_WEBSITE_ID = $encodedWebsiteId;
    window.CRISP_RUNTIME_CONFIG = { lock_maximized: true };
    window.\$crisp.push(["safe", true]);
    window.\$crisp.push(["config", "locale", [$encodedLocale]]);
    window.\$crisp.push(["config", "color:mode", ["$colorMode"]]);
    window.\$crisp.push(["config", "hide:on:mobile", [false]]);
    window.CRISP_READY_TRIGGER = function() {
      window.\$crisp.push(["do", "chat:open"]);
      window.flutter_inappwebview.callHandler("$_sdkStateHandler", "ready");
    };
    (function() {
      var script = document.createElement("script");
      script.src = "https://client.crisp.chat/l.js";
      script.async = true;
      script.onerror = function() {
        window.flutter_inappwebview.callHandler("$_sdkStateHandler", "error");
      };
      document.head.appendChild(script);
    })();
  </script>
</body>
</html>
''';
  }

  void _handleSdkState(List<dynamic> arguments) {
    if (!mounted || arguments.isEmpty) return;

    setState(() {
      _isLoading = false;
      _hasLoadError = arguments.first != 'ready';
    });
  }

  void _retry() {
    setState(() {
      _webViewKey = UniqueKey();
      _isLoading = true;
      _hasLoadError = false;
    });
  }

  Widget _buildSupportContent(String? websiteId) {
    final localizations = AppLocalizations.of(context);
    if (websiteId == null) {
      return _SupportError(
        message: localizations.onlineSupportConnectionError,
        onRetry: _retry,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            key: _webViewKey,
            initialData: InAppWebViewInitialData(
              data: _buildSdkDocument(websiteId),
              baseUrl: WebUri('https://client.crisp.chat/'),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              thirdPartyCookiesEnabled: true,
              supportZoom: false,
              transparentBackground: true,
            ),
            onWebViewCreated: (controller) {
              controller.addJavaScriptHandler(
                handlerName: _sdkStateHandler,
                callback: _handleSdkState,
              );
            },
          ),
        ),
        if (_isLoading)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: const Center(child: CircularProgressIndicator()),
          ),
        if (_hasLoadError)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: _SupportError(
              message: localizations.onlineSupportConnectionError,
              onRetry: _retry,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    final supportContent = _buildSupportContent(_websiteId);
    final scaffold = Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(title: Text(AppLocalizations.of(context).onlineSupportTitle)),
      body: isDesktop
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: supportContent,
              ),
            )
          : supportContent,
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

class _SupportError extends StatelessWidget {
  const _SupportError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).xboardRetry),
          ),
        ],
      ),
    );
  }
}