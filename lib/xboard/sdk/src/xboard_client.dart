import 'dart:async';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_client.dart');

/// 简化的 XBoard 客户端
///
/// 这是一个轻量级的 SDK 封装类，负责：
/// 1. SDK 初始化和配置
/// 2. 统一的实例管理
/// 3. 直接暴露 SDK 的所有 API
///
/// 使用示例:
/// ```dart
/// // 初始化（通过依赖注入配置提供者）
/// await XBoardClient.instance.initialize(configProvider: myConfigProvider);
///
/// // 或使用默认配置（需要先初始化XBoardConfig）
/// await XBoardClient.instance.initialize();
///
/// // 使用 SDK API
/// final userInfo = await XBoardClient.instance.sdk.userInfo.getUserInfo();
/// await XBoardClient.instance.sdk.login.login(email, password);
/// final plans = await XBoardClient.instance.sdk.plan.fetchPlans();
/// ```
class XBoardClient {
  static XBoardClient? _instance;
  static XBoardClient get instance => _instance ??= XBoardClient._internal();

  XBoardClient._internal();

  XBoardSDK? _sdk;
  String? _currentPanelUrl;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  ConfigProviderInterface? _configProvider;

  /// 初始化客户端
  ///
  /// [configProvider] 配置提供者（可选，如果不提供则需要确保XBoardConfig已初始化）
  /// [baseUrl] 可选的直接指定基础URL（优先级最高）
  /// [config] 额外配置参数
  Future<void> initialize({
    ConfigProviderInterface? configProvider,
    String? baseUrl,
    Map<String, dynamic>? config,
  }) async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      _logger.info('[SDK] 开始初始化 XBoardClient (使用域名竞速)');

      // 保存配置提供者
      _configProvider = configProvider;

      // 获取面板URL
      String? panelUrl = baseUrl;
      
      // 如果没有直接提供 baseUrl，使用域名竞速选择最快的
      if (panelUrl == null && _configProvider != null) {
        _logger.info('[SDK] 开始域名竞速...');
        panelUrl = await _configProvider!.getFastestPanelUrl();
        
        if (panelUrl == null) {
          throw XBoardConfigException(
            message: '域名竞速失败：所有面板域名都无法连接，请检查网络或配置文件',
            code: 'DOMAIN_RACING_FAILED',
          );
        }
        
        _logger.info('[SDK] 域名竞速完成，使用最快域名: $panelUrl');
      }

      if (panelUrl == null) {
        throw XBoardConfigException(
          message: '无法获取面板地址，请检查配置文件或提供 baseUrl 参数',
          code: 'PANEL_URL_NOT_FOUND',
        );
      }

      // 获取面板类型
      String? panelType;
      if (_configProvider != null) {
        panelType = _configProvider!.getPanelType();
        _logger.info('[SDK] 从配置提供者获取面板类型: $panelType');
      }
      
      if (panelType == null || panelType.isEmpty) {
        throw XBoardConfigException(
          message: '无法获取面板类型，请检查配置文件中的 panel_type 配置',
          code: 'PANEL_TYPE_NOT_FOUND',
        );
      }

      // 从配置文件加载 HTTP 配置
      _logger.info('[SDK] 正在从配置文件加载 HTTP 配置...');
      final httpConfig = await _loadHttpConfigFromFile();
      _logger.info('[SDK] HTTP 配置加载完成: UA=${httpConfig.userAgent != null ? "已设置" : "默认"}, '
          '混淆前缀=${httpConfig.obfuscationPrefix != null ? "已设置" : "未设置"}');

      // 根据竞速结果决定是否使用代理
      String? proxyUrl;
      final racingResult = XBoardConfig.lastRacingResult;
      if (racingResult != null && racingResult.useProxy) {
        proxyUrl = racingResult.proxyUrl;
        _logger.info('[SDK] 竞速结果：使用代理 $proxyUrl');
      } else {
        _logger.info('[SDK] 竞速结果：使用直连');
      }

      // 初始化 SDK
      _sdk = XBoardSDK.instance;
      await _sdk!.initialize(
        panelUrl,
        panelType: panelType,
        proxyUrl: proxyUrl,  // 传递代理配置
        httpConfig: httpConfig,
      );
      _currentPanelUrl = panelUrl;

      _isInitialized = true;
      _initCompleter!.complete();
      _logger.info('[SDK] XBoardClient 初始化完成');
    } catch (e) {
      _logger.error('[SDK] XBoardClient 初始化失败', e);
      _initCompleter!.completeError(e);
      _isInitialized = false;
      rethrow;
    }
  }

  /// 获取 SDK 实例
  ///
  /// 直接暴露 SDK，让上层可以访问所有 API:
  /// - sdk.login.login()
  /// - sdk.register.register()
  /// - sdk.userInfo.getUserInfo()
  /// - sdk.plan.fetchPlans()
  /// - sdk.subscription.getSubscriptionLink()
  /// - sdk.payment.*
  /// - sdk.order.*
  /// - sdk.ticket.*
  /// - sdk.invite.*
  XBoardSDK get sdk {
    if (_sdk == null) {
      throw XBoardConfigException(
        message: 'SDK 未初始化，请先调用 initialize()',
        code: 'SDK_NOT_INITIALIZED',
      );
    }
    return _sdk!;
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  /// 获取当前面板URL
  Future<String?> getCurrentDomain() async {
    return _currentPanelUrl;
  }

  /// 切换到最快的面板URL
  Future<void> switchToFastestDomain() async {
    if (!_isInitialized) {
      throw XBoardConfigException(
        message: 'SDK未初始化，请先调用initialize()',
        code: 'SDK_NOT_INITIALIZED',
      );
    }

    _logger.info('[SDK] 开始切换到最快的面板URL');
    
    final fastestUrl = await _configProvider!.getFastestPanelUrl();
    if (fastestUrl == null) {
      _logger.warning('[SDK] 域名竞速失败：所有域名都无法连接');
      throw XBoardConfigException(
        message: '域名竞速失败：所有域名都无法连接',
        code: 'DOMAIN_RACING_FAILED',
      );
    }

    _logger.info('[SDK] 域名竞速完成，最快URL: $fastestUrl');

    if (fastestUrl == _currentPanelUrl) {
      _logger.info('[SDK] 最快URL与当前URL相同，无需切换');
      return;
    }

    _logger.info('[SDK] 正在切换到新面板URL: $fastestUrl');
    
    // 重新初始化SDK
    _isInitialized = false;
    _initCompleter = null;
    
    await initialize(
      configProvider: _configProvider,
      baseUrl: fastestUrl,
    );
  }

  /// 从配置文件加载 HTTP 配置
  /// 
  /// 从 xboard.config.yaml 读取：
  /// - User-Agent (security.user_agents.api_encrypted)
  /// - 混淆前缀 (security.obfuscation_prefix)
  Future<HttpConfig> _loadHttpConfigFromFile() async {
    try {
      // 从配置文件获取加密 UA（用于 API 请求和 Caddy 认证）
      final userAgent = await UserAgentConfig.get(UserAgentScenario.apiEncrypted);
      
      // 从配置文件获取混淆前缀
      final obfuscationPrefix = await ConfigFileLoaderHelper.getObfuscationPrefix();
      
      // 构建 HttpConfig
      return HttpConfig(
        userAgent: userAgent,
        obfuscationPrefix: obfuscationPrefix,
        enableAutoDeobfuscation: obfuscationPrefix != null,
        enableCertificatePinning: false,
      );
    } catch (e) {
      _logger.error('[SDK] 加载 HTTP 配置失败，使用默认配置', e);
      // 如果加载失败，返回默认配置
      return HttpConfig.defaultConfig();
    }
  }

  /// 释放资源
  void dispose() {
    _logger.info('[SDK] 释放 XBoardClient 资源');
    _sdk = null;
    _currentPanelUrl = null;
    _isInitialized = false;
    _initCompleter = null;
    _configProvider = null;
  }

  /// 重置单例（主要用于测试）
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
