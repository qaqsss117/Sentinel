import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 自动更新检查的节流与弹窗去重策略。
///
/// 抽成纯函数是为了让这段最容易出错的时序逻辑可以被单元测试覆盖：
/// 它直接决定用户能否看到更新弹窗，而失败模式是「静默不弹窗」，
/// 靠手工点击检查很难稳定复现。
class UpdateCheckPolicy {
  const UpdateCheckPolicy._();

  /// 自动检查的最小间隔。
  static const autoCheckInterval = Duration(hours: 24);

  /// 记录最近一次**成功**检查时间的持久化键。
  static const lastSuccessfulCheckKey = 'sentinel.update.lastCheck';

  /// 记录最近一次成功检查是否发生的标记键。
  static const lastCheckSucceededKey = 'sentinel.update.lastCheckSucceeded';

  /// 弹窗去重键的前缀。
  static const promptedKeyPrefix = 'sentinel.update.prompted';

  /// 判断本次自动检查是否应被节流跳过。
  ///
  /// [lastCheckMs] 是持久化的检查时间戳；[lastCheckSucceeded] 表示那次检查
  /// 是否真的拿到了服务端响应。**失败的检查不应锁死后续检查** —— 否则一次
  /// 断网或服务端 5xx 会让客户端在 24 小时内彻底放弃更新检查，
  /// 表现为「服务端已发版但客户端永不弹窗」。
  static bool shouldSkipAutomaticCheck({
    required int? lastCheckMs,
    required int nowMs,
    bool lastCheckSucceeded = true,
  }) {
    if (lastCheckMs == null) return false;
    if (!lastCheckSucceeded) return false;
    return nowMs - lastCheckMs < autoCheckInterval.inMilliseconds;
  }

  /// 构造弹窗去重键。
  ///
  /// 键中包含更新内容的指纹，而不只是版本号。仅按版本号去重会导致：
  /// 某版本弹过一次后，服务端即使修改了更新说明、下载地址或强制更新状态，
  /// 客户端也不会再提示，管理员在后台改配置完全看不到效果。
  static String promptKey({
    required String? version,
    required String? releaseNotes,
    required String? updateUrl,
    required bool forceUpdate,
  }) {
    final versionPart = (version == null || version.isEmpty) ? 'unknown' : version;
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'v': versionPart,
              'n': releaseNotes ?? '',
              'u': updateUrl ?? '',
              'f': forceUpdate,
            }),
          ),
        )
        .toString();
    // 保留可读的版本号，便于在 SharedPreferences 中人工排查。
    final safeVersion = versionPart.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return '$promptedKeyPrefix.$safeVersion.${fingerprint.substring(0, 12)}';
  }
}
