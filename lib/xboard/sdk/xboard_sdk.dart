/// XBoard SDK Wrapper - SDK 封装层
///
/// 本模块封装 flutter_xboard_sdk，提供统一的访问入口和便捷方法
///
/// 核心职责：
/// 1. SDK 初始化和配置管理
/// 2. 多域名切换和竞速选择
/// 3. 统一的 API 访问接口
/// 4. 便捷方法封装（减少重复代码）
///
/// 使用示例：
/// ```dart
/// import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
///
/// // 1. 初始化（通过配置提供者）
/// await XBoardSDK.initialize(configProvider: XBoardConfig);
///
/// // 2. 使用 API
/// final userInfo = await XBoardSDK.getUserInfo();
/// final plans = await XBoardSDK.getPlans();
/// await XBoardSDK.login(email: email, password: password);
/// ```
library;

import 'src/xboard_client.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart' as sdk;
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/config/interface/config_provider_interface.dart';



// ========== 核心客户端 ==========
export 'src/xboard_client.dart';

// ========== 直接导出 SDK 模型和 API ==========
// 不再维护自定义模型，直接使用 SDK 的 Freezed 模型
// 注意：重导出时要避免名称冲突
export 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart' 
  hide XBoardException;  // 使用我们自己的XBoardException

// ========== 工具类 ==========
export 'src/utils/subscription_url_transformer.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_sdk.dart');
// ========== 为了向后兼容，提供类型别名 ==========
typedef UserInfoData = sdk.UserInfo;
typedef SubscriptionData = sdk.SubscriptionInfo;
typedef Plan = sdk.Plan;
typedef OrderData = sdk.Order;
typedef PaymentMethodData = sdk.PaymentMethodInfo;
typedef PaymentMethod = sdk.PaymentMethodInfo;  // 主要别名
typedef PaymentMethodInfoData = sdk.PaymentMethodInfo;
typedef InviteData = sdk.InviteInfo;
typedef InviteCodeData = sdk.InviteCode;
typedef CommissionDetailData = sdk.CommissionDetail;
typedef CommissionHistoryItem = sdk.CommissionDetail;  // SDK中没有单独的HistoryItem
typedef CommissionHistoryItemData = sdk.CommissionDetail;
typedef WithdrawResultData = sdk.WithdrawResult;
typedef TransferResultData = sdk.TransferResult;
typedef VerificationCodeResponseData = sdk.ApiResponse<dynamic>;
typedef NoticeData = sdk.Notice;
typedef TicketData = sdk.Ticket;
typedef Ticket = sdk.TicketDetail;  // TicketDetail是Ticket的扩展版

/// XBoard SDK - SDK 封装类
///
/// 这是应用中访问 XBoard 功能的 **统一入口**。
///
/// ## 核心职责
/// - SDK 初始化和生命周期管理
/// - 多域名竞速选择和自动切换
/// - 统一的 API 访问接口
///
/// ## 使用规范（必读！）
///
/// ### ✅ 正确用法：通过 XBoardSDK 调用
/// ```dart
/// // 1. 初始化（应用启动时）
/// await XBoardSDK.initialize(configProvider: XBoardConfig);
///
/// // 2. 使用 API
/// final userInfo = await XBoardSDK.getUserInfo();
/// final plans = await XBoardSDK.getPlans();
/// await XBoardSDK.login(email: email, password: password);
/// ```
///
/// ### ❌ 错误用法：不要直接访问底层 SDK
/// ```dart
/// // ❌ 禁止！不要这样做
/// final sdk = XBoardClient.instance.sdk;
/// ```
///
/// ## 设计原则
/// - **单一入口**：所有 XBoard 功能只通过 XBoardSDK 访问
/// - **依赖接口**：依赖 ConfigProviderInterface 而非具体实现
/// - **统一规范**：强制使用标准 API，避免混乱
/// - **易于维护**：集中管理，方便未来修改
class XBoardSDK {
  // 私有构造函数 - 禁止实例化
  XBoardSDK._();

  // 内部获取 SDK Client
  static XBoardClient get _client => XBoardClient.instance;
  static sdk.XBoardSDK get _sdk => _client.sdk;

  // ========== 生命周期管理 ==========

  /// 初始化 SDK
  ///
  /// **必须**在应用启动时调用一次
  ///
  /// [configProvider] 配置提供者（必需）
  /// [baseUrl] 可选的基础URL，如果不为null则直接使用，不从配置读取
  static Future<void> initialize({
    required ConfigProviderInterface configProvider,
    String? baseUrl,
  }) async {
    return _client.initialize(
      configProvider: configProvider,
      baseUrl: baseUrl,
    );
  }

  /// 释放资源
  static void dispose() {
    _client.dispose();
  }

  /// 获取当前域名
  static Future<String?> getCurrentDomain() {
    return _client.getCurrentDomain();
  }

  /// 切换到最快的域名
  static Future<void> switchToFastestDomain() {
    return _client.switchToFastestDomain();
  }

  /// 检查是否已初始化
  static bool get isInitialized => _client.isInitialized;

  // ========== 认证相关 ==========

  /// 登录
  static Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      // 使用 loginWithCredentials 方法，它会自动保存 auth_data token
      final success = await _sdk.loginWithCredentials(email, password);
      if (success) {
        _logger.info('[SDK] 登录成功，authData token已保存');
        return true;
      }
      return false;
    } catch (e) {
      _logger.error('[SDK] 登录失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  /// 注册
  /// [email] 邮箱
  /// [password] 密码
  /// [inviteCode] 邀请码（可选）
  /// [emailCode] 邮箱验证码（可选，根据 config.isEmailVerify 决定是否需要）
  static Future<sdk.UserInfo?> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    try {
      await _sdk.register.register(
        email,
        password,
        inviteCode,  // 可以传 null，API 内部会判断
        emailCode,   // 可以传 null，API 内部会判断
      );
      // 注册成功后返回null，因为API返回的是generic data
      return null;
    } catch (e) {
      _logger.error('[SDK] 注册失败', e);
      rethrow; // 重新抛出异常以便上层获取详细错误信息
    }
  }

  /// 登出
  static Future<bool> logout() async {
    try {
      await _sdk.clearToken();
      return true;
    } catch (e) {
      _logger.error('[SDK] 登出失败', e);
      return false;
    }
  }

  /// 重置密码
  static Future<bool> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    try {
      final result = await _sdk.resetPassword.resetPassword(
        email: email,
        password: password,
        emailCode: emailCode,
      );
      return result.data ?? false;
    } catch (e) {
      _logger.error('[SDK] 重置密码失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  /// 发送验证码
  static Future<bool> sendVerificationCode(String email) async {
    try {
      final result = await _sdk.sendEmailCode.sendEmailCode(email);
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 发送验证码失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  /// 检查是否已登录
  static Future<bool> isLoggedIn() async {
    try {
      return _sdk.isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  /// 获取认证Token
  static Future<String?> getAuthToken() async {
    try {
      return await _sdk.getToken();
    } catch (e) {
      _logger.error('[SDK] 获取认证Token失败', e);
      return null;
    }
  }

  // ========== 用户相关 ==========

  /// 获取用户信息
  static Future<sdk.UserInfo?> getUserInfo() async {
    try {
      final result = await _sdk.userInfo.getUserInfo();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取用户信息失败', e);
      return null;
    }
  }

  // ========== 套餐相关 ==========

  /// 获取套餐列表
  static Future<List<sdk.Plan>> getPlans() async {
    try {
      final result = await _sdk.plan.fetchPlans();
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取套餐列表失败', e);
      return [];
    }
  }

  // ========== 订阅相关 ==========

  /// 获取订阅信息
  static Future<sdk.SubscriptionInfo?> getSubscription() async {
    try {
      final result = await _sdk.subscription.getSubscriptionInfo();
      return result;
    } catch (e) {
      _logger.error('[SDK] 获取订阅信息失败', e);
      return null;
    }
  }

  // ========== 订单相关 ==========

  /// 创建订单
  static Future<String?> createOrder({
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    try {
      final result = await _sdk.order.createOrder(
        planId: planId,
        period: period,
        couponCode: couponCode,
      );
      // createOrder返回ApiResponse<String>
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 创建订单失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  /// 获取订单列表
  static Future<List<sdk.Order>> getOrders() async {
    try {
      final result = await _sdk.order.fetchUserOrders();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取订单列表失败', e);
      return [];
    }
  }

  /// 根据订单号获取订单详情
  static Future<sdk.Order?> getOrderByTradeNo(String tradeNo) async {
    try {
      final result = await _sdk.order.getOrderDetails(tradeNo);
      return result;
    } catch (e) {
      _logger.error('[SDK] 获取订单详情失败', e);
      return null;
    }
  }

  /// 取消订单
  static Future<bool> cancelOrder(String tradeNo) async {
    try {
      final result = await _sdk.order.cancelOrder(tradeNo);
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 取消订单失败', e);
      return false;
    }
  }

  // ========== 支付相关 ==========

  /// 获取支付方式列表
  static Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      final result = await _sdk.payment.getPaymentMethods();
      // API返回PaymentMethodInfo列表，PaymentMethod是其别名
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取支付方式失败', e);
      return [];
    }
  }

  /// 提交支付
  /// 返回 Map 包含 type 和 data
  /// type: -1 表示免费订单, 0 表示二维码支付, 1 表示URL跳转支付
  /// data: 对于免费订单(type=-1)是 bool，对于付费订单是支付URL或二维码内容(String)
  static Future<Map<String, dynamic>?> submitPayment({
    required String tradeNo,
    required int method,
  }) async {
    try {
      final result = await _sdk.order.submitPayment(
        tradeNo: tradeNo,
        method: method.toString(),
      );
      // CheckoutResult 包含 type 和 data
      // 注意：免费订单时 data 是 bool，付费订单时 data 是 String
      return {
        'type': result.type,
        'data': result.data, // 保持原始类型，不强制转换
      };
    } catch (e) {
      _logger.error('[SDK] 提交支付失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  /// 查询支付状态
  static Future<int?> checkPaymentStatus(String tradeNo) async {
    try {
      final result = await _sdk.payment.checkPaymentStatus(tradeNo);
      final paymentResult = result.data;
      if (paymentResult != null) {
        if (paymentResult.isSuccess) return 3;  // 支付成功
        if (paymentResult.isCanceled) return 2; // 已取消
        if (paymentResult.isPending) return 0;  // 等待中
      }
      return null;
    } catch (e) {
      _logger.error('[SDK] 查询支付状态失败', e);
      return null;
    }
  }

  // ========== 邀请佣金相关 ==========

  /// 获取邀请信息
  static Future<sdk.InviteInfo?> getInviteInfo() async {
    try {
      final result = await _sdk.invite.getInviteInfo();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取邀请信息失败', e);
      return null;
    }
  }

  /// 生成邀请码
  static Future<sdk.InviteCode?> generateInviteCode() async {
    try {
      await _sdk.invite.generateInviteCode();
      // API返回void，需要重新获取邀请信息来获取新生成的码
      final info = await getInviteInfo();
      if (info != null && info.codes.isNotEmpty) {
        return info.codes.first;
      }
      return null;
    } catch (e) {
      _logger.error('[SDK] 生成邀请码失败', e);
      return null;
    }
  }

  /// 获取佣金历史
  static Future<List<CommissionHistoryItem>> getCommissionHistory({
    int current = 1,
    int pageSize = 100,
  }) async {
    try {
      // SDK的fetchCommissionDetails需要分页参数
      final result = await _sdk.invite.fetchCommissionDetails(
        current: current,
        pageSize: pageSize,
      );
      // 直接返回CommissionDetail列表，CommissionHistoryItem是其别名
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取佣金历史失败', e);
      return [];
    }
  }

  /// 提现佣金
  /// [withdrawMethod] 提现方式（如：支付宝、微信、银行卡等）
  /// [withdrawAccount] 提现账户（具体账号）
  /// 
  /// 注意：v2board 的提现是通过工单系统实现的
  static Future<WithdrawResultData?> withdrawCommission({
    required String withdrawMethod,
    required String withdrawAccount,
  }) async {
    try {
      _logger.info('[SDK] 申请提现: 方式=$withdrawMethod, 账号=$withdrawAccount');
      
      final result = await _sdk.balance.withdrawFunds(withdrawMethod, withdrawAccount);
      
      return result;  // WithdrawResult 已经是正确的类型
    } catch (e) {
      _logger.error('[SDK] 提现申请失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  /// 划转佣金到余额
  /// [amount] 金额（元），会自动转换为分
  static Future<TransferResultData?> transferCommissionToBalance(
      double amount) async {
    try {
      final amountInCents = (amount * 100).round(); // 转换为分
      _logger.info('[SDK] 划转佣金: ¥$amount (${amountInCents}分)');
      
      final result = await _sdk.balance.transferCommission(amountInCents);
      
      return result;  // TransferResult 已经是正确的类型
    } catch (e) {
      _logger.error('[SDK] 划转佣金失败', e);
      rethrow; // 重新抛出异常，让 UI 层可以获取详细错误信息
    }
  }

  // ========== 优惠券相关 ==========

  /// 验证优惠券
  static Future<sdk.CouponData?> checkCoupon({
    required String code,
    required int planId,
  }) async {
    try {
      final result = await _sdk.coupon.checkCoupon(code, planId);
      // 返回完整的优惠券数据，包含折扣类型和金额
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 验证优惠券失败', e);
      return null;
    }
  }

  // ========== 工单相关 ==========

  /// 获取工单列表
  static Future<List<sdk.Ticket>> getTickets() async {
    try {
      final result = await _sdk.ticket.fetchTickets();
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取工单列表失败', e);
      return [];
    }
  }

  /// 创建工单
  static Future<sdk.Ticket?> createTicket({
    required String subject,
    required String message,
    required int level,
  }) async {
    try {
      final result = await _sdk.ticket.createTicket(
        subject: subject,
        message: message,
        level: level,
      );
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 创建工单失败', e);
      return null;
    }
  }

  /// 获取工单详情
  static Future<Ticket?> getTicketDetail(int id) async {
    try {
      final result = await _sdk.ticket.getTicketDetail(id);
      // TicketDetail就是Ticket的别名
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取工单详情失败', e);
      return null;
    }
  }

  /// 回复工单
  static Future<bool> replyTicket({
    required int id,
    required String message,
  }) async {
    try {
      final result = await _sdk.ticket.replyTicket(
        ticketId: id,
        message: message,
      );
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 回复工单失败', e);
      return false;
    }
  }

  /// 关闭工单
  static Future<bool> closeTicket(int id) async {
    try {
      final result = await _sdk.ticket.closeTicket(id);
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 关闭工单失败', e);
      return false;
    }
  }

  // ========== 公告相关 ==========

  /// 获取公告列表
  static Future<List<sdk.Notice>> getNotices() async {
    try {
      final result = await _sdk.notice.fetchNotices();
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取公告列表失败', e);
      return [];
    }
  }

  // ========== 配置相关 ==========

  /// 获取应用配置
  static Future<dynamic> getConfig() async {
    try {
      final result = await _sdk.config.getConfig();
      return result;  // ConfigData 本身就是数据
    } catch (e) {
      _logger.error('[SDK] 获取配置失败', e);
      return null;
    }
  }

  /// 获取应用信息
  static Future<sdk.AppInfo?> getAppInfo() async {
    try {
      final result = await _sdk.app.fetchDedicatedAppInfo();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取应用信息失败', e);
      return null;
    }
  }
}

