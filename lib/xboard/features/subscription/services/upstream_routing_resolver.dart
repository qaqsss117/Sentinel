import 'dart:convert';

import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';

import 'package:fl_clash/xboard/core/core.dart';

final _logger = FileLogger('upstream_routing_resolver.dart');

/// 上游链路路由信息（来自面板 /api/v1/user/getSubscribe 的 upstream 块）。
///
/// ⚠️ [subscribeUrl] 含上游订阅 token（明文）—— 只允许存在于内存
/// （D1：落盘必须加密，本类不落盘）。日志打印必须用 [safeUrlForLog]。
class UpstreamRouting {
  final int linkId;
  final String linkName;
  final String linkState;
  final String subscribeUrl;
  final List<String> flags;
  final int assignedAt;
  final bool reportEnabled;
  final int reportInterval;
  final int deviceTtl;

  const UpstreamRouting({
    required this.linkId,
    required this.linkName,
    required this.linkState,
    required this.subscribeUrl,
    required this.flags,
    required this.assignedAt,
    required this.reportEnabled,
    required this.reportInterval,
    required this.deviceTtl,
  });

  /// Sentinel 内核是 Clash.Meta → 优先选 clash；不支持时取 flags 第一个。
  String get preferredFlag {
    if (flags.contains('clash')) return 'clash';
    if (flags.isNotEmpty) return flags.first;
    return 'clash';
  }

  /// 完整拉取 URL（追加 flag）。
  String get fetchUrl {
    final sep = subscribeUrl.contains('?') ? '&' : '?';
    return '$subscribeUrl${sep}flag=${Uri.encodeComponent(preferredFlag)}';
  }

  /// 日志脱敏：去掉 query（含上游 token），只留 origin+path。
  String get safeUrlForLog {
    try {
      final uri = Uri.parse(subscribeUrl);
      return '${uri.replace(query: '')}';
    } catch (_) {
      return '<invalid-url>';
    }
  }

  static UpstreamRouting? fromJson(dynamic json) {
    if (json is! Map) return null;
    final url = json['subscribe_url'];
    if (url is! String || url.isEmpty) return null;
    final flagsRaw = json['flags'];
    return UpstreamRouting(
      linkId: (json['link_id'] as num?)?.toInt() ?? 0,
      linkName: (json['link_name'] as String?) ?? '',
      linkState: (json['link_state'] as String?) ?? '',
      subscribeUrl: url,
      flags: flagsRaw is List
          ? flagsRaw.whereType<String>().toList()
          : const <String>[],
      assignedAt: (json['assigned_at'] as num?)?.toInt() ?? 0,
      reportEnabled: json['report_enabled'] == true,
      reportInterval: (json['report_interval'] as num?)?.toInt() ?? 60,
      deviceTtl: (json['device_ttl'] as num?)?.toInt() ?? 10,
    );
  }
}

/// 解析并内存缓存当前用户的上游路由。
///
/// 上游 token 只存在于 [_cached] 静态字段（进程内存，不落盘）。
/// 链路失败后调 [invalidate]，下次 [resolve] 重新向面板请求 ——
/// 服务端会因 degraded 释放粘性分配并换链路（D10）。
class UpstreamRoutingResolver {
  static UpstreamRouting? _cached;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(minutes: 10);

  /// 面板订阅 token（v2_user.token，client 中间件鉴权用）。
  /// 与上游 token 不同！这是本用户在面板的 token，随 getSubscribe 响应携带。
  /// 仅内存，不落盘。
  static String? _panelSubscribeToken;

  /// getSubscribe 响应 data（含 u/d/transfer_enable/expired_at）。
  /// 上游模式的 Profile 订阅信息用它构造 —— 面板口径配额，而非上游账号的。
  static Map<String, dynamic>? _panelData;

  /// 面板订阅 token（上报端点鉴权用）；未登录/未拉取过订阅时为 null。
  static String? get panelSubscribeToken => _panelSubscribeToken;

  /// 最近一次 getSubscribe 的 data（可能过期，调用方自行判断时效）。
  static Map<String, dynamic>? get panelData => _panelData;

  /// 解析当前上游路由；不适用上游模式 / 插件关闭 / 拉取失败 → null
  /// （调用方回落到面板加密网关订阅）。
  static Future<UpstreamRouting?> resolve({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cached != null && _fresh()) {
      return _cached;
    }
    try {
      final result = await XBoardSDK.instance.httpService
          .getRequest('/api/v1/user/getSubscribe');
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        _panelData = data;
        final panelToken = data['token'];
        if (panelToken is String && panelToken.isNotEmpty) {
          _panelSubscribeToken = panelToken;
        }
      }
      final upstreamJson = data is Map ? data['upstream'] : null;
      final routing = UpstreamRouting.fromJson(upstreamJson);
      if (routing == null) {
        _cached = null;
        _cachedAt = DateTime.now();
        return null;
      }
      // 安全校验：上游订阅地址必须是 https（拒绝 http 明文与畸形 URL）
      if (!routing.subscribeUrl.startsWith('https://')) {
        _logger.warning(
          'upstream subscribe_url 不是 https，拒绝使用: ${routing.safeUrlForLog}',
        );
        _cached = null;
        return null;
      }
      _cached = routing;
      _cachedAt = DateTime.now();
      _logger.info(
        'upstream 路由已解析: link=${routing.linkId}(${routing.linkName}) '
        'state=${routing.linkState} flag=${routing.preferredFlag}',
      );
      return routing;
    } catch (e) {
      _logger.warning('解析 upstream 路由失败（回落面板订阅）', e);
      // 保留旧缓存：面板短暂不可达不应导致用户掉回自建节点
      if (_cached != null && _fresh()) return _cached;
      return null;
    }
  }

  static bool _fresh() =>
      _cachedAt != null &&
      DateTime.now().difference(_cachedAt!) < _cacheTtl;

  /// 上游拉取失败后使缓存失效，让下次订阅刷新换链路。
  /// （只清上游路由，panel token 保留 —— 上报仍需要它）
  static void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  static UpstreamRouting? get cached => _cached;
}
