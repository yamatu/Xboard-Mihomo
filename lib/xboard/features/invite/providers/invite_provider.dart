import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/core/core.dart';

// 初始化文件级日志器
final _logger = FileLogger('invite_provider.dart');

class InviteState {
  final InviteData? inviteData;
  final List<CommissionDetailData> commissionHistory;
  final UserInfoData? userInfo;
  final bool isLoading;
  final bool isGenerating;
  final bool isLoadingHistory;
  final String? errorMessage;
  final int currentHistoryPage;
  final bool hasMoreHistory;
  final int historyPageSize;

  const InviteState({
    this.inviteData,
    this.commissionHistory = const [],
    this.userInfo,
    this.isLoading = false,
    this.isGenerating = false,
    this.isLoadingHistory = false,
    this.errorMessage,
    this.currentHistoryPage = 1,
    this.hasMoreHistory = true,
    this.historyPageSize = 10,
  });

  InviteState copyWith({
    InviteData? inviteData,
    List<CommissionDetailData>? commissionHistory,
    UserInfoData? userInfo,
    bool? isLoading,
    bool? isGenerating,
    bool? isLoadingHistory,
    String? errorMessage,
    int? currentHistoryPage,
    bool? hasMoreHistory,
    int? historyPageSize,
  }) {
    return InviteState(
      inviteData: inviteData ?? this.inviteData,
      commissionHistory: commissionHistory ?? this.commissionHistory,
      userInfo: userInfo ?? this.userInfo,
      isLoading: isLoading ?? this.isLoading,
      isGenerating: isGenerating ?? this.isGenerating,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      errorMessage: errorMessage,
      currentHistoryPage: currentHistoryPage ?? this.currentHistoryPage,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      historyPageSize: historyPageSize ?? this.historyPageSize,
    );
  }

  bool get hasInviteData => inviteData != null;
  bool get hasActiveCodes => inviteData?.codes.any((code) => code.isActive) ?? false;
  int get totalInvites => inviteData?.totalInvites ?? 0;
  int get totalCommission => inviteData?.totalCommission ?? 0;
  int get pendingCommission => inviteData?.pendingCommission ?? 0;
  int get commissionRate => inviteData?.commissionRate ?? 0;
  int get availableCommission => inviteData?.availableCommission ?? 0;
  int get walletBalance => (userInfo?.balance ?? 0).toInt();
  String get formattedCommission => _formatCommissionAmount(totalCommission);
  String get formattedPendingCommission => _formatCommissionAmount(pendingCommission);
  String get formattedAvailableCommission => _formatCommissionAmount(availableCommission);
  String get formattedWalletBalance => _formatCommissionAmount(walletBalance);

  String _formatCommissionAmount(int amount) {
    final value = amount / 100.0;
    if (value >= 1000) {
      return '¥${(value / 1000).toStringAsFixed(1)}k';
    } else {
      return '¥${value.toStringAsFixed(2)}';
    }
  }
}

class InviteNotifier extends Notifier<InviteState> {
  @override
  InviteState build() {
    return const InviteState();
  }

  Future<void> loadInviteData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      _logger.info('加载邀请信息...');
      final inviteData = await XBoardSDK.getInviteInfo();

      state = state.copyWith(
        inviteData: inviteData,
        isLoading: false,
      );

      _logger.info('邀请信息加载成功: ${inviteData.toString()}');
    } catch (e) {
      _logger.info('加载邀请信息失败: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> loadCommissionHistory({int page = 1, bool append = false}) async {
    if (state.isLoadingHistory) return;

    state = state.copyWith(isLoadingHistory: true);

    try {
      _logger.info('加载佣金历史... 页码: $page');
      final newHistory = await XBoardSDK.getCommissionHistory(
        current: page,
        pageSize: state.historyPageSize,
      );

      List<CommissionDetailData> updatedHistory;
      if (append && newHistory.isNotEmpty) {
        // 追加到现有列表
        updatedHistory = [...state.commissionHistory, ...newHistory];
      } else {
        // 替换整个列表
        updatedHistory = newHistory;
      }

      state = state.copyWith(
        commissionHistory: updatedHistory,
        currentHistoryPage: page,
        hasMoreHistory: newHistory.length >= state.historyPageSize,
        isLoadingHistory: false,
      );

      _logger.info('佣金历史加载成功: 第$page页，${newHistory.length} 条记录');
    } catch (e) {
      _logger.info('加载佣金历史失败: $e');
      state = state.copyWith(isLoadingHistory: false);
    }
  }
  
  Future<void> loadNextHistoryPage() async {
    if (!state.hasMoreHistory || state.isLoadingHistory) return;
    await loadCommissionHistory(page: state.currentHistoryPage + 1, append: true);
  }
  
  Future<void> refreshCommissionHistory() async {
    await loadCommissionHistory(page: 1, append: false);
  }

  Future<void> loadUserInfo() async {
    try {
      _logger.info('加载用户信息...');
      final userInfo = await XBoardSDK.getUserInfo();

      state = state.copyWith(userInfo: userInfo);
      _logger.info('用户信息加载成功: 钱包余额 ¥${(userInfo?.balance ?? 0) / 100.0}');
    } catch (e) {
      _logger.info('加载用户信息失败: $e');
    }
  }

  Future<InviteCodeData?> generateInviteCode() async {
    if (state.isGenerating) return null;

    state = state.copyWith(isGenerating: true, errorMessage: null);

    try {
      _logger.info('生成邀请码...');
      final newCode = await XBoardSDK.generateInviteCode();

      await loadInviteData();

      state = state.copyWith(isGenerating: false);
      _logger.info('邀请码生成成功: ${newCode?.code}');
      return newCode;
    } catch (e) {
      _logger.info('生成邀请码失败: $e');
      state = state.copyWith(
        isGenerating: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<WithdrawResultData?> withdrawCommission({
    required String withdrawMethod,
    required String withdrawAccount,
  }) async {
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      _logger.info('提现佣金: 方式=$withdrawMethod, 账号=$withdrawAccount');
      final result = await XBoardSDK.withdrawCommission(
        withdrawMethod: withdrawMethod,
        withdrawAccount: withdrawAccount,
      );

      await loadInviteData();
      await refreshCommissionHistory();

      state = state.copyWith(isLoading: false);
      _logger.info('提现申请提交成功');
      return result;
    } catch (e) {
      _logger.info('提现申请失败: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<TransferResultData?> transferCommission(double amount) async {
    if (state.isLoading) return null;
    
    state = state.copyWith(isLoading: true, errorMessage: null);
    
    try {
      _logger.info('划转佣金到钱包: ¥$amount');
      final result = await XBoardSDK.transferCommissionToBalance(amount);
      
      await Future.wait([
        loadInviteData(),
        loadUserInfo(),
      ]);
      
      state = state.copyWith(isLoading: false);
      _logger.info('划转成功');
      return result;
    } catch (e) {
      _logger.info('划转失败: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  Future<void> refresh() async {
    await Future.wait([
      loadInviteData(),
      refreshCommissionHistory(),
      loadUserInfo(),
    ]);
  }
}

final inviteProvider = NotifierProvider<InviteNotifier, InviteState>(
  InviteNotifier.new,
);

extension InviteHelpers on WidgetRef {
  InviteState get inviteState => read(inviteProvider);
  InviteNotifier get inviteNotifier => read(inviteProvider.notifier);
}