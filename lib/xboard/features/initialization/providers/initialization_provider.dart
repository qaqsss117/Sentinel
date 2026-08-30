import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/features/domain_status/providers/domain_status_provider.dart';
import 'package:fl_clash/xboard/features/domain_status/models/domain_status_state.dart';
import 'package:fl_clash/xboard/adapter/initialization/sdk_provider.dart';

import '../models/initialization_state.dart';

// 初始化文件级日志器
final _logger = FileLogger('initialization_provider.dart');

/// XBoard 统一初始化 Provider
/// 
/// 封装整个初始化流程：
/// 1. 域名检查（域名竞速）
/// 2. SDK 初始化
/// 
/// 提供统一的初始化入口和状态管理
class XBoardInitializationNotifier extends StateNotifier<InitializationState> {
  final Ref ref;
  
  XBoardInitializationNotifier(this.ref) : super(const InitializationState()) {
    _logger.info('[Initialization] Provider 已创建');
  }
  
  /// 统一初始化入口
  /// 
  /// 执行完整的初始化流程，包括：
  /// - 域名检查（竞速）
  /// - SDK 初始化
  /// 
  /// 如果已经初始化完成，会直接返回（幂等性）
  Future<void> initialize() async {
    // 如果已经就绪，跳过初始化
    if (state.isReady) {
      _logger.info('[Initialization] ✅ 已初始化，跳过重复执行');
      return;
    }
    
    // 如果正在初始化，避免重复触发
    if (state.isInitializing) {
      _logger.info('[Initialization] ⏳ 正在初始化中，跳过重复触发');
      return;
    }
    
    try {
      _logger.info('[Initialization] 🚀 开始初始化流程');
      
      // ========== 步骤 1: 检查域名 ==========
      _logger.info('[Initialization] 📡 步骤 1/2: 检查域名');
      state = state.copyWith(
        status: InitializationStatus.checkingDomain,
        errorMessage: null,
        currentStepDescription: '正在检查域名可用性...',
      );
      
      // 触发域名检查
      await ref.read(domainStatusProvider.notifier).checkDomain();
      
      // 获取域名检查结果
      final domainStatus = ref.read(domainStatusProvider);
      
      if (domainStatus.status == DomainStatus.failed) {
        throw Exception(domainStatus.errorMessage ?? '域名不可用');
      }
      
      if (!domainStatus.isReady) {
        throw Exception('域名状态未就绪');
      }
      
      _logger.info('[Initialization] ✅ 域名检查完成: ${domainStatus.currentDomain}');
      
      // ========== 步骤 2: 初始化 SDK ==========
      _logger.info('[Initialization] 🔧 步骤 2/2: 初始化 SDK');
      state = state.copyWith(
        status: InitializationStatus.initializingSDK,
        currentDomain: domainStatus.currentDomain,
        latency: domainStatus.latency,
        currentStepDescription: '正在初始化 SDK...',
      );
      
      // 等待 SDK 初始化完成
      await ref.read(xboardSdkProvider.future);
      
      _logger.info('[Initialization] ✅ SDK 初始化完成');
      
      // ========== 完成 ==========
      _logger.info('[Initialization] 🎉 初始化流程完成');
      state = state.copyWith(
        status: InitializationStatus.ready,
        lastChecked: DateTime.now(),
        currentStepDescription: '初始化完成',
        errorMessage: null,
      );
      
    } catch (e, stackTrace) {
      _logger.error('[Initialization] ❌ 初始化失败', e, stackTrace);
      
      state = state.copyWith(
        status: InitializationStatus.failed,
        errorMessage: e.toString(),
        currentStepDescription: '初始化失败',
      );
      
      rethrow;
    }
  }
  
  /// 刷新（重新初始化）
  /// 
  /// 重置状态并重新执行完整的初始化流程
  Future<void> refresh() async {
    _logger.info('[Initialization] 🔄 刷新初始化状态');
    
    // 重置状态
    state = const InitializationState();
    
    // 重新初始化
    await initialize();
  }
  
  /// 重置为初始状态
  void reset() {
    _logger.info('[Initialization] 🔄 重置初始化状态');
    state = const InitializationState();
  }
}

/// XBoard 统一初始化 Provider
final initializationProvider = 
    StateNotifierProvider<XBoardInitializationNotifier, InitializationState>(
  (ref) => XBoardInitializationNotifier(ref),
);

/// 便捷 Provider: 是否已初始化
final isInitializedProvider = Provider<bool>((ref) {
  return ref.watch(initializationProvider).isReady;
});

/// 便捷 Provider: 是否正在初始化
final isInitializingProvider = Provider<bool>((ref) {
  return ref.watch(initializationProvider).isInitializing;
});

/// 便捷 Provider: 初始化进度百分比
final initializationProgressProvider = Provider<int>((ref) {
  return ref.watch(initializationProvider).progressPercentage;
});
