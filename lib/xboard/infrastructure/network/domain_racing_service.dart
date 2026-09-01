/// 域名竞速服务
///
/// 实现多个域名并发测试，选择响应最快的域名
library;

import 'dart:async';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';

// 初始化文件级日志器
final _logger = FileLogger('domain_racing_service.dart');

/// 域名竞速服务
class DomainRacingService {
  static const Duration _connectionTimeout = Duration(seconds: 5);
  static const Duration _responseTimeout = Duration(seconds: 8);
  
  /// 设置证书路径（由配置加载器调用）
  static void setCertificatePath(String path) {
    _configuredCertPath = path;
  }

  static String? _configuredCertPath;

  /// 并发竞速选择最快域名
  ///
  /// [domains] 要测试的域名列表
  /// [testPath] 用于测试的路径，默认为空（只测试连通性）
  /// [forceHttpsResult] 是否强制返回HTTPS格式的结果（用于SDK初始化）
  /// [proxyUrls] 可选的代理地址列表，每个域名会测试直连+所有代理
  ///
  /// 返回最快响应的结果（包含域名和是否使用代理），如果所有域名都失败则返回null
  static Future<DomainRacingResult?> raceSelectFastestDomain(
    List<String> domains, {
    String testPath = '',
    bool forceHttpsResult = false,
    List<String>? proxyUrls,
  }) async {
    if (domains.isEmpty) return null;
    
    final proxies = proxyUrls ?? [];
    final testCount = domains.length * (1 + proxies.length);
    
    _logger.info('[域名竞速] 开始竞速测试 ${domains.length} 个域名${proxies.isNotEmpty ? '（每个测试直连+${proxies.length}个代理）' : ''}，共 $testCount 个测试');

    // 创建并发测试任务
    final List<Future<DomainTestResult>> futures = [];
    final List<CancelToken> cancelTokens = [];

    int taskIndex = 0;
    for (int i = 0; i < domains.length; i++) {
      final domain = domains[i];
      
      // 测试直连
      final directToken = CancelToken();
      cancelTokens.add(directToken);
      futures.add(_testSingleDomain(domain, directToken, taskIndex++, useProxy: false));
      
      // 测试所有代理
      for (final proxyUrl in proxies) {
        final proxyToken = CancelToken();
        cancelTokens.add(proxyToken);
        futures.add(_testSingleDomain(domain, proxyToken, taskIndex++, useProxy: true, proxyUrl: proxyUrl));
      }
    }

    try {
      // 创建竞速逻辑
      final completer = Completer<DomainRacingResult?>();
      int completedCount = 0;
      final errors = <String>[];

      for (int i = 0; i < futures.length; i++) {
        futures[i].then((result) {
          if (!completer.isCompleted && result.success) {
            // 第一个成功的获胜
            final connectionType = result.useProxy ? '代理: ${result.proxyUrl}' : '直连';
            _logger.info(
                '[域名竞速] 🏆 域名 #$i (${result.domain}) [$connectionType] 获胜！响应时间: ${result.responseTime}ms');
            
            // 保存获胜结果（包含域名和代理信息）
            final racingResult = DomainRacingResult(
              domain: result.domain,
              useProxy: result.useProxy,
              proxyUrl: result.useProxy ? result.proxyUrl : null,
              responseTime: result.responseTime,
            );
            completer.complete(racingResult);

            // 注释掉取消逻辑，让所有测试都完成，方便查看每个域名+代理的连通状况
            // for (int j = 0; j < cancelTokens.length; j++) {
            //   if (j != i) cancelTokens[j].cancel();
            // }
          } else {
            completedCount++;
            if (result.error != null) {
              final connectionType = result.useProxy ? '代理: ${result.proxyUrl}' : '直连';
              _logger.info(
                  '[域名竞速] ❌ 域名 #$i (${result.domain}) [$connectionType] 失败: ${result.error}, 用时: ${result.responseTime}ms');
              errors.add('域名#$i (${result.domain}) [$connectionType]: ${result.error}');
            }

            // 如果所有测试都完成且都失败了
            if (completedCount == futures.length && !completer.isCompleted) {
              _logger.warning('[域名竞速] 所有域名测试都失败: ${errors.join('; ')}');
              completer.complete(null);
            }
          }
        }).catchError((e) {
          completedCount++;
          errors.add('域名#$i异常: $e');

          if (completedCount == futures.length && !completer.isCompleted) {
            _logger.warning('[域名竞速] 所有域名测试都失败: ${errors.join('; ')}');
            completer.complete(null);
          }
        });
      }

      // 等待第一个完成
      final winner = await completer.future;

      // 如果需要强制HTTPS结果，转换获胜域名
      if (winner != null && forceHttpsResult) {
        final httpsUrl = _convertToHttpsUrl(winner.domain);
        return DomainRacingResult(
          domain: httpsUrl,
          useProxy: winner.useProxy,
          proxyUrl: winner.proxyUrl,
          responseTime: winner.responseTime,
        );
      }

      return winner;
    } catch (e) {
      _logger.error('[域名竞速] 竞速测试异常', e);
      return null;
    }
  }

  /// 测试单个域名
  static Future<DomainTestResult> _testSingleDomain(
    String domain,
    CancelToken cancelToken,
    int index, {
    bool useProxy = false,
    String? proxyUrl,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final connectionType = useProxy ? '代理: $proxyUrl' : '直连';
      _logger.info('[域名竞速] 开始测试域名 #$index: $domain [$connectionType]');

      await ConfigFileLoaderHelper.getEncryptedGatewayConfig();
      return await _testEncryptedDomain(
        domain,
        cancelToken,
        stopwatch,
        useProxy: useProxy,
        proxyUrl: proxyUrl,
      );
    } on TimeoutException {
      stopwatch.stop();
      _logger.info('[域名竞速] 域名 #$index ($domain) 超时');
      return DomainTestResult.failure(
          domain, '连接超时', stopwatch.elapsedMilliseconds, useProxy: useProxy, proxyUrl: proxyUrl);
    } catch (e) {
      stopwatch.stop();
      if (cancelToken.isCancelled) {
        _logger.info('[域名竞速] 域名 #$index ($domain) 被正常取消');
        return DomainTestResult.failure(
            domain, '测试被取消', stopwatch.elapsedMilliseconds, useProxy: useProxy, proxyUrl: proxyUrl);
      }

      _logger.info('[域名竞速] 域名 #$index ($domain) 测试失败: $e');
      return DomainTestResult.failure(
          domain, '连接失败: $e', stopwatch.elapsedMilliseconds, useProxy: useProxy, proxyUrl: proxyUrl);
    }
  }

  static Future<DomainTestResult> _testEncryptedDomain(
    String domain,
    CancelToken cancelToken,
    Stopwatch stopwatch, {
    required bool useProxy,
    String? proxyUrl,
  }) async {
    HttpService? service;
    try {
      final gateway = await ConfigFileLoaderHelper.getEncryptedGatewayConfig();
      final userAgent = await UserAgentConfig.get(UserAgentScenario.apiEncrypted);
      service = await HttpService.create(
        _convertToHttpsUrl(domain),
        httpConfig: HttpConfig(
          encryptedGateway: gateway,
          userAgent: userAgent,
          proxyUrl: useProxy ? proxyUrl : null,
          certificatePath: _configuredCertPath,
          enableCertificatePinning:
              _configuredCertPath != null && _configuredCertPath!.isNotEmpty,
          connectTimeoutSeconds: _connectionTimeout.inSeconds,
          receiveTimeoutSeconds: _responseTimeout.inSeconds,
          sendTimeoutSeconds: _responseTimeout.inSeconds,
        ),
      );
      await service.getRequest('/api/v1/guest/comm/config');
      stopwatch.stop();
      if (cancelToken.isCancelled) {
        return DomainTestResult.failure(
          domain,
          '测试被取消',
          stopwatch.elapsedMilliseconds,
          useProxy: useProxy,
          proxyUrl: proxyUrl,
        );
      }
      return DomainTestResult.success(
        domain,
        stopwatch.elapsedMilliseconds,
        useProxy: useProxy,
        proxyUrl: proxyUrl,
      );
    } catch (error) {
      stopwatch.stop();
      return DomainTestResult.failure(
        domain,
        '加密探测失败',
        stopwatch.elapsedMilliseconds,
        useProxy: useProxy,
        proxyUrl: proxyUrl,
      );
    } finally {
      service?.dispose();
    }
  }

  /// 转换域名为HTTPS格式（用于SDK初始化）
  static String _convertToHttpsUrl(String domain) {
    if (domain.startsWith('https://')) {
      return domain;
    } else if (domain.startsWith('http://')) {
      // 如果是HTTP的IP+端口，转换为HTTPS
      final withoutHttp = domain.substring(7); // 移除 "http://"
      return 'https://$withoutHttp';
    } else {
      // 纯域名，添加HTTPS前缀
      return 'https://$domain';
    }
  }

  /// 批量测试所有域名的延迟（不竞速）
  ///
  /// [domains] 要测试的域名列表
  /// [testPath] 用于测试的路径
  ///
  /// 返回所有域名的测试结果
  static Future<List<DomainTestResult>> testAllDomains(
    List<String> domains, {
    String testPath = '',
  }) async {
    if (domains.isEmpty) return [];

    _logger.info('[域名测试] 开始测试 ${domains.length} 个域名的延迟');

    final List<Future<DomainTestResult>> futures =
        domains.asMap().entries.map((entry) {
      final index = entry.key;
      final domain = entry.value;
      return _testSingleDomain(domain, CancelToken(), index);
    }).toList();

    final results = await Future.wait(futures);

    // 按响应时间排序
    results.sort((a, b) {
      if (a.success && !b.success) return -1;
      if (!a.success && b.success) return 1;
      if (a.success && b.success) {
        return a.responseTime.compareTo(b.responseTime);
      }
      return 0;
    });

    _logger.info(
        '[域名测试] 测试完成，成功: ${results.where((r) => r.success).length}/${results.length}');
    return results;
  }
}

/// 域名竞速结果
class DomainRacingResult {
  final String domain; // 获胜域名
  final bool useProxy; // 是否使用代理
  final String? proxyUrl; // 代理地址（如果使用代理）
  final int responseTime; // 响应时间（毫秒）

  const DomainRacingResult({
    required this.domain,
    required this.useProxy,
    this.proxyUrl,
    required this.responseTime,
  });

  @override
  String toString() {
    final proxyInfo = useProxy ? ' [代理: $proxyUrl]' : ' [直连]';
    return 'DomainRacingResult(domain: $domain$proxyInfo, responseTime: ${responseTime}ms)';
  }
}

/// 域名测试结果
class DomainTestResult {
  final String domain;
  final bool success;
  final int responseTime;
  final String? error;
  final bool useProxy; // 是否使用代理
  final String? proxyUrl; // 使用的代理地址

  const DomainTestResult._({
    required this.domain,
    required this.success,
    required this.responseTime,
    this.error,
    this.useProxy = false,
    this.proxyUrl,
  });

  factory DomainTestResult.success(String domain, int responseTime, {bool useProxy = false, String? proxyUrl}) {
    return DomainTestResult._(
      domain: domain,
      success: true,
      responseTime: responseTime,
      useProxy: useProxy,
      proxyUrl: proxyUrl,
    );
  }

  factory DomainTestResult.failure(
      String domain, String error, int responseTime, {bool useProxy = false, String? proxyUrl}) {
    return DomainTestResult._(
      domain: domain,
      success: false,
      responseTime: responseTime,
      error: error,
      useProxy: useProxy,
      proxyUrl: proxyUrl,
    );
  }

  @override
  String toString() {
    final proxyInfo = useProxy ? ' [代理: $proxyUrl]' : ' [直连]';
    if (success) {
      return 'DomainTestResult(domain: $domain$proxyInfo, success: $success, responseTime: ${responseTime}ms)';
    } else {
      return 'DomainTestResult(domain: $domain$proxyInfo, success: $success, error: $error, responseTime: ${responseTime}ms)';
    }
  }
}

/// 取消令牌
class CancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

