import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/payment/payment.dart';
import 'package:fl_clash/xboard/core/core.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_payment_provider.dart');

final pendingOrdersProvider = StateProvider<List<OrderData>>((ref) => []);
final paymentMethodsProvider = StateProvider<List<PaymentMethodData>>((ref) => []);
final paymentProcessStateProvider = StateProvider<PaymentProcessState>((ref) => const PaymentProcessState());

class XBoardPaymentNotifier extends Notifier<void> {
  @override
  void build() {
    ref.listen(xboardUserAuthProvider, (previous, next) {
      if (next.isAuthenticated) {
        if (previous?.isAuthenticated != true) {
          _loadInitialData();
        }
      } else if (!next.isAuthenticated) {
        _clearPaymentData();
      }
    });
  }
  Future<void> _loadInitialData() async {
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) return;
    try {
      await Future.wait([
        loadPendingOrders(),
        loadPaymentMethods(),
      ]);
    } catch (e) {
      _logger.info('加载支付初始数据失败: $e');
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
      final orders = await XBoardSDK.getOrders();
      // status: 0=待付款, 1=开通中, 2=已取消, 3=已完成, 4=已折抵
      final pendingOrders = orders.where((order) => order.status == 0).toList();
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
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) {
      ref.read(paymentMethodsProvider.notifier).state = [];
      return;
    }
    try {
      _logger.info('加载支付方式...');
      final List<PaymentMethodData> paymentMethods = await XBoardSDK.getPaymentMethods();
      ref.read(paymentMethodsProvider.notifier).state = paymentMethods;
      _logger.info('支付方式加载成功，共 ${paymentMethods.length} 个');
    } catch (e) {
      _logger.info('加载支付方式失败: $e');
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

      // 调用域名服务创建订单
      final tradeNo = await XBoardSDK.createOrder(
        planId: planId,
        period: period,
        couponCode: couponCode,
      );

      if (tradeNo != null) {
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

      // 调用域名服务提交支付，返回支付结果
      final paymentResult = await XBoardSDK.submitPayment(
        tradeNo: tradeNo,
        method: int.tryParse(method) ?? 0,
      );

      ref.read(paymentProcessStateProvider.notifier).state = const PaymentProcessState(
        isProcessingPayment: false,
      );

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
      final orders = await XBoardSDK.getOrders();
      // status: 0=待付款, 1=开通中, 2=已取消, 3=已完成, 4=已折抵
      final pendingOrders = orders.where((order) => order.status == 0).toList();

      int canceledCount = 0;
      for (final order in pendingOrders) {
        if (order.tradeNo != null) {
          try {
            final success = await XBoardSDK.cancelOrder(order.tradeNo!);
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
final xboardAvailablePaymentMethodsProvider = Provider<List<PaymentMethodData>>((ref) {
  final paymentMethods = ref.watch(paymentMethodsProvider);
  // PaymentMethod 没有 isAvailable 字段，返回所有支付方式
  return paymentMethods;
});
final xboardPaymentMethodProvider = Provider.family<PaymentMethodData?, String>((ref, methodId) {
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