import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/core/core.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_subscription_provider.dart');

class XBoardSubscriptionNotifier extends Notifier<List<Plan>> {
  @override
  List<Plan> build() {
    ref.listen(xboardUserAuthProvider, (previous, next) {
      if (next.isAuthenticated) {
        if (previous?.isAuthenticated != true) {
          loadPlans();
        }
      } else if (!next.isAuthenticated) {
        _clearPlans();
      }
    });
    return const <Plan>[];  // 明确指定类型
  }
  Future<void> loadPlans() async {
    final userAuthState = ref.read(xboardUserAuthProvider);
    if (!userAuthState.isAuthenticated) {
      state = <Plan>[];
      ref.read(userUIStateProvider.notifier).state = const UIState(
        errorMessage: '请先登录',
      );
      return;
    }
    ref.read(userUIStateProvider.notifier).state = const UIState(isLoading: true);
    try {
      _logger.info('开始加载套餐列表...');
      final plans = await XBoardSDK.getPlans();
      final visiblePlans = plans.where((plan) => plan.isVisible).toList();
      // 按 sort 字段排序（升序），null 值排在最后
      visiblePlans.sort((a, b) {
        if (a.sort == null && b.sort == null) return 0;
        if (a.sort == null) return 1;
        if (b.sort == null) return -1;
        return a.sort!.compareTo(b.sort!);
      });
      state = visiblePlans;
      ref.read(userUIStateProvider.notifier).state = UIState(
        isLoading: false,
        lastUpdated: DateTime.now(),
      );
      _logger.info('套餐列表加载成功，共 ${visiblePlans.length} 个可见套餐');
    } catch (e) {
      _logger.info('加载套餐列表失败: $e');
      ref.read(userUIStateProvider.notifier).state = UIState(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }
  Future<void> refreshPlans() async {
    _logger.info('刷新套餐列表...');
    await loadPlans();
  }
  Plan? getPlanById(int planId) {
    try {
      return state.firstWhere((plan) => plan.id == planId);
    } catch (e) {
      return null;
    }
  }
  List<Plan> get plansWithPrice {
    return state.where((plan) => plan.hasPrice).toList();
  }
  List<Plan> get recommendedPlans {
    return state.where((plan) => plan.isVisible && plan.hasPrice).take(3).toList();
  }
  void _clearPlans() {
    _logger.info('清空套餐列表');
    state = <Plan>[];
    ref.read(userUIStateProvider.notifier).state = const UIState();
  }
  void clearError() {
    final uiState = ref.read(userUIStateProvider);
    if (uiState.errorMessage != null) {
      ref.read(userUIStateProvider.notifier).state = uiState.clearError();
    }
  }
  bool get needsRefresh {
    final uiState = ref.read(userUIStateProvider);
    if (uiState.lastUpdated == null) return true;
    final now = DateTime.now();
    final diff = now.difference(uiState.lastUpdated!);
    return diff.inMinutes > 10; // 10分钟后需要刷新
  }
  Future<void> autoRefreshIfNeeded() async {
    final uiState = ref.read(userUIStateProvider);
    if (needsRefresh && !uiState.isLoading) {
      await refreshPlans();
    }
  }
}
final xboardSubscriptionProvider = NotifierProvider<XBoardSubscriptionNotifier, List<Plan>>(
  XBoardSubscriptionNotifier.new,
);
final xboardPlanProvider = Provider.family<Plan?, int>((ref, planId) {
  final plans = ref.watch(xboardSubscriptionProvider);
  try {
    return plans.firstWhere((plan) => plan.id == planId);
  } catch (e) {
    return null;
  }
});
final xboardPlansWithPriceProvider = Provider<List<Plan>>((ref) {
  final plans = ref.watch(xboardSubscriptionProvider);
  return plans.where((plan) => plan.hasPrice).toList();
});
final xboardRecommendedPlansProvider = Provider<List<Plan>>((ref) {
  final plans = ref.watch(xboardSubscriptionProvider);
  return plans.where((plan) => plan.isVisible && plan.hasPrice).take(3).toList();
}); 