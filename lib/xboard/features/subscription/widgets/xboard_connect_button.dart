import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/profile/profile.dart';
import 'package:fl_clash/theme/sentinel_assets.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';

class XBoardConnectButton extends ConsumerStatefulWidget {
  const XBoardConnectButton({
    super.key,
    this.isFloating = false,
    this.onToggle,
  });
  final bool isFloating;

  /// Optional command adapter; the displayed state always comes from the runtime.
  final Future<void> Function(bool start)? onToggle;
  @override
  ConsumerState<XBoardConnectButton> createState() =>
      _XBoardConnectButtonState();
}

class _XBoardConnectButtonState extends ConsumerState<XBoardConnectButton> {
  bool _pending = false;
  bool _failed = false;

  bool get _ready =>
      ref.read(subscriptionInfoProvider)?.subscribeUrl.isNotEmpty == true &&
      ref.read(currentProfileProvider)?.subscriptionInfo != null &&
      !ref.read(profileImportProvider).isImporting;

  Future<void> _toggle() async {
    if (_pending) return;
    final running = ref.read(runTimeProvider) != null;
    if (!running && !_ready) return;
    setState(() {
      _pending = true;
      _failed = false;
    });
    try {
      if (widget.onToggle != null) {
        await widget.onToggle!(!running);
      } else {
        await globalState.appController.updateStatus(!running);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capability = ref.watch(startButtonSelectorStateProvider);
    final subscription = ref.watch(subscriptionInfoProvider);
    final profile = ref.watch(currentProfileProvider);
    final importing = ref.watch(profileImportProvider).isImporting;
    final runTime = ref.watch(runTimeProvider);
    final running = runTime != null;
    final ready =
        capability.isInit &&
        capability.hasProfile &&
        subscription?.subscribeUrl.isNotEmpty == true &&
        profile?.subscriptionInfo != null &&
        !importing;
    final l10n = AppLocalizations.of(context);
    final label = _pending
        ? l10n.loading
        : running
        ? l10n.xboardStopProxy
        : l10n.xboardStartProxy;
    final status = _failed
        ? l10n.xboardOperationFailed
        : running
        ? l10n.xboardRunningTime(utils.getTimeText(runTime))
        : importing || !capability.isInit
        ? l10n.xboardPreparingImport
        : !ready
        ? l10n.xboardNoAvailableSubscription
        : l10n.xboardConnectGlobalQualityNodes;
    return SentinelConnectionControl(
      running: running,
      pending: _pending,
      failed: _failed,
      compact: widget.isFloating,
      label: label,
      status: status,
      onPressed: !_pending && (running || ready) ? _toggle : null,
    );
  }
}

/// Pure presentation shared by the live home screen and visual regression tests.
class SentinelConnectionControl extends StatelessWidget {
  const SentinelConnectionControl({
    super.key,
    required this.running,
    required this.pending,
    required this.label,
    required this.status,
    this.failed = false,
    this.compact = false,
    this.onPressed,
  });
  final bool running;
  final bool pending;
  final bool failed;
  final bool compact;
  final String label;
  final String status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = SentinelColors.of(context);
    final active = running ? brand.success : scheme.primary;
    if (compact) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(
          running ? Icons.stop_rounded : Icons.power_settings_new_rounded,
        ),
        label: Text(label),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 224,
          height: 224,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final diameter in [224.0, 196.0])
                Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active.withValues(
                        alpha: diameter == 224 ? .12 : .25,
                      ),
                    ),
                  ),
                ),
              if (pending)
                const SentinelAnimation(
                  asset: SentinelAssets.connection,
                  size: 224,
                ),
              Container(
                width: 164,
                height: 164,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: active.withValues(alpha: .18),
                      blurRadius: 40,
                      spreadRadius: 6,
                    ),
                  ],
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      active.withValues(alpha: .24),
                      brand.glow.withValues(alpha: .08),
                    ],
                  ),
                  border: Border.all(color: active.withValues(alpha: .5)),
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPressed,
                    customBorder: const CircleBorder(),
                    child: Semantics(
                      button: true,
                      enabled: onPressed != null,
                      label: label,
                      child: Center(
                        child: pending
                            ? const SentinelAnimation(
                                asset: SentinelAssets.loading,
                                size: 90,
                              )
                            : running
                            ? const SentinelAnimation(
                                asset: SentinelAssets.secured,
                                size: 100,
                                repeat: false,
                                fallback: Icons.shield_rounded,
                              )
                            : Icon(
                                Icons.power_settings_new_rounded,
                                size: 62,
                                color: onPressed != null
                                    ? active
                                    : scheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            status,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: failed
                  ? scheme.error
                  : running
                  ? brand.success
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
