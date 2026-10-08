import 'package:fl_clash/xboard/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/update_check_state.dart';
import '../services/update_service.dart';
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
    if (automatic) {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('sentinel.update.lastCheck') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last < const Duration(hours: 24).inMilliseconds) {
        return;
      }
      await prefs.setInt('sentinel.update.lastCheck', DateTime.now().millisecondsSinceEpoch);
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
      state = state.copyWith(
        isChecking: false,
        error: e.toString(),
      );
    }
  }
}
