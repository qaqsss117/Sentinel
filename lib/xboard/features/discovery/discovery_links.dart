import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

typedef DiscoveryUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> launchDiscoveryUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> openDiscoveryLink(
  BuildContext context,
  String url, {
  DiscoveryUrlLauncher launcher = launchDiscoveryUrl,
}) async {
  final uri = DiscoveryCatalog.httpsUri(url);
  if (uri == null) return;
  var opened = false;
  try {
    opened = await launcher(uri);
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  final strings = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.discoveryOpenFailed),
      content: SelectableText(uri.toString()),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: uri.toString()));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: Text(strings.discoveryCopyLink),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );
}
