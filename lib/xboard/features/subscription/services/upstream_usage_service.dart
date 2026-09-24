import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/vpn.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'managed_subscription_profile.dart';
import 'upstream_transport_config.dart';

/// Owned by the Android service isolate, or the desktop application process.
/// The native core independently expires the lease if this process stalls.
class UpstreamUsageService {
  UpstreamUsageService({
    this.invokeCore,
    this.sendRequest,
    this.profileFile,
    this.journalFile,
    this.validateConfiguration,
    this.createHttp,
    HttpService? httpService,
  }) : _http = httpService;

  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? invokeCore;
  final Future<Map<String, dynamic>> Function(
    String,
    Map<String, dynamic>,
    String,
  )?
  sendRequest;
  final Future<File> Function(String)? profileFile;
  final Future<File> Function()? journalFile;
  final Future<String> Function(String)? validateConfiguration;
  final Future<HttpService> Function(String, HttpConfig)? createHttp;
  static final instance = UpstreamUsageService();
  static const coreVersion = '1.19.0';
  static final estimatedRemaining = ValueNotifier<int?>(null);
  static final _leaseClock = Stopwatch()..start();

  int _ttl(Map<String, dynamic> lease) {
    final received =
        lease['_received_us'] as int? ?? _leaseClock.elapsedMicroseconds;
    return (lease['lease_until'] as int) -
        (lease['server_time'] as int) -
        ((_leaseClock.elapsedMicroseconds - received) / 1000000).ceil();
  }

  static Future<void> refreshDisplay() async {
    try {
      final snapshot = await instance.core({'operation': 'snapshot'});
      estimatedRemaining.value = snapshot['active'] == true
          ? snapshot['remaining'] as int?
          : null;
    } catch (_) {
      estimatedRemaining.value = null;
    }
  }

  HttpService? _http;
  UpstreamTransportConfig? _transportConfig;
  Map<String, dynamic>? _session;
  Timer? _timer;
  Future<void>? _tick;
  Future<void>? _report;
  bool _meterStarted = false;
  bool _preparing = false;
  int _generation = 0;
  final Stopwatch _reportClock = Stopwatch();
  bool _stopping = false;
  String? lastReason;

  static String reasonText(String reason) => switch (reason) {
    'expired' => '套餐已到期，请续费后重试',
    'quota_exhausted' => '套餐流量已用完，请购买流量或续费',
    'banned' || 'signed_out' => '账号已停用或登录已失效，请重新登录',
    'period_changed' => '流量周期已更新，请重新连接',
    'configuration_changed' => '节点配置已更新，请刷新订阅后再连接',
    'disabled' => '导入节点暂未开放',
    'device_limit' => '已达到套餐设备数限制',
    'storage_error' => '流量记录保存失败，请检查存储空间后重试',
    _ => '无法续期使用授权，连接已停止，请重试',
  };

  Future<File> get _journal async => journalFile != null
      ? await journalFile!()
      : File('${await appPath.homeDirPath}/upstream-usage.json');

  Future<Map<String, dynamic>> core(Map<String, dynamic> value) async {
    if (invokeCore != null) return invokeCore!(value);
    String raw;
    if (Platform.isAndroid && globalState.isService) {
      final response =
          jsonDecode(
                await ClashLibHandler().invokeAction(
                  jsonEncode({
                    'id': const Uuid().v4(),
                    'method': 'managedSession',
                    'data': jsonEncode(value),
                  }),
                ),
              )
              as Map<String, dynamic>;
      raw = response['data'] as String;
    } else {
      raw = await clashCore.clashInterface.invoke<String>(
        method: ActionMethod.managedSession,
        data: jsonEncode(value),
      );
    }
    if (raw.isEmpty) throw StateError('请更新代理核心后使用导入节点');
    final result = jsonDecode(raw) as Map<String, dynamic>;
    if (result['metering_version'] != 1) throw StateError('代理核心不支持流量计量');
    return result;
  }

  Future<HttpService> _transport() async {
    if (_http != null) return _http!;
    final selected = _transportConfig;
    if (selected != null) {
      return _http = await _createHttp(selected.baseUrl, selected.httpConfig);
    }
    if (XBoardSDK.instance.isInitialized) {
      final original = XBoardSDK.instance.httpService;
      // No account-token interceptor: restricted session tokens must not be replaced.
      return _http = await _createHttp(original.baseUrl, original.httpConfig);
    }
    if (!XBoardConfig.isInitialized) {
      await XBoardConfig.initialize(
        settings: await ConfigFileLoader.loadFromFile(),
      );
    }
    final url = await XBoardConfig.getFastestPanelUrl();
    if (url == null) throw StateError('无法连接授权服务');
    final cert = await ConfigFileLoaderHelper.getCertificateConfig();
    return _http = await _createHttp(
      url,
      HttpConfig(
        encryptedGateway:
            await ConfigFileLoaderHelper.getEncryptedGatewayConfig(),
        userAgent: await UserAgentConfig.get(UserAgentScenario.apiEncrypted),
        certificatePath: cert['path'] as String?,
        enableCertificatePinning:
            cert['enabled'] == true && cert['path'] != null,
      ),
    );
  }

  Future<HttpService> _createHttp(String url, HttpConfig config) =>
      createHttp != null
      ? createHttp!(url, config)
      : HttpService.create(
          url,
          httpConfig: config,
          requireEncryptedGateway: true,
          directConnections: true,
        );

  static Map<String, dynamic> prepareCommand(String profileId) => {
    'operation': 'prepare',
    'profile_id': profileId,
    if (XBoardSDK.instance.isInitialized)
      'transport': UpstreamTransportConfig.fromService(
        XBoardSDK.instance.httpService,
      ).toJson(),
  };

  Future<void> handleControl(Map<String, dynamic> command) async {
    if (command['operation'] == 'prepare') {
      final transport = command['transport'];
      await prepare(
        command['profile_id'] as String,
        transportConfig: transport == null
            ? null
            : UpstreamTransportConfig.fromJson(
                Map<String, dynamic>.from(transport as Map),
              ),
      );
    } else {
      await stop('closed');
    }
  }

  Future<Map<String, dynamic>> _request(
    String action,
    Map<String, dynamic> body,
    String token,
  ) async {
    if (sendRequest != null) return sendRequest!(action, body, token);
    final elapsed = Stopwatch()..start();
    final transport = await _transport();
    final host = Uri.parse(transport.baseUrl).host;
    final addresses = await InternetAddress.lookup(
      host,
    ).timeout(const Duration(seconds: 5));
    await core({
      'operation': 'control',
      'control_hosts': [host, ...addresses.map((address) => address.address)],
    });
    final response = await transport
        .postRequest(
          '/api/v1/upstream/$action',
          body,
          headers: {
            'Authorization': token.startsWith('Bearer ')
                ? token
                : 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));
    // Older plugin releases returned only {data: ...}. The SDK wraps that
    // unrecognized envelope once more; standard Xboard envelopes need one unwrap.
    dynamic data = response['data'];
    if (data is Map && data.length == 1 && data['data'] is Map) {
      data = data['data'];
    }
    if (response['success'] != true ||
        data is! Map ||
        data['allowed'] is! bool ||
        data['status'] is! String) {
      throw StateError('授权接口返回格式异常（$action），请更新面板上游订阅插件后重试');
    }
    final result = Map<String, dynamic>.from(data);
    if (result['allowed'] == true) {
      final validLease =
          result['server_time'] is int &&
          result['lease_until'] is int &&
          result['remaining'] is int &&
          result['period'] is String;
      final validSession =
          action != 'open' ||
          (result['session_id'] is String && result['session_token'] is String);
      final validConfiguration =
          action != 'configuration' ||
          (result['content'] is String && result['nodes'] is Map);
      if (!validLease || !validSession || !validConfiguration) {
        throw StateError('授权接口返回数据不完整（$action），请更新面板上游订阅插件后重试');
      }
    }
    if (result['lease_until'] is int) {
      result['lease_until'] =
          (result['lease_until'] as int) -
          (elapsed.elapsedMilliseconds / 1000).ceil();
      result['_received_us'] = _leaseClock.elapsedMicroseconds;
    }
    return result;
  }

  /// Android UI sends this command to the service isolate; it never owns its timer.
  static Future<void> prepareSelected() async {
    final profile = globalState.config.currentProfile;
    if (profile == null || profile.subscriptionInfo == null) {
      await stopSelected();
      return;
    }
    if (Platform.isAndroid && !globalState.isService) {
      final result = await clashCore.clashInterface.invoke<String>(
        method: ActionMethod.managedControl,
        data: jsonEncode(prepareCommand(profile.id)),
        timeout: const Duration(seconds: 90),
      );
      if (result != 'ok') {
        throw StateError(result.isEmpty ? '授权服务启动失败' : result);
      }
    } else {
      await instance.prepare(profile.id);
    }
  }

  static Future<void> stopSelected() async {
    estimatedRemaining.value = null;
    if (Platform.isAndroid && !globalState.isService) {
      await clashCore.clashInterface.invoke<String>(
        method: ActionMethod.managedControl,
        data: jsonEncode({'operation': 'stop'}),
        timeout: const Duration(seconds: 25),
      );
    } else {
      await instance.stop('closed');
    }
  }

  Future<void> prepare(
    String profileId, {
    UpstreamTransportConfig? transportConfig,
  }) async {
    if (_preparing || _stopping) throw StateError('代理正在启动或停止，请稍后重试');
    _preparing = true;
    try {
      await _prepare(profileId, transportConfig);
    } finally {
      _preparing = false;
    }
  }

  Future<Map<String, dynamic>?> fetchConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final auth = prefs.getString('xboard_token');
    if (auth == null || auth.isEmpty) return null;
    var device = prefs.getString('upstream_device_id');
    if (device == null) {
      device = const Uuid().v4();
      await prefs.setString('upstream_device_id', device);
    }
    Map<String, dynamic> opened;
    try {
      opened = await _request('open', {
        'device_id': device,
        'core': 'mihomo',
        'core_version': coreVersion,
        'metering_version': 1,
        'configuration_only': true,
      }, auth);
    } on XBoardException catch (error) {
      if (error.code == 404) return null;
      rethrow;
    }
    if (opened['status'] == 'disabled') return null;
    if (opened['allowed'] != true) {
      throw StateError(reasonText(opened['status'] as String));
    }
    try {
      final result = await _request(
        'configuration',
        {},
        opened['session_token'] as String,
      );
      if (result['allowed'] != true ||
          result['configuration_version'] is! String ||
          result['configuration_version'] != opened['configuration_version'] ||
          result['content'] is! String ||
          result['nodes'] is! Map) {
        throw StateError('无法导入完整节点配置，请更新面板或重试');
      }
      return result;
    } finally {
      try {
        await _request('close', {
          'period': opened['period'],
          'seq': 1,
          'traffic': <String, dynamic>{},
        }, opened['session_token'] as String);
      } catch (_) {}
    }
  }

  Future<void> _prepare(
    String profileId,
    UpstreamTransportConfig? transportConfig,
  ) async {
    await stop('closed');
    // Finish the old session using its original transport before switching.
    if (transportConfig != null && !transportConfig.matches(_transportConfig)) {
      _http?.dispose();
      _http = null;
      _transportConfig = transportConfig;
    }
    final attempt = ++_generation;
    final file = profileFile != null
        ? await profileFile!(profileId)
        : File(await appPath.getProfilePath(profileId));
    final oldContent = await file.readAsString();
    final hadImportedNodes = RegExp(r'upstream-\d+').hasMatch(oldContent);
    final configurationVersion = await ManagedSubscriptionProfile.version(
      file,
      coreVersion,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final auth = prefs.getString('xboard_token');
    if (auth == null || auth.isEmpty) throw StateError('请先登录');
    var device = prefs.getString('upstream_device_id');
    if (device == null) {
      device = const Uuid().v4();
      await prefs.setString('upstream_device_id', device);
    }
    await _settlePending();
    Map<String, dynamic> opened;
    try {
      opened = await _request('open', {
        'device_id': device,
        'core': 'mihomo',
        'core_version': coreVersion,
        'metering_version': 1,
        'configuration_version': configurationVersion ?? 'missing',
      }, auth);
    } on XBoardException catch (e) {
      if (e.code == 404 && !hadImportedNodes) return;
      rethrow;
    }
    if (opened['allowed'] != true) {
      if (opened['status'] == 'disabled' && !hadImportedNodes) return;
      throw StateError(reasonText(opened['status'] as String));
    }
    if (attempt != _generation || _stopping) throw StateError('启动已取消');
    _session = {...opened, 'seq': 0, 'traffic': <String, dynamic>{}};
    await _persist();
    try {
      if (configurationVersion == null ||
          opened['configuration_version'] != configurationVersion ||
          opened['nodes'] is! Map) {
        throw StateError(reasonText('configuration_changed'));
      }
      final content = oldContent;
      final capability = await core({'operation': 'capabilities'});
      if (capability['metering_version'] != 1) throw StateError('请更新代理核心');
      String validation;
      if (validateConfiguration != null) {
        validation = await validateConfiguration!(content);
      } else if (Platform.isAndroid && globalState.isService) {
        final response =
            jsonDecode(
                  await ClashLibHandler().invokeAction(
                    jsonEncode({
                      'id': const Uuid().v4(),
                      'method': 'validateConfig',
                      'data': content,
                    }),
                  ),
                )
                as Map;
        validation = response['data'] as String;
      } else {
        validation = await clashCore.validateConfig(content);
      }
      if (validation.isNotEmpty) throw StateError('节点配置校验失败');
      if (await ManagedSubscriptionProfile.version(file, coreVersion) !=
          configurationVersion) {
        throw StateError(reasonText('configuration_changed'));
      }
      if (attempt != _generation || _stopping) throw StateError('启动已取消');
      final nodes = Map<String, dynamic>.from(opened['nodes'] as Map);
      final started = await core({
        'operation': 'begin',
        'tags': nodes.map((tag, node) => MapEntry(tag, '${node['id']}')),
        'remaining': opened['remaining'],
        'ttl': _ttl(opened),
        'deadline_reason': opened['deadline_reason'],
      });
      _meterStarted = true;
      if ((started['reason'] as String).isNotEmpty) {
        throw StateError(reasonText(started['reason'] as String));
      }
      lastReason = null;
      _reportClock
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_tick == null && !_stopping) {
          _tick = checkpoint().whenComplete(() => _tick = null);
        }
      });
    } catch (_) {
      await stop('authorization_timeout');
      rethrow;
    }
  }

  Future<void> checkpoint({bool reportNow = false}) async {
    if (_session == null || _stopping) return;
    try {
      final snapshot = await core({'operation': 'snapshot'});
      if (_stopping || _session == null) return;
      _session!['traffic'] = snapshot['traffic'];
      await _persist();
      final reason = snapshot['reason'] as String;
      if (reason.isNotEmpty) {
        unawaited(_terminate(reason));
        return;
      }
      if (_report != null ||
          (!reportNow && _reportClock.elapsed < const Duration(seconds: 30))) {
        return;
      }
      _reportClock.reset();
      _session!['seq'] = (_session!['seq'] as int) + 1;
      await _persist();
      final session = Map<String, dynamic>.from(_session!);
      // Network latency must not block the independent five-second journal.
      _report = _sendReport(session).whenComplete(() => _report = null);
    } catch (_) {
      // A broken local ledger cannot safely continue accumulating billable data.
      unawaited(_terminate('storage_error'));
    }
  }

  Future<void> _sendReport(Map<String, dynamic> session) async {
    try {
      final result = await _request(
        'report',
        _payload(session),
        session['session_token'] as String,
      );
      if (_stopping || _session?['session_id'] != session['session_id']) return;
      if (result['allowed'] != true) {
        unawaited(_terminate(result['status'] as String));
        return;
      }
      final renewed = await core({
        'operation': 'renew',
        'remaining': result['remaining'],
        'confirmed': result['confirmed'],
        'ttl': _ttl(result),
        'deadline_reason': result['deadline_reason'],
      });
      if ((renewed['reason'] as String).isNotEmpty) {
        unawaited(_terminate(renewed['reason'] as String));
      }
    } catch (_) {
      // Keep cumulative counters. The native watchdog enforces the existing lease.
    }
  }

  Future<void> _terminate(String reason) async {
    lastReason = reason;
    await stop(reason);
    if (Platform.isAndroid && globalState.isService) {
      await app?.tip(reasonText(reason));
      await vpn?.stop();
    } else {
      globalState.showNotifier(reasonText(reason));
      await globalState.appController.updateStatus(false);
    }
  }

  Future<void> stop(String reason) async {
    _generation++;
    if (_stopping) return;
    _stopping = true;
    _timer?.cancel();
    _timer = null;
    try {
      // Stop traffic before waiting for any disk or network operation.
      final stopped = _meterStarted
          ? await core({'operation': 'stop', 'reason': reason})
          : null;
      await _tick;
      if (_session == null) return;
      if (stopped != null) _session!['traffic'] = stopped['traffic'];
      _session!['stop_reason'] = reason;
      _session!['seq'] = (_session!['seq'] as int) + 1;
      try {
        await _persist();
        await _request(
          'close',
          _payload(_session!),
          _session!['session_token'] as String,
        );
        final journal = await _journal;
        if (await journal.exists()) await journal.delete();
      } catch (_) {
        /* Next online start settles this journal before opening another session. */
      }
      _session = null;
    } finally {
      _meterStarted = false;
      _stopping = false;
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic> session) => {
    'period': session['period'],
    'seq': session['seq'],
    'traffic': session['traffic'],
    if (session['stop_reason'] != null) 'stop_reason': session['stop_reason'],
  };

  Future<void> _settlePending() async {
    final journal = await _journal;
    if (!await journal.exists()) return;
    final pending =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    pending['seq'] = (pending['seq'] as int) + 1;
    await _request(
      'close',
      _payload(pending),
      pending['session_token'] as String,
    );
    await journal.delete();
  }

  Future<void> _persist() async {
    final journal = await _journal;
    final staged = File('${journal.path}.tmp');
    await staged.writeAsString(jsonEncode(_session), flush: true);
    await staged.rename(journal.path);
  }
}
