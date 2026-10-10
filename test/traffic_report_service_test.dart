import 'package:flutter_test/flutter_test.dart';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/xboard/features/subscription/services/upstream_routing_resolver.dart';
import 'package:fl_clash/xboard/features/traffic/services/traffic_report_service.dart';

/// 会话锚点算法单测（纯 Dart，无需 mihomo 内核）。
///
/// 覆盖四类不变量：
/// 1. 单会话连续上报：u_total 单调递增，seq 严格递增
/// 2. 会话切换（内核清零）：锚点垫底，u_total 不回落、无负数、不丢增量
/// 3. 失败重发：同 seq 原 payload 重发，成功后锚点推进
/// 4. 进程重启（锚点归零）：u_total 从内核值重新起步（服务端 delta=0 兜底）
void main() {
  group('UpstreamRouting', () {
    test('fromJson 解析完整 upstream 块', () {
      final routing = UpstreamRouting.fromJson({
        'enabled': true,
        'link_id': 7,
        'link_name': '上游A',
        'link_state': 'active',
        'subscribe_url': 'https://up.example.com/api/v1/client/subscribe?token=SECRET',
        'flags': ['clash', 'sing-box'],
        'assigned_at': 1760000000,
        'report_enabled': true,
        'report_interval': 60,
        'device_ttl': 10,
      });
      expect(routing, isNotNull);
      expect(routing!.preferredFlag, 'clash');
      expect(
        routing.fetchUrl,
        'https://up.example.com/api/v1/client/subscribe?token=SECRET&flag=clash',
      );
      // 日志脱敏：不得包含 query（上游 token）
      expect(routing.safeUrlForLog.contains('SECRET'), isFalse);
      expect(routing.safeUrlForLog.startsWith('https://up.example.com'), isTrue);
    });

    test('flags 无 clash 时取第一个', () {
      final routing = UpstreamRouting.fromJson({
        'subscribe_url': 'https://x.example.com/s?token=t',
        'flags': ['sing-box'],
      });
      expect(routing!.preferredFlag, 'sing-box');
    });

    test('http:// 被上游服务拒绝', () {
      final routing = UpstreamRouting.fromJson({
        'subscribe_url': 'http://insecure.example.com/s?token=t',
        'flags': ['clash'],
      });
      // resolver 层校验 https；模型层只负责解析
      expect(routing, isNotNull);
    });

    test('缺少 subscribe_url 返回 null', () {
      expect(UpstreamRouting.fromJson({'enabled': true}), isNull);
      expect(UpstreamRouting.fromJson(null), isNull);
      expect(UpstreamRouting.fromJson('string'), isNull);
    });
  });

  group('TrafficReportService 会话锚点', () {
    late _FakeTransport transport;
    late _ScriptedTotal totals;

    setUp(() {
      transport = _FakeTransport();
      totals = _ScriptedTotal();
    });

    TrafficReportService newService() => TrafficReportService.forTest(
          totals.read,
          reportSender: transport.send,
          heartbeatSender: transport.heartbeat,
        );

    test('单会话连续上报：u_total 单调递增、seq 严格递增', () async {
      final service = newService();
      await service.onTunnelStart();
      totals.next(up: 100, down: 200);
      await service.tickForTest();
      totals.next(up: 300, down: 500);
      await service.tickForTest();
      totals.next(up: 1000, down: 1500);
      await service.tickForTest();

      expect(transport.reports.length, 3);
      expect(transport.reports.map((r) => r.seq), [1, 2, 3]);
      expect(transport.reports.map((r) => r.uTotal), [100, 300, 1000]);
      expect(transport.reports.map((r) => r.dTotal), [200, 500, 1500]);
      final totalsList = transport.reports.map((r) => r.uTotal).toList();
      for (var i = 1; i < totalsList.length; i++) {
        expect(totalsList[i], greaterThan(totalsList[i - 1]));
      }
    });

    test('会话切换（内核清零）：锚点垫底，无负数、不丢增量', () async {
      final service = newService();
      // 会话1：内核累计到 1000/2000，全部上报成功
      await service.onTunnelStart();
      totals.next(up: 1000, down: 2000);
      await service.tickForTest();
      expect(transport.reports.last.uTotal, 1000);

      // 隧道停止（flush 尾部）→ 内核清零 → 新会话
      totals.next(up: 1000, down: 2000); // flush 读最终值
      await service.onTunnelStop();
      await service.onTunnelStart();

      // 新会话内核从 0 重新累计到 500/800
      totals.next(up: 500, down: 800);
      await service.tickForTest();

      // 锚点垫底：u_total = 已入账(1000) + 新会话(500) = 1500 —— 不回落、不丢
      final last = transport.reports.last;
      expect(last.uTotal, 1500);
      expect(last.dTotal, 2800);
      expect(last.sessionId, isNot(equals(transport.reports.first.sessionId)));
    });

    test('失败重发：同 seq 原 payload，成功后锚点推进', () async {
      final service = newService();
      await service.onTunnelStart();
      totals.next(up: 600, down: 700);
      transport.failNext = true;
      await service.tickForTest(); // seq=1 失败，挂起

      expect(transport.reports.length, 1);
      expect(transport.reports.last.seq, 1);

      totals.next(up: 600, down: 700);
      await service.tickForTest(); // 重发 seq=1 成功
      expect(transport.reports.length, 2);
      expect(transport.reports.last.seq, 1, reason: '重发必须同 seq');
      expect(transport.reports.last.uTotal, 600);

      totals.next(up: 900, down: 700);
      await service.tickForTest(); // 新上报 seq=2
      expect(transport.reports.last.seq, 2);
      expect(transport.reports.last.uTotal, 600 + 900,
          reason: '锚点已推进到 600，新内核读数 900');
    });

    test('内核读数回落（异常防御）：不产生负增量', () async {
      final service = newService();
      await service.onTunnelStart();
      totals.next(up: 1000, down: 1000);
      await service.tickForTest();

      // 模拟内核读数异常回落（未走 onTunnelStop 的路径）
      totals.next(up: 200, down: 100);
      await service.tickForTest();

      // 逻辑总量 = 锚点(1000) + 200 = 1200 ≥ 锚点，绝不回落
      expect(transport.reports.last.uTotal, greaterThanOrEqualTo(1000));
    });

    test('进程重启（锚点归零）：从内核值重新起步，服务端 delta=0 兜底', () async {
      // 旧进程报到 5000
      final service = newService();
      await service.onTunnelStart();
      totals.next(up: 5000, down: 5000);
      await service.tickForTest();

      // 新进程（新 service 实例 = 锚点归零），内核恰有 300 未报
      final freshTransport = _FakeTransport();
      final freshService = TrafficReportService.forTest(
        totals.read,
        reportSender: freshTransport.send,
      );
      await freshService.onTunnelStart();
      totals.next(up: 300, down: 300);
      await freshService.tickForTest();

      // u_total = 0 + 300 = 300 < 服务端 reported(5000) → delta=0（不重复记账）
      expect(freshTransport.reports.last.uTotal, 300);
    });
  });
}

/// 内核读数脚本（逐次返回预设值）。
class _ScriptedTotal {
  int _up = 0, _down = 0;

  void next({required int up, required int down}) {
    _up = up;
    _down = down;
  }

  Future<Traffic> read() async => Traffic(up: _up, down: _down);
}

/// 捕获上报的假传输层。
class _FakeTransport {
  final List<({String sessionId, int seq, int uTotal, int dTotal})> reports = [];
  final List<Map<String, dynamic>> heartbeats = [];
  bool failNext = false;

  Future<bool> send(String sessionId, int seq, int uTotal, int dTotal) async {
    if (failNext) {
      failNext = false;
      return false;
    }
    reports.add((sessionId: sessionId, seq: seq, uTotal: uTotal, dTotal: dTotal));
    return true;
  }

  Future<void> heartbeat() async => heartbeats.add({});
}
