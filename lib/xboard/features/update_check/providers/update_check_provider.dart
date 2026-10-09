import 'package:fl_clash/xboard/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/update_check_state.dart';
import '../services/update_service.dart';
import '../update_check_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 初始化文件级日志器
final _logger = FileLogger('update_check_provider.dart');

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
final updateCheckProvider =
    StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>((ref) {
  final updateService = ref.watch(updateServiceProvider);
  return UpdateCheckNotifier(updateService: updateService);
});
class UpdateCheckNotifier extends StateNotifier<UpdateCheckState> {
  final UpdateService _updateService;
  UpdateCheckNotifier({
    required UpdateService updateService,
  })  : _updateService = updateService,
        super(const UpdateCheckState());
  Future<void> initialize() async {
    _logger.info('开始检查更新');
    await checkForUpdates(automatic: true);
  }
  Future<void> refresh() async {
    _logger.info('刷新检查更新');
    await checkForUpdates();
  }
  Future<void> checkForUpdates({bool automatic = false}) async {
    if (!mounted) return;
    if (state.isChecking) return;
    if (automatic && await _isThrottled()) {
      _logger.info('距上次成功检查不足 24 小时，跳过自动检查');
      return;
    }
    state = state.copyWith(
      isChecking: true,
      error: null,
    );
    try {
      final currentVersion = await _updateService.getCurrentVersion();
      _logger.info('当前版本: $currentVersion');
      state = state.copyWith(currentVersion: currentVersion);
      final updateInfo = await _updateService.checkForUpdates();
      if (!mounted) return;
      state = state.copyWith(
        isChecking: false,
        hasUpdate: updateInfo["hasUpdate"] as bool? ?? false,
        latestVersion: updateInfo["latestVersion"]?.toString(),
        updateUrl: updateInfo["updateUrl"]?.toString(),
        releaseNotes: updateInfo["releaseNotes"]?.toString(),
        forceUpdate: updateInfo["forceUpdate"] as bool? ?? false,
        minimumSupportedVersion: updateInfo["minimumSupportedVersion"]?.toString(),
        distribution: updateInfo["distribution"]?.toString(),
        sha256: updateInfo["sha256"]?.toString(),
      );
      // 只有真正拿到服务端响应才记录节流时间戳。
      // 旧实现在这里之前就写入时间戳，一次断网或 5xx 会把后续 24 小时
      // 全部锁死，表现为「服务端已发版但客户端永不弹窗」。
      await _recordCheckOutcome(succeeded: true);
      if (state.hasUpdate) {
        _logger.info('发现新版本: ${state.latestVersion}');
        if (state.releaseNotes != null && state.releaseNotes!.isNotEmpty) {
          // _logger.debug('发布说明: ${state.releaseNotes}');
        }
      } else {
        _logger.info('已是最新版本');
      }
    } catch (e) {
      if (!mounted) return;
      _logger.error('检查更新失败', e);
      await _recordCheckOutcome(succeeded: false);
      state = state.copyWith(
        isChecking: false,
        error: e.toString(),
      );
    }
  }

  /// 判断本次自动检查是否应被 24 小时窗口节流。
  Future<bool> _isThrottled() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckMs = prefs.getInt(UpdateCheckPolicy.lastSuccessfulCheckKey);
    final succeeded = prefs.getBool(UpdateCheckPolicy.lastCheckSucceededKey) ?? true;
    return UpdateCheckPolicy.shouldSkipAutomaticCheck(
      lastCheckMs: lastCheckMs,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      lastCheckSucceeded: succeeded,
    );
  }

  /// 记录本次检查结果，失败时不推进节流时间戳。
  Future<void> _recordCheckOutcome({required bool succeeded}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UpdateCheckPolicy.lastCheckSucceededKey, succeeded);
    if (succeeded) {
      await prefs.setInt(
        UpdateCheckPolicy.lastSuccessfulCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }
}
