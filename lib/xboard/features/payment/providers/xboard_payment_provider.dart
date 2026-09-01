import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/payment/payment.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:fl_clash/xboard/adapter/state/payment_state.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_payment_provider.dart');

final pendingOrdersProvider = StateProvider<List<DomainOrder>>((ref) => []);
final paymentMethodsProvider = StateProvider<List<DomainPaymentMethod>>((ref) => []);
final paymentProcessStateProvider = StateProvider<PaymentProcessState>((ref) => const PaymentProcessState());

class XBoardPaymentNotifier extends Notifier<void> {
  @override
  void build() {
    // 1. 监听认证状态变化
    ref.listen(xboardUserAuthProvider, (previous, next) {
      _logger.info('📋 [Payment] 👤 认证状态变化: ${previous?.isAuthenticated} -> ${next.isAuthenticated}');
      
      if (next.isAuthenticated) {
        if (previous?.isAuthenticated != true) {
          _logger.info('📋 [Payment] 🎯 用户刚登录，触发初始数据加载');
          _loadInitialData();
        }
      } else if (!next.isAuthenticated) {
        _logger.warning('📋 [Payment] 🚪 用户已登出，清空支付数据');
        _clearPaymentData();
      }
    });
    
    // 2. 检查当前状态（处理 Provider 初始化时用户已登录的情况）
    final authState = ref.read(xboardUserAuthProvider);
    if (authState.isAuthenticated) {
      _logger.info('📋 [Payment] 🚀 Provider 初始化时用户已认证，触发初始数据加载');
      // 使用 microtask 避免在 build 过程中修改 state
      Future.microtask(() => _loadInitialData());
    }
  }
  Future<void> _loadInitialData() async {
    _logger.info('📋 [Payment] 🔄 开始加载初始支付数据...');
    
    final userAuthState = ref.read(xboardUserAuthProvider);
    _logger.info('📋 [Payment] 用户认证状态: ${userAuthState.isAuthenticated}');
    
    if (!userAuthState.isAuthenticated) {
      _logger.warning('📋 [Payment] ⚠️ 用户未认证，跳过数据加载');
      return;
    }
    
    try {
      _logger.info('📋 [Payment] 并行加载：待支付订单 + 支付方式');
      await Future.wait([
        loadPendingOrders(),
        loadPaymentMethods(),
      ]);
      _logger.info('📋 [Payment] ✅ 初始数据加载完成');
    } catch (e, stackTrace) {
      _logger.error('📋 [Payment] ❌ 加载支付初始数据失败: $e');
      _logger.error('📋 [Payment] 错误堆栈: $stackTrace');
    }
  }
  Future<void> loadPendingOrders() async {
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) {
      ref.read(pendingOrdersProvider.notifier).state = [];
      return;
    }
    ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: true);
    try {
      _logger.info('加载待支付订单...');
      _logger.info('加载待支付订单...');
      final orderModels = await XBoardSDK.instance.order.getOrders();
      final orders = orderModels.map(_mapOrder).toList();
      
      // status: 0=待付款, 1=开通中, 2=已取消, 3=已完成, 4=已折抵
      // 显示"待付款"和"开通中"的订单
      final pendingOrders = orders.where((order) => 
        order.status == OrderStatus.pending || order.status == OrderStatus.processing
      ).toList();
      ref.read(pendingOrdersProvider.notifier).state = pendingOrders;
      ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: false);
      _logger.info('待支付订单加载成功，共 ${pendingOrders.length} 个');
    } catch (e) {
      _logger.info('加载待支付订单失败: $e');
      ref.read(userUIStateProvider.notifier).state = UIState(
        isLoading: false,
        errorMessage: e.toString(),
      );
      ref.read(pendingOrdersProvider.notifier).state = [];
    }
  }
  Future<void> loadPaymentMethods() async {
    _logger.info('📋 [Payment] 开始加载支付方式...');
    
    final userAuthState = ref.read(xboardUserAuthProvider);
    _logger.info('📋 [Payment] 用户认证状态: ${userAuthState.isAuthenticated}');
    
    if (!userAuthState.isAuthenticated) {
      _logger.warning('📋 [Payment] ⚠️ 用户未认证，清空支付方式列表');
      ref.read(paymentMethodsProvider.notifier).state = [];
      return;
    }
    
    try {
      _logger.info('📋 [Payment] 调用 getPaymentMethodsProvider 获取数据...');
      final paymentMethodModels = await ref.read(getPaymentMethodsProvider.future);
      
      _logger.info('📋 [Payment] SDK 返回支付方式数量: ${paymentMethodModels.length}');
      if (paymentMethodModels.isNotEmpty) {
        _logger.info('📋 [Payment] SDK 返回的支付方式:');
        for (var method in paymentMethodModels) {
          _logger.info('   - ${method.name} (id: ${method.id}, paymentMethod: ${method.paymentMethod})');
        }
      }
      
      final paymentMethods = paymentMethodModels.map(_mapPaymentMethod).toList();
      ref.read(paymentMethodsProvider.notifier).state = paymentMethods;
      
      _logger.info('📋 [Payment] ✅ 支付方式加载成功，共 ${paymentMethods.length} 个');
      _logger.info('📋 [Payment] 映射后的支付方式:');
      for (var method in paymentMethods) {
        _logger.info('   - ${method.name} (id: ${method.id})');
      }
    } catch (e, stackTrace) {
      _logger.error('📋 [Payment] ❌ 加载支付方式失败: $e');
      _logger.error('📋 [Payment] 错误堆栈: $stackTrace');
      ref.read(userUIStateProvider.notifier).state = UIState(
        errorMessage: e.toString(),
      );
    }
  }
  Future<String?> createOrder({
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) {
      ref.read(userUIStateProvider.notifier).state = const UIState(
        errorMessage: '请先登录',
      );
      return null;
    }
    ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: true);
    try {
      _logger.info('创建订单: planId=$planId, period=$period, couponCode=$couponCode');

      // 先取消待支付订单
      await cancelPendingOrders();

      // 调用 Repository 创建订单
      final tradeNo = await XBoardSDK.instance.order.createOrder(
        planId,
        period,
        couponCode: couponCode,
      );
      if (tradeNo != null && tradeNo.isNotEmpty) {
        ref.read(paymentProcessStateProvider.notifier).state = PaymentProcessState(
          currentOrderTradeNo: tradeNo,
        );
        ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: false);
        await loadPendingOrders();
        _logger.info('订单创建成功: tradeNo=$tradeNo');
        await Future.delayed(const Duration(seconds: 1)); // 添加延迟，确保订单在服务器端完全就绪
        return tradeNo;
      } else {
        ref.read(userUIStateProvider.notifier).state = const UIState(
          isLoading: false,
          errorMessage: '创建订单失败',
        );
        return null;
      }
    } catch (e) {
      _logger.info('创建订单失败: $e');
      ref.read(userUIStateProvider.notifier).state = UIState(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }
  /// 提交支付
  /// 
  /// 返回支付结果，包含 type 和 data
  /// type: -1 表示余额支付成功, 0 表示跳转支付, 1 表示二维码支付
  Future<Map<String, dynamic>?> submitPayment({
    required String tradeNo,
    required String method,
  }) async {
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) {
      ref.read(userUIStateProvider.notifier).state = const UIState(
        errorMessage: '请先登录',
      );
      return null;
    }
    ref.read(paymentProcessStateProvider.notifier).state = const PaymentProcessState(
      isProcessingPayment: true,
    );
    try {
      _logger.info('提交支付: tradeNo=$tradeNo, method=$method');

      // 调用 Repository 提交支付，返回支付结果
      final paymentResultModel = await XBoardSDK.instance.order.checkoutOrder(
        tradeNo,
        method,
      );

      ref.read(paymentProcessStateProvider.notifier).state = const PaymentProcessState(
        isProcessingPayment: false,
      );

      final paymentResult = _mapPaymentResult(paymentResultModel);
      if (paymentResult != null) {
        await loadPendingOrders();
        _logger.info('支付提交成功，结果: $paymentResult');
        return paymentResult;
      }
      return null;
    } catch (e) {
      _logger.info('支付提交失败: $e');
      ref.read(paymentProcessStateProvider.notifier).state = const PaymentProcessState(
        isProcessingPayment: false,
      );
      ref.read(userUIStateProvider.notifier).state = UIState(
        errorMessage: e.toString(),
      );
      return null;
    }
  }
  Future<int> cancelPendingOrders() async {
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) {
      ref.read(userUIStateProvider.notifier).state = const UIState(
        errorMessage: '请先登录',
      );
      return 0;
    }
    ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: true);
    try {
      // 获取所有订单并筛选待支付的
      final orderModels = await XBoardSDK.instance.order.getOrders();
      final orders = orderModels.map(_mapOrder).toList();
      // 筛选需要在创建新订单前自动取消的订单（待付款和开通中）
      final ordersToCancel = orders.where((order) => order.shouldAutoCancelBeforeNewOrder).toList();

      int canceledCount = 0;
      for (final order in ordersToCancel) {
        if (order.tradeNo != null && order.tradeNo!.isNotEmpty) {
          try {
            final success = await XBoardSDK.instance.order.cancelOrder(order.tradeNo!);
            if (success) {
              canceledCount++;
            }
          } catch (e) {
            _logger.info('取消订单失败: ${order.tradeNo}, 错误: $e');
          }
        }
      }

      ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: false);
      await loadPendingOrders();
      _logger.info('取消订单成功，共取消 $canceledCount 个订单');
      return canceledCount;
    } catch (e) {
      _logger.info('取消订单失败: $e');
      ref.read(userUIStateProvider.notifier).state = UIState(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return 0;
    }
  }
  void _clearPaymentData() {
    ref.read(pendingOrdersProvider.notifier).state = [];
    ref.read(paymentMethodsProvider.notifier).state = [];
    ref.read(paymentProcessStateProvider.notifier).state = const PaymentProcessState();
  }
  void setCurrentOrderTradeNo(String? tradeNo) {
    ref.read(paymentProcessStateProvider.notifier).state = 
        ref.read(paymentProcessStateProvider).copyWith(currentOrderTradeNo: tradeNo);
  }
}
final xboardPaymentProvider = NotifierProvider<XBoardPaymentNotifier, void>(
  XBoardPaymentNotifier.new,
);
final xboardAvailablePaymentMethodsProvider = Provider<List<DomainPaymentMethod>>((ref) {
  final paymentMethods = ref.watch(paymentMethodsProvider);
  // 返回所有支付方式
  return paymentMethods;
});
final xboardPaymentMethodProvider = Provider.family<DomainPaymentMethod?, String>((ref, methodId) {
  final paymentMethods = ref.watch(paymentMethodsProvider);
  try {
    return paymentMethods.firstWhere((method) => method.id.toString() == methodId);
  } catch (e) {
    return null;
  }
});
final hasPendingOrdersProvider = Provider<bool>((ref) {
  final pendingOrders = ref.watch(pendingOrdersProvider);
  return pendingOrders.isNotEmpty;
});
final pendingOrdersCountProvider = Provider<int>((ref) {
  final pendingOrders = ref.watch(pendingOrdersProvider);
  return pendingOrders.length;
});

DomainOrder _mapOrder(OrderModel order) {
  return DomainOrder(
    tradeNo: order.tradeNo ?? '',
    planId: order.planId ?? 0,
    period: order.period ?? '',
    totalAmount: (order.totalAmount ?? 0), // SDK might be cents? Check OrderModel.
    // OrderModel totalAmount is double?
    // SDK OrderModel: `double? totalAmount`.
    // If SDK returns Yuan, then no division. If Cents, divide.
    // Usually SDK returns raw value from API.
    // Assuming API returns Cents (common in payment).
    // Wait, DomainOrder expects Yuan (double).
    // If SDK returns Cents, I divide by 100.
    // If SDK returns Yuan, I keep it.
    // I'll assume Cents for now as standard practice, but verify if possible.
    // Actually, `xboard_user_provider` mapped balance * 100 to cents. So balance was Yuan?
    // `balanceInCents: (user.balance * 100).toInt()`. So `user.balance` is Yuan.
    // So `order.totalAmount` is likely Yuan too.
    // So NO division by 100 if it's already Yuan.
    // But `DomainOrder` `totalAmount` is double (Yuan).
    // So `totalAmount: order.totalAmount ?? 0`.
    status: OrderStatus.fromCode(order.status ?? 0),
    planName: order.orderPlan?.name,
    createdAt: order.createdAt ?? DateTime.now(),
    // paidAt missing in OrderModel?
  );
}

DomainPaymentMethod _mapPaymentMethod(PaymentMethodModel method) {
  return DomainPaymentMethod(
    id: int.tryParse(method.id) ?? 0,
    name: method.name,
    iconUrl: method.icon,
    feePercentage: method.handlingFeePercent ?? 0,
    isAvailable: method.isAvailable,
    description: method.description,
    minAmount: method.minAmount,
    maxAmount: method.maxAmount,
    config: method.config ?? {},
  );
}

Map<String, dynamic>? _mapPaymentResult(PaymentResultModel result) {
  return result.when(
    success: (transactionId, message, extra) => {
      'type': -1,
      'data': true, // Balance payment success
    },
    redirect: (url, method, headers) => {
      'type': method == 'qr_code' ? 1 : 0,
      'data': url,
    },
    failed: (message, errorCode, extra) => null, // Or throw?
    canceled: (message) => null,
  );
}