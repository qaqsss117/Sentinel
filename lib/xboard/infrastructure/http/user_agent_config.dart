/// User-Agent 配置管理
///
/// 说明：不同的 User-Agent 是有意设计的，服务端会根据 UA 返回不同格式的数据
///
/// 使用场景：
/// 1. 订阅下载：使用 FlClash 标识和已安装应用版本获取 Clash Meta 配置。
/// 2. API/域名竞速：使用加密 UA 通过 Caddy 反代认证（从配置文件读取）
/// 3. 其他服务：使用特定版本号标识（硬编码）
library;

import 'package:package_info_plus/package_info_plus.dart';

import '../../config/utils/config_file_loader.dart';

/// User-Agent 配置类
///
/// ⚠️ 域名竞速相关的 UA 从配置文件读取，其他 UA 使用硬编码
///
/// 使用方式：
/// ```dart
/// final ua = await UserAgentConfig.get(UserAgentScenario.subscription);
/// request.headers.set(HttpHeaders.userAgentHeader, ua);
/// ```
class UserAgentConfig {
  // 硬编码的 User-Agent（非域名竞速场景）
  static const String _subscription = 'FlClash';
  static const String _attachment = 'FlClash/1.0';

  // 缓存从配置文件加载的 UA（域名竞速专用）
  static Map<String, String>? _cachedUserAgents;

  /// 获取指定场景的 User-Agent
  ///
  /// [scenario] 使用场景
  /// 返回对应的 UA 字符串
  ///
  /// 域名竞速相关的 UA 从配置文件读取，其他场景使用硬编码
  static Future<String> get(UserAgentScenario scenario) async {
    // 硬编码的场景直接返回
    switch (scenario) {
      case UserAgentScenario.subscription:
      case UserAgentScenario.subscriptionRacing:
        try {
          final version = (await PackageInfo.fromPlatform()).version.trim();
          if (RegExp(
            r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
          ).hasMatch(version)) {
            return '$_subscription/$version';
          }
        } catch (_) {
          // Xboard supports unknown versions when platform metadata is unavailable.
        }
        return _subscription;
      case UserAgentScenario.attachment:
        return _attachment;
      case UserAgentScenario.apiEncrypted:
      case UserAgentScenario.domainRacingTest:
        // 域名竞速相关的从配置文件读取
        final userAgents = await _loadUserAgents();
        final key = _scenarioToKey(scenario);

        if (!userAgents.containsKey(key)) {
          throw Exception(
            '配置文件中未找到 User-Agent 配置: security.user_agents.$key\n'
            '请在 xboard.config.yaml 中添加此配置项。',
          );
        }

        return userAgents[key]!;
    }
  }

  /// 批量获取所有 User-Agent
  static Future<Map<String, String>> getAll() async {
    return await _loadUserAgents();
  }

  /// 从配置文件加载 User-Agent（域名竞速专用）
  static Future<Map<String, String>> _loadUserAgents() async {
    if (_cachedUserAgents != null) {
      return _cachedUserAgents!;
    }

    _cachedUserAgents = await ConfigFileLoaderHelper.getUserAgents();

    // 配置文件中只需要域名竞速相关的 UA，为空也不抛异常
    return _cachedUserAgents!;
  }

  /// 清除缓存（用于重新加载配置）
  static void clearCache() {
    _cachedUserAgents = null;
  }

  /// 将场景枚举转换为配置文件中的 key
  static String _scenarioToKey(UserAgentScenario scenario) {
    return switch (scenario) {
      UserAgentScenario.subscription => 'subscription',
      UserAgentScenario.apiEncrypted => 'api_encrypted',
      UserAgentScenario.subscriptionRacing => 'subscription_racing',
      UserAgentScenario.domainRacingTest => 'domain_racing_test',
      UserAgentScenario.attachment => 'attachment',
    };
  }
}

/// User-Agent 使用场景枚举
enum UserAgentScenario {
  /// 订阅下载（FlClash/应用版本）
  subscription,

  /// API 请求/域名竞速（从配置读取 api_encrypted）
  apiEncrypted,

  /// 并发订阅竞速（与订阅下载使用同一版本）
  subscriptionRacing,

  /// 域名竞速测试（从配置读取 domain_racing_test）
  domainRacingTest,

  /// 消息附件下载（硬编码：'FlClash/1.0'）
  attachment,
}
