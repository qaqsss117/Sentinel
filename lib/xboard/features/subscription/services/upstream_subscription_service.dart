import 'dart:convert';

import 'package:fl_clash/xboard/core/core.dart';

import 'upstream_routing_resolver.dart';
import 'subscription_downloader.dart';

final _logger = FileLogger('upstream_subscription_service.dart');

/// 上游订阅直连拉取（明文 HTTPS，绕过面板加密网关）。
///
/// 上游同为 Xboard，按 flag 参数分发格式；Sentinel 内核是 mihomo
/// → 追加 routing.preferredFlag（meta）。
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
      final proxies = _countProxies(result.content);
      if (proxies == 0) {
        // 上游返回了合法 YAML 但 proxies 为空 —— 已实测某上游对 flag=clash
        // 走经典内核模板，会把 vless+ech/hy2 节点全过滤掉（56 → 0）。
        // 此时必须抛错让调用方换 flag / 换链路，绝不能把空配置写进去
        // 覆盖用户正在用的配置（那会造成「客户端突然没节点」）。
        throw Exception(
          '上游返回 0 个节点（proxies 为空）。'
          '多半是 flag=${routing.preferredFlag} 与上游节点协议不兼容'
          '（如 flag=clash 走经典内核模板，过滤掉 vless+ech/hysteria2）。'
          '可在插件链路配置里改用 meta/sing-box 格式。',
        );
      }
      _logger.info(
        '上游订阅拉取成功: ${result.bytes.length} bytes，节点 $proxies 个 '
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

  /// 统计 Clash YAML 里的节点数（proxies 段条目）。
  ///
  /// 只做行级近似统计，不引入 yaml 依赖：数 `proxies:` 段内形如
  /// `- { name: ...` / `- name: ...` 的条目行。段边界到下一个顶层键为止。
  static int _countProxies(String content) {
    var inProxies = false;
    var count = 0;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;
      // 顶层键（无缩进）
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        inProxies = line.startsWith('proxies:');
        if (inProxies) {
          // 行内写法 `proxies: [{...}, {...}]` → 直接数顶层花括号条目
          final inline = line.substring('proxies:'.length).trim();
          if (inline.startsWith('[')) {
            return _countInlineEntries(inline);
          }
          if (inline.isNotEmpty && !inline.startsWith('#')) {
            count = 1; // `proxies: {name: x}` 单条内联
          }
        }
        continue;
      }
      if (!inProxies) continue;
      final t = line.trimLeft();
      if (t.startsWith('- {') || (t.startsWith('- ') && t.length > 2)) {
        count++;
      }
    }
    return count;
  }

  /// 行内数组写法：`proxies: []` → 0；`[{...}, {...}]` → 2。
  static int _countInlineEntries(String inline) {
    if (!inline.startsWith('[')) return 0;
    var depth = 0;
    var count = 0;
    var sawContent = false;
    for (var i = 0; i < inline.length; i++) {
      final c = inline[i];
      if (c == '{' || c == '[') {
        depth++;
        if (depth == 2) {
          count++;
          sawContent = true;
        }
      } else if (c == '}' || c == ']') {
        depth--;
      }
    }
    return (depth == 0 && sawContent) ? count : 0;
  }
}
