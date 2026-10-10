import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/clash/core.dart';
import 'package:fl_clash/xboard/core/core.dart';

import 'upstream_routing_resolver.dart';

final _logger = FileLogger('traffic_report_service.dart');

/// 上游模式流量上报（仅上游路由激活时运行）。
///
/// ## 跨会话锚点（本类核心不变量）
///
/// 内核 `getTotalTraffic()` 在隧道停止时被 `resetTraffic()` 清零，朴素差分
/// 会产生巨大负数。本服务维护「进程生命周期内已成功上报的逻辑累计」
/// `_accountedU/_accountedD`：
///
/// ```
/// u_total = _accountedU + kernelTotal.up     // 单调递增，跨会话不回落
/// ```
///
/// - 上报成功 → `_accounted = u_total`（推进锚点）
/// - 隧道重启（kernel 归零）→ 锚点保留 → 下一 tick `u_total = _accounted + 0`
///   → 无新增，不重复记账
/// - 进程重启 → 锚点归零 → 服务端 `delta = max(0, u_total - reported_u) = 0`
///   → 最多丢最后一个上报周期的流量（Q5，接受）
///
/// ## 幂等（单 in-flight 模型）
///
/// 同一 `(session_id, seq)` 的 payload 失败后原样重发，服务端 receipt
/// 唯一索引兜底；`duplicate:true` 视为成功。任一时刻至多一条未确认上报，
/// 60s 周期下足够保守。
class TrafficReportService {
  /// 全局单例：会话锚点必须跨页面/跨会话存活，不能随 Riverpod provider 重建。
  static final TrafficReportService instance = TrafficReportService();

  /// 上报周期。对齐面板 check:traffic-exceeded 每分钟节奏（超摘延迟 ≤2min），
  /// 设备 TTL 10min 有 10 倍冗余，流量成本 ~200B/min。
  static const Duration reportInterval = Duration(seconds: 60);

  /// 无新增流量时的心跳周期（与上报同频即可，保住设备在线计数）。
  static const Duration heartbeatInterval = reportInterval;

  /// 仅测试用：注入内核读取函数与发送器。
  @visibleForTesting
  TrafficReportService.forTest(
    TrafficTotalReader totalReader, {
    ReportSender? reportSender,
    HeartbeatSender? heartbeatSender,
  })  : _readTotal = totalReader,
        _reportSender = reportSender ?? _defaultReportSender,
        _heartbeatSender = heartbeatSender ?? _defaultHeartbeatSender {
    _testMode = true;
  }

  TrafficReportService._()
      : _readTotal = _defaultReadTotal,
        _reportSender = _defaultReportSender,
        _heartbeatSender = _defaultHeartbeatSender;

  /// 内核累计流量读取（可注入，测试用）。返回自本次隧道启动以来的累计字节。
  final TrafficTotalReader _readTotal;

  /// 上报发送器（可注入，测试用）。返回是否成功（duplicate 也算成功）。
  final ReportSender _reportSender;

  /// 心跳发送器（可注入，测试用）。
  final HeartbeatSender _heartbeatSender;

  /// 测试钩子：手动触发一次周期逻辑。
  @visibleForTesting
  Future<void> tickForTest() => _tick();

  // ---- 会话锚点（内存，不落盘 —— D1）----
  String? _sessionId;
  int _seq = 0;
  int _accountedU = 0;
  int _accountedD = 0;
  _PendingReport? _pending;

  Timer? _timer;
  Timer? _heartbeatTimer;
  bool _running = false;
  bool _testMode = false;
  String? _deviceIdCache;
  DateTime? _lastHeartbeatAt;

  bool get isRunning => _running;

  /// 隧道启动（controller.updateStatus(true) 后调用）。
  Future<void> onTunnelStart() async {
    if (_running) return;
    _running = true;
    _sessionId = _newSessionId();
    _seq = 0;
    // 锚点 _accounted 保留：跨会话连续（见类注释）
    _logger.info('流量上报会话启动: $_sessionId (锚点 u=$_accountedU d=$_accountedD)');
    _timer?.cancel();
    _timer = Timer.periodic(reportInterval, (_) => _tick());
  }

  /// 隧道停止（必须在 controller 调 resetTraffic() 之前调用，flush 尾部）。
  Future<void> onTunnelStop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      await _flushOnce();
    } catch (e) {
      _logger.warning('隧道停止时 flush 失败（最多丢本周期流量）', e);
    }
    _logger.info('流量上报会话结束: $_sessionId (锚点 u=$_accountedU d=$_accountedD)');
  }

  Future<void> _tick() async {
    try {
      if (!_testMode) {
        final routing = UpstreamRoutingResolver.cached;
        if (routing == null || !routing.reportEnabled) return;
        final token = UpstreamRoutingResolver.panelSubscribeToken;
        if (token == null || token.isEmpty) {
          _logger.warning('面板订阅 token 缺失，跳过上报');
          return;
        }
      }

      // 1) 有未确认的上报 → 优先重发（同 seq，服务端幂等）
      if (_pending != null) {
        if (await _send(_pending!)) {
          _accountedU = _pending!.uTotal;
          _accountedD = _pending!.dTotal;
          _pending = null;
        }
        return;
      }

      // 2) 读内核累计，算逻辑总量
      final total = await _readTotal();
      final uTotal = _accountedU + total.up.value.toInt();
      final dTotal = _accountedD + total.down.value.toInt();

      // 3) 无新增 → 心跳（保住设备在线计数，不记流量）
      if (uTotal == _accountedU && dTotal == _accountedD) {
        await _maybeHeartbeat();
        return;
      }

      // 4) 新上报（seq 自增，失败挂起等下周期重发）
      _seq++;
      final pending = _PendingReport(
        sessionId: _sessionId ?? _newSessionId(),
        seq: _seq,
        uTotal: uTotal,
        dTotal: dTotal,
      );
      if (await _send(pending)) {
        _accountedU = uTotal;
        _accountedD = dTotal;
      } else {
        _pending = pending;
      }
    } catch (e) {
      _logger.warning('上报 tick 异常（下周期重试）', e);
    }
  }

  /// 隧道停止前的尾部 flush：把内核最终读数报上去。
  Future<void> _flushOnce() async {
    if (!_testMode) {
      final routing = UpstreamRoutingResolver.cached;
      final token = UpstreamRoutingResolver.panelSubscribeToken;
      if (routing == null || !routing.reportEnabled || token == null) return;
    }

    if (_pending != null) {
      if (await _send(_pending!)) {
        _accountedU = _pending!.uTotal;
        _accountedD = _pending!.dTotal;
        _pending = null;
      }
      return; // 上次的都没确认，本次尾部下周期补（或丢，Q5）
    }

    final total = await _readTotal();
    final uTotal = _accountedU + total.up.value.toInt();
    final dTotal = _accountedD + total.down.value.toInt();
    if (uTotal == _accountedU && dTotal == _accountedD) return;

    _seq++;
    final pending = _PendingReport(
      sessionId: _sessionId ?? _newSessionId(),
      seq: _seq,
      uTotal: uTotal,
      dTotal: dTotal,
    );
    if (await _send(pending)) {
      _accountedU = uTotal;
      _accountedD = dTotal;
    } else {
      _pending = pending; // 进程若随隧道一起退出则丢失（Q5：≤60s）
    }
  }

  Future<void> _maybeHeartbeat() async {
    final now = DateTime.now();
    if (_lastHeartbeatAt != null &&
        now.difference(_lastHeartbeatAt!) < heartbeatInterval) {
      return;
    }
    _lastHeartbeatAt = now;
    try {
      await _heartbeatSender();
    } catch (e) {
      _logger.debug('心跳失败（不影响流量，下周期重试）: $e');
    }
  }

  Future<bool> _send(_PendingReport report) async {
    try {
      return await _reportSender(
        report.sessionId,
        report.seq,
        report.uTotal,
        report.dTotal,
      );
    } catch (e) {
      _logger.warning(
        '上报 ${report.sessionId}#${report.seq} 失败（下周期重发同 seq）',
        e,
      );
      return false;
    }
  }

  /// 稳定设备标识（软配额去重计数用）。首启生成，落盘 `<dataDir>/upstream_device_id`。
  /// 非凭据（不含任何 secret），明文文件存储符合 D1。
  Future<String> get deviceId async {
    if (_deviceIdCache != null) return _deviceIdCache!;
    try {
      final dirPath = await appPath.homeDirPath;
      final file = File(
        '$dirPath${Platform.pathSeparator}upstream_device_id',
      );
      if (await file.exists()) {
        final saved = (await file.readAsString()).trim();
        if (saved.length == 32) {
          _deviceIdCache = saved;
          return saved;
        }
      }
      final generated = _newSessionId(); // 32 hex
      await file.writeAsString(generated, flush: true);
      _deviceIdCache = generated;
      return generated;
    } catch (e) {
      // 文件系统不可用时退化为内存 ID（进程重启变化 → 会被计为新设备，可接受）
      _logger.warning('device_id 持久化失败，退化为内存 ID', e);
      _deviceIdCache ??= _newSessionId();
      return _deviceIdCache!;
    }
  }

  /// 32 hex（测试可见）。
  static String newSessionId() => _newSessionId();
}

/// 内核累计读取函数签名（可注入）。
typedef TrafficTotalReader = Future<Traffic> Function();

/// 上报发送器签名（可注入）。返回是否成功（服务端 duplicate:true 视为成功）。
typedef ReportSender = Future<bool> Function(
  String sessionId,
  int seq,
  int uTotal,
  int dTotal,
);

/// 心跳发送器签名（可注入）。
typedef HeartbeatSender = Future<void> Function();

Future<Traffic> _defaultReadTotal() => clashCore.getTotalTraffic();

Future<bool> _defaultReportSender(
  String sessionId,
  int seq,
  int uTotal,
  int dTotal,
) async {
  final service = TrafficReportService.instance;
  final token = UpstreamRoutingResolver.panelSubscribeToken;
  if (token == null || token.isEmpty) {
    throw StateError('panel subscribe token missing');
  }
  final deviceId = await service.deviceId;
  final result = await XBoardSDK.instance.httpService.postRequest(
    '/api/v1/client/upstream/report',
    {
      'token': token,
      'device_id': deviceId,
      'session_id': sessionId,
      'seq': seq,
      'u_total': uTotal,
      'd_total': dTotal,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'platform': Platform.operatingSystem,
    },
  );
  final data = result['data'];
  if (data is Map && data['duplicate'] == true) {
    // 服务端已入账（重试竞态），按成功处理并推进本地锚点
    FileLogger('traffic_report_service.dart')
        .debug('上报 $sessionId#$seq 命中幂等 duplicate');
  }
  return true;
}

Future<void> _defaultHeartbeatSender() async {
  final token = UpstreamRoutingResolver.panelSubscribeToken;
  if (token == null || token.isEmpty) {
    throw StateError('panel subscribe token missing');
  }
  final deviceId = await TrafficReportService.instance.deviceId;
  await XBoardSDK.instance.httpService.postRequest(
    '/api/v1/client/upstream/devices/heartbeat',
    {'token': token, 'device_id': deviceId},
  );
}

class _PendingReport {
  final String sessionId;
  final int seq;
  final int uTotal;
  final int dTotal;

  const _PendingReport({
    required this.sessionId,
    required this.seq,
    required this.uTotal,
    required this.dTotal,
  });
}

String _newSessionId() {
  final random = Random.secure();
  return List.generate(32, (_) => '0123456789abcdef'[random.nextInt(16)]).join();
}
