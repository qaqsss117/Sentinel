import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/xboard/features/auth/providers/config_provider.dart';
import 'package:fl_clash/xboard/features/invite/providers/invite_provider.dart';
import 'package:fl_clash/xboard/features/invite/widgets/qr_code_widget.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';

String buildInviteUrl(String appUrl, String inviteCode) {
  final siteUri = Uri.tryParse(appUrl.trim());
  if (siteUri == null || !siteUri.hasScheme || !siteUri.hasAuthority) return '';

  return Uri(
    scheme: siteUri.scheme,
    userInfo: siteUri.userInfo,
    host: siteUri.host,
    port: siteUri.hasPort ? siteUri.port : null,
    path: siteUri.path,
    queryParameters: {
      ...siteUri.queryParameters,
      'code': inviteCode,
    },
  ).toString();
}

class InviteQrCard extends ConsumerWidget {
  const InviteQrCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inviteState = ref.watch(inviteProvider);
    final configAsync = ref.watch(configProvider);
    final appUrl = configAsync.when(
      data: (config) => config?.appUrl ?? '',
      loading: () => '',
      error: (_, _) => '',
    );
    
    final firstCode = inviteState.hasInviteData && inviteState.inviteData!.codes.isNotEmpty
        ? inviteState.inviteData!.codes.first
        : null;
    
    final inviteUrl = firstCode != null
      ? buildInviteUrl(appUrl, firstCode.code)
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              appLocalizations.myInviteQr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            if (firstCode != null && inviteUrl.isNotEmpty) ...[
              QrCodeWidget(
                data: inviteUrl,
                size: 200,
              ),
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _saveQrCode(context, inviteUrl),
                    icon: const Icon(Icons.save_alt),
                    label: Text(appLocalizations.saveQr),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _copyToClipboard(context, inviteUrl),
                    icon: const Icon(Icons.link),
                    label: Text(appLocalizations.copyInviteLink),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ] else if (configAsync.isLoading ||
              inviteState.isLoading ||
              inviteState.isGenerating) ...[
              Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      appLocalizations.generatingInviteCode,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appLocalizations.inviteCodeGenFailed,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appLocalizations.checkNetwork,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    XBoardNotification.showSuccess(appLocalizations.copiedToClipboard);
  }

  void _saveQrCode(BuildContext context, String inviteUrl) {
    XBoardNotification.showInfo(appLocalizations.saveQrCodeFeature);
  }
}