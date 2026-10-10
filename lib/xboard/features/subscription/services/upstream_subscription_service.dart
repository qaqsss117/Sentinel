import 'package:fl_clash/xboard/core/core.dart';

import 'upstream_routing_resolver.dart';
import 'subscription_downloader.dart';

final _logger = FileLogger('upstream_subscription_service.dart');

/// 上游订阅直连拉取（明文 HTTPS，绕过面板加密网关）。
///
/// 上游同为 Xboard，按 flag 参数分发格式；Sentinel 内核是 Clash.Meta
/// → 固定追加 routing.preferredFlag（clash）。
///
/// ⚠️ 上游响应的 subscription-userinfo 是「上游账号」的用量，被本面板
/// 多个用户共享 —— 绝不能当作本用户的配额展示（D3），[fetch] 直接丢弃。
class UpstreamSubscriptionService {
  static const int maxAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 3);

  /// 拉取上游订阅内容（Clash YAML）。
  ///
  /// 失败时抛异常（调用方负责重试/换链路/回落逻辑），
  /// 重试本身由调用方 [XBoardProfileImportService] 的整体重试承担。
  static Future<String> fetch(UpstreamRouting routing) async {
    final url = routing.fetchUrl;
    _logger.info('直连拉取上游订阅: ${routing.safeUrlForLog} (flag=${routing.preferredFlag})');
    try {
      final result = await SubscriptionDownloader.fetchRaw(
        url,
        userAgent: 'clash-verge/v2.0.0',
      );
      if (result.content.trim().isEmpty) {
        throw Exception('上游订阅内容为空');
      }
      _logger.info(
        '上游订阅拉取成功: ${result.bytes.length} bytes '
        '(上游账号 userinfo 已丢弃，不用于本用户配额)',
      );
      return result.content;
    } catch (e) {
      _logger.warning('上游订阅拉取失败: ${routing.safeUrlForLog}', e);
      // 拉取失败 → 使路由缓存失效，下次订阅刷新让服务端换链路（D10）
      UpstreamRoutingResolver.invalidate();
      rethrow;
    }
  }
}
