import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/features/profile/profile.dart';
import 'package:fl_clash/xboard/features/subscription/services/encrypted_subscription_service.dart';
import 'package:fl_clash/xboard/features/subscription/utils/utils.dart';
import 'package:fl_clash/xboard/core/core.dart';

// 初始化文件级日志器
final _logger = FileLogger('profile_import_service.dart');

final xboardProfileImportServiceProvider = Provider<XBoardProfileImportService>((ref) {
  return XBoardProfileImportService(ref);
});
class XBoardProfileImportService {
  final Ref _ref;
  bool _isImporting = false;
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration downloadTimeout = Duration(seconds: 30);
  XBoardProfileImportService(this._ref);
  Future<ImportResult> importSubscription(
    String url, {
    Function(ImportStatus, double, String?)? onProgress,
  }) async {
    if (_isImporting) {
      return ImportResult.failure(
        errorMessage: '正在导入中，请稍候',
        errorType: ImportErrorType.unknownError,
      );
    }
    _isImporting = true;
    final stopwatch = Stopwatch()..start();
    try {
      _logger.info('开始导入订阅配置: $url');
      
      // 1. 先下载并验证新配置（不删除旧配置）
      onProgress?.call(ImportStatus.downloading, 0.3, '下载配置文件');
      final profile = await _downloadAndValidateProfile(url);
      onProgress?.call(ImportStatus.validating, 0.6, '验证配置格式');
      
      // 2. 下载成功后，再清理旧配置（避免 UI 闪烁显示"无订阅"）
      onProgress?.call(ImportStatus.cleaning, 0.8, '替换旧的订阅配置');
      await _cleanOldUrlProfiles();
      
      // 3. 添加新配置
      onProgress?.call(ImportStatus.adding, 0.9, '添加到配置列表');
      await _addProfile(profile);
      
      stopwatch.stop();
      onProgress?.call(ImportStatus.success, 1.0, '导入成功');
      _logger.info('订阅配置导入成功，耗时: ${stopwatch.elapsedMilliseconds}ms');
      return ImportResult.success(
        profile: profile,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      _logger.error('订阅配置导入失败', e);
      final errorType = _classifyError(e);
      final userMessage = _getUserFriendlyErrorMessage(e, errorType);
      onProgress?.call(ImportStatus.failed, 0.0, userMessage);
      return ImportResult.failure(
        errorMessage: userMessage,
        errorType: errorType,
        duration: stopwatch.elapsed,
      );
    } finally {
      _isImporting = false;
    }
  }
  Future<ImportResult> importSubscriptionWithRetry(
    String url, {
    Function(ImportStatus, double, String?)? onProgress,
    int retries = maxRetries,
  }) async {
    for (int attempt = 1; attempt <= retries; attempt++) {
      _logger.debug('导入尝试 $attempt/$retries');
      final result = await importSubscription(url, onProgress: onProgress);
      if (result.isSuccess) {
        return result;
      }
      if (result.errorType != ImportErrorType.networkError && 
          result.errorType != ImportErrorType.downloadError) {
        return result;
      }
      if (attempt == retries) {
        return result;
      }
      _logger.debug('等待 ${retryDelay.inSeconds} 秒后重试');
      onProgress?.call(ImportStatus.downloading, 0.0, '第 $attempt 次尝试失败，等待重试...');
      await Future.delayed(retryDelay);
    }
    return ImportResult.failure(
      errorMessage: '多次重试后仍然失败',
      errorType: ImportErrorType.networkError,
    );
  }
  Future<void> _cleanOldUrlProfiles() async {
    try {
      final profiles = globalState.config.profiles;
      final urlProfiles = profiles.where((profile) => profile.type == ProfileType.url).toList();
      
      for (final profile in urlProfiles) {
        _logger.debug('删除旧的URL配置: ${profile.label ?? profile.id}');
        _ref.read(profilesProvider.notifier).deleteProfileById(profile.id);
        _clearProfileEffect(profile.id);
      }
      
      _logger.info('清理了 ${urlProfiles.length} 个旧的URL配置');
    } catch (e) {
      _logger.warning('清理旧配置时出错', e);
      throw Exception('清理旧配置失败: $e');
    }
  }
  Future<Profile> _downloadAndValidateProfile(String url) async {
    try {
      _logger.info('通过加密网关下载订阅配置');
      return await _downloadEncryptedProfile(url).timeout(
        downloadTimeout,
        onTimeout: () {
          throw TimeoutException('下载超时', downloadTimeout);
        },
      );
    } on TimeoutException catch (e) {
      throw Exception('下载超时: ${e.message}');
    } on SocketException catch (e) {
      throw Exception('网络连接失败: ${e.message}');
    } on HttpException catch (e) {
      throw Exception('HTTP请求失败: ${e.message}');
    } catch (e) {
      if (e.toString().contains('validateConfig')) {
        throw Exception('配置文件格式错误: $e');
      }
      throw Exception('下载配置失败: $e');
    }
  }

  /// 下载加密的订阅配置
  Future<Profile> _downloadEncryptedProfile(String url) async {
    try {
      _logger.info('📦 开始下载加密订阅配置流程');

      // 优先从登录数据获取 token；URL 仅用于提取 token，不会作为请求目标。
      String? token;
      SubscriptionResult result;
      
      try {
        _logger.debug('🔑 尝试从登录数据获取token');
        result = await EncryptedSubscriptionService.getSubscriptionSmart(null);

        if (!result.success) {
          // 如果从登录数据获取失败，尝试从URL提取token
          _logger.warning('⚠️ 从登录数据获取失败，尝试从URL提取token: ${result.error}');
          token = SubscriptionUrlHelper.extractTokenFromUrl(url);
          if (token == null) {
            throw Exception('无法从URL中提取token且登录数据获取失败: $url');
          }

          _logger.debug('🔑 从URL提取到token: ${token.substring(0, 8)}...');
          result = await EncryptedSubscriptionService.getSubscriptionSmart(token);
        } else {
          _logger.info('✅ 成功从登录数据获取订阅');
        }
      } catch (e) {
        _logger.warning('⚠️ 登录数据不可用，改从URL提取token', e);
        token = SubscriptionUrlHelper.extractTokenFromUrl(url);
        if (token == null) {
          throw Exception('所有token获取方式都失败: $url');
        }

        _logger.debug('🔄 从URL提取到token: ${token.substring(0, 8)}...');
        result = await EncryptedSubscriptionService.getSubscriptionSmart(token);
      }

      if (!result.success) {
        throw Exception('加密订阅获取失败: ${result.error}');
      }

      _logger.info('🎉 加密订阅获取成功！加密模式: ${result.encryptionUsed}');
      if (result.keyUsed != null) {
        _logger.debug('🔑 使用解密密钥: ${result.keyUsed?.substring(0, 8)}...');
      }
      
      // 验证解密后的配置内容
      _logger.debug('📄 验证解密后的配置内容，长度: ${result.content!.length}');
      if (result.content!.trim().isEmpty) {
        throw Exception('解密后的配置内容为空');
      }

      // 记录配置内容的基本统计信息
      final lines = result.content!.split('\n');
      final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).length;
      _logger.debug('📄 配置内容统计: 总行数 ${lines.length}, 非空行数 $nonEmptyLines');

      // 移除冗余的格式检查，让ClashMeta核心进行权威验证
      _logger.debug('⚡ 跳过客户端格式验证，将由ClashMeta核心进行权威验证');

      // 创建Profile并保存解密的配置内容
      _logger.debug('💾 开始保存解密的配置内容到Profile...');
      final profile = Profile.normal().copyWith(autoUpdate: false);
      final profileWithContent = await profile.saveFileWithString(result.content!);
      _logger.info('✅ 配置内容已成功保存并通过ClashMeta核心验证');
      
      // 获取订阅信息并更新Profile
      _logger.info('📊 开始获取加密订阅的订阅信息...');
      final subscriptionInfo = await ProfileSubscriptionInfoService.instance.getSubscriptionInfo(
        subscriptionUserInfo: result.subscriptionUserInfo,
      );
      _logger.info('📊 Profile订阅信息获取完成: upload=${subscriptionInfo.upload}, download=${subscriptionInfo.download}, total=${subscriptionInfo.total}');

      // 返回带有订阅信息的Profile
      final updatedProfile = profileWithContent.copyWith(
        subscriptionInfo: subscriptionInfo,
      );

      _logger.info('🎉 加密配置验证和保存成功！最终Profile订阅信息: ${updatedProfile.subscriptionInfo}');
      _logger.debug('✅ 完整的加密订阅处理流程已成功完成');
      return updatedProfile;
      
    } catch (e) {
      _logger.error('💥 加密配置下载失败', e);
      _logger.debug('❌ 加密订阅处理流程异常终止');
      throw Exception('加密订阅处理失败: $e');
    }
  }

  Future<void> _addProfile(Profile profile) async {
    try {
      // 1. 添加配置到列表
      _ref.read(profilesProvider.notifier).setProfile(profile);
      
      // 2. 强制设置为当前配置（订阅导入是用户主动操作，应该立即生效）
      final currentProfileIdNotifier = _ref.read(currentProfileIdProvider.notifier);
      currentProfileIdNotifier.value = profile.id;
      _logger.info('✅ 已设置为当前配置: ${profile.label ?? profile.id}');
      
      // 3. 使用 silence 模式直接应用配置（新路由系统中 homeScaffoldKey 不可用）
      // needSetupProvider 的监听器会触发 handleChangeProfile，但因为 commonScaffoldState 
      // 未 mounted 会失败，所以我们在这里手动用 silence 模式触发
      _logger.info('📋 使用 silence 模式应用配置...');
      try {
        await globalState.appController.applyProfile(silence: true);
        _logger.info('✅ 配置应用成功');
      } catch (e) {
        _logger.error('❌ 配置应用失败', e);
        // 不抛出异常，因为配置已经保存了
      }
      
      _logger.info('配置添加成功: ${profile.label ?? profile.id}');
    } catch (e) {
      throw Exception('添加配置失败: $e');
    }
  }
  void _clearProfileEffect(String profileId) {
    try {
      if (globalState.config.currentProfileId == profileId) {
        final profiles = globalState.config.profiles;
        final currentProfileIdNotifier = _ref.read(currentProfileIdProvider.notifier);
        if (profiles.isNotEmpty) {
          final updateId = profiles.first.id;
          currentProfileIdNotifier.value = updateId;
        } else {
          currentProfileIdNotifier.value = null;
          globalState.appController.updateStatus(false);
        }
      }
    } catch (e) {
      _logger.warning('清理配置缓存时出错', e);
    }
  }
  ImportErrorType _classifyError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('timeout') || 
        errorString.contains('连接失败') ||
        errorString.contains('network')) {
      return ImportErrorType.networkError;
    }
    if (errorString.contains('下载') || 
        errorString.contains('http') ||
        errorString.contains('响应')) {
      return ImportErrorType.downloadError;
    }
    if (errorString.contains('validateconfig') ||
        errorString.contains('格式错误') ||
        errorString.contains('解析') ||
        errorString.contains('配置文件格式错误') ||
        errorString.contains('clash配置') ||
        errorString.contains('invalid config')) {
      return ImportErrorType.validationError;
    }
    if (errorString.contains('存储') || 
        errorString.contains('文件') ||
        errorString.contains('保存')) {
      return ImportErrorType.storageError;
    }
    return ImportErrorType.unknownError;
  }
  String _getUserFriendlyErrorMessage(dynamic error, ImportErrorType errorType) {
    final errorString = error.toString();
    
    switch (errorType) {
      case ImportErrorType.networkError:
        return '网络连接失败，请检查网络设置后重试';
      case ImportErrorType.downloadError:
        // 特殊处理User-Agent相关错误
        if (errorString.contains('Invalid HTTP header field value')) {
          return '配置文件下载失败：HTTP请求头格式错误，请稍后重试';
        }
        if (errorString.contains('FormatException')) {
          return '配置文件下载失败：请求格式错误，请稍后重试';
        }
        return '配置文件下载失败，请检查订阅链接是否正确';
      case ImportErrorType.validationError:
        return '配置文件格式验证失败，请联系服务提供商检查配置格式';
      case ImportErrorType.storageError:
        return '保存配置失败，请检查存储空间';
      case ImportErrorType.unknownError:
        // 简化未知错误的显示，避免显示技术细节
        if (errorString.contains('Invalid HTTP header field value') || 
            errorString.contains('FormatException')) {
          return '导入失败：应用配置错误，请稍后重试或重启应用';
        }
        return '导入失败，请稍后重试或联系技术支持';
    }
  }
  bool get isImporting => _isImporting;
} 