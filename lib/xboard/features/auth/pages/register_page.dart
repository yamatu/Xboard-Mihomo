import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:go_router/go_router.dart';
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}
class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _emailCodeController = TextEditingController();
  bool _isRegistering = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSendingEmailCode = false;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    _emailCodeController.dispose();
    super.dispose();
  }
  Future<void> _register() async {
    // 获取配置
    final configAsync = ref.read(configProvider);
    final config = configAsync.value;
    final isInviteForce = config?.isInviteForce ?? false;
    final isEmailVerify = config?.isEmailVerify ?? false;
    
    // 检查邀请码是否必填
    if (isInviteForce && _inviteCodeController.text.trim().isEmpty) {
      _showInviteCodeDialog();
      return;
    }
    
    // 检查邮箱验证码是否必填
    if (isEmailVerify && _emailCodeController.text.trim().isEmpty) {
      XBoardNotification.showError('请输入邮箱验证码');
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isRegistering = true;
      });
      try {
        await XBoardSDK.register(
          email: _emailController.text,
          password: _passwordController.text,
          inviteCode: _inviteCodeController.text.trim().isNotEmpty 
              ? _inviteCodeController.text 
              : null,
          emailCode: isEmailVerify && _emailCodeController.text.trim().isNotEmpty
              ? _emailCodeController.text
              : null,
        );
        
        // 注册成功
        if (mounted) {
          final storageService = ref.read(storageServiceProvider);
          await storageService.saveCredentials(
            _emailController.text,
            _passwordController.text,
            true, // 启用记住密码
          );
          if (mounted) {
            XBoardNotification.showSuccess(appLocalizations.xboardRegisterSuccess);
          }
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              context.pop();
            }
          });
        }
      } catch (e) {
        if (mounted) {
          // 提取详细的错误信息
          String errorMessage = '注册失败';
          
          final errorStr = e.toString();
          print('[RegisterPage] Caught error: $errorStr');
          
          // 尝试提取具体的错误信息
          if (errorStr.contains('XBoardException')) {
            // 格式1: XBoardException(400): 具体错误信息
            if (errorStr.contains('): ')) {
              final parts = errorStr.split('): ');
              if (parts.length > 1) {
                errorMessage = parts.sublist(1).join('): ').trim();
              }
            } 
            // 格式2: XBoardException: 具体错误信息
            else if (errorStr.contains('XBoardException: ')) {
              errorMessage = errorStr.split('XBoardException: ').last.trim();
            }
          } else {
            // 其他类型的错误，直接使用错误文本
            errorMessage = errorStr;
          }
          
          // 移除可能的 "Error: " 前缀
          if (errorMessage.startsWith('Error: ')) {
            errorMessage = errorMessage.substring(7);
          }
          
          print('[RegisterPage] Display error message: $errorMessage');
          
          XBoardNotification.showError(errorMessage);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isRegistering = false;
          });
        }
      }
    }
  }

  Future<void> _sendEmailCode() async {
    if (_emailController.text.isEmpty) {
      XBoardNotification.showError(appLocalizations.pleaseEnterEmailAddress);
      return;
    }

    if (!_emailController.text.contains('@')) {
      XBoardNotification.showError(appLocalizations.pleaseEnterValidEmailAddress);
      return;
    }

    setState(() {
      _isSendingEmailCode = true;
    });

    try {
      await XBoardSDK.sendVerificationCode(_emailController.text);

      if (mounted) {
        XBoardNotification.showSuccess(appLocalizations.verificationCodeSentCheckEmail);
      }
    } catch (e) {
      if (mounted) {
        XBoardNotification.showError(appLocalizations.sendVerificationCodeFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingEmailCode = false;
        });
      }
    }
  }

  void _showInviteCodeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(appLocalizations.inviteCodeRequired),
          content: Text(appLocalizations.inviteCodeRequiredMessage),
          actions: [
            TextButton(
              onPressed: () {
                context.pop();
              },
              child: Text(appLocalizations.iUnderstand),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final configAsync = ref.watch(configProvider);
    
    // 处理异步加载状态
    return configAsync.when(
      loading: () => Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildPage(context, colorScheme, null),
      data: (config) => _buildPage(context, colorScheme, config),
    );
  }
  
  Widget _buildPage(BuildContext context, ColorScheme colorScheme, ConfigData? config) {
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: XBContainer(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerLow,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    appLocalizations.createAccount,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          appLocalizations.fillInfoToRegister,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        XBInputField(
                          controller: _emailController,
                          labelText: appLocalizations.emailAddress,
                          hintText: appLocalizations.pleaseEnterYourEmailAddress,
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return appLocalizations.pleaseEnterEmailAddress;
                            }
                            if (!value.contains('@')) {
                              return appLocalizations.pleaseEnterValidEmailAddress;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        XBInputField(
                          controller: _passwordController,
                          labelText: appLocalizations.password,
                          hintText: appLocalizations.pleaseEnterAtLeast8CharsPassword,
                          prefixIcon: Icons.lock_outlined,
                          obscureText: !_isPasswordVisible,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return appLocalizations.pleaseEnterPassword;
                            }
                            if (value.length < 8) {
                              return appLocalizations.passwordMin8Chars;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        XBInputField(
                          controller: _confirmPasswordController,
                          labelText: appLocalizations.confirmNewPassword,
                          hintText: appLocalizations.pleaseReEnterPassword,
                          prefixIcon: Icons.lock_outlined,
                          obscureText: !_isConfirmPasswordVisible,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isConfirmPasswordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return appLocalizations.pleaseConfirmPassword;
                            }
                            if (value != _passwordController.text) {
                              return appLocalizations.passwordsDoNotMatch;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        // 根据配置决定是否显示邮箱验证码字段
                        if (config?.isEmailVerify == true)
                          Column(
                            children: [
                                  XBInputField(
                                    controller: _emailCodeController,
                                    labelText: appLocalizations.emailVerificationCode,
                                    hintText: appLocalizations.pleaseEnterEmailVerificationCode,
                                    prefixIcon: Icons.verified_user_outlined,
                                    keyboardType: TextInputType.number,
                                    suffixIcon: _isSendingEmailCode
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : TextButton(
                                            onPressed: _sendEmailCode,
                                            child: Text(appLocalizations.sendVerificationCode),
                                          ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return appLocalizations.pleaseEnterEmailVerificationCode;
                                      }
                                      if (value.length != 6) {
                                        return appLocalizations.verificationCode6Digits;
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                            ],
                          ),
                        // 根据配置决定邀请码字段的显示和必填状态
                        XBInputField(
                          controller: _inviteCodeController,
                          labelText: (config?.isInviteForce ?? false)
                              ? '${appLocalizations.xboardInviteCode} *' 
                              : appLocalizations.inviteCodeOptional,
                          hintText: appLocalizations.pleaseEnterInviteCode,
                          prefixIcon: Icons.card_giftcard_outlined,
                          enabled: true,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: _isRegistering
                              ? ElevatedButton(
                                  onPressed: null,
                                  child: const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _register,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    appLocalizations.registerAccount,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              appLocalizations.alreadyHaveAccount,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.pop(),
                              child: Text(
                                appLocalizations.loginNow,
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 