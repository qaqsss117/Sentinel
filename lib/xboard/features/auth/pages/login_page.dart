import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/initialization/initialization.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/legal/legal_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../widgets/login_layout.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberPassword = false;
  bool _isPasswordVisible = false;
  late XBoardStorageService _storageService;

  // 从配置文件加载的应用信息
  String _appTitle = 'XBoard';
  String _appWebsite = 'example.com';

  @override
  void initState() {
    super.initState();
    _storageService = ref.read(storageServiceProvider);
    _loadSavedCredentials();
    _loadAppInfo();

    // ✅ 调用统一初始化服务
    _initializeXBoard();
  }

  /// 加载应用信息（标题和网站）
  Future<void> _loadAppInfo() async {
    final title = await ConfigFileLoaderHelper.getAppTitle();
    final website = await ConfigFileLoaderHelper.getAppWebsite();
    if (mounted) {
      setState(() {
        _appTitle = title;
        _appWebsite = website;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 初始化 XBoard（统一入口）
  Future<void> _initializeXBoard() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(initializationProvider.notifier).initialize();
      } catch (e) {
        // 初始化失败，UI 会显示错误状态
      }
    });
  }

  void refreshCredentials() {
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final savedEmail = await _storageService.getSavedEmail();
      final savedPassword = await _storageService.getSavedPassword();
      final rememberPassword = await _storageService.getRememberPassword();
      if (savedEmail != null && savedEmail.isNotEmpty) {
        _emailController.text = savedEmail;
      }
      if (savedPassword != null &&
          savedPassword.isNotEmpty &&
          rememberPassword) {
        _passwordController.text = savedPassword;
      }
      _rememberPassword = rememberPassword;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // 忽略加载凭据失败,继续正常流程
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      final userNotifier = ref.read(xboardUserProvider.notifier);
      final success = await userNotifier.login(
        _emailController.text,
        _passwordController.text,
      );
      if (mounted) {
        if (success) {
          if (_rememberPassword) {
            await _storageService.saveCredentials(
              _emailController.text,
              _passwordController.text,
              true,
            );
          } else {
            await _storageService.saveCredentials(
              _emailController.text,
              '',
              false,
            );
          }
          if (mounted) {
            XBoardNotification.showSuccess(appLocalizations.xboardLoginSuccess);
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                context.go('/');
              }
            });
          }
        } else {
          final userState = ref.read(xboardUserProvider);
          if (userState.errorMessage != null) {
            // 使用哨兵加速器的原生 Toast 通知（自动消失）
            XBoardNotification.showError(userState.errorMessage!);
          }
        }
      }
    }
  }

  void _navigateToRegister() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const RegisterPage()));
    _loadSavedCredentials();
    _initializeXBoard(); // 重新初始化
  }

  void _navigateToForgotPassword() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ForgotPasswordPage()));
    _initializeXBoard(); // 重新初始化
  }

  @override
  Widget build(BuildContext context) {
    final initState = ref.watch(initializationProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          const LanguageSelector(),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildInitializationIndicator(initState),
          ),
        ],
      ),
      body: LoginLayout(
        title: _appTitle,
        website: _appWebsite,
        child: _buildLoginForm(context, initState),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, InitializationState initState) {
    final theme = Theme.of(context);
    final userState = ref.watch(xboardUserProvider);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appLocalizations.xboardLogin,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          XBInputField(
            controller: _emailController,
            labelText: appLocalizations.xboardEmail,
            hintText: appLocalizations.xboardEmail,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty || !value.contains('@')) {
                return appLocalizations.xboardEmail;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          XBInputField(
            controller: _passwordController,
            labelText: appLocalizations.xboardPassword,
            hintText: appLocalizations.xboardPassword,
            prefixIcon: Icons.lock_outlined,
            obscureText: !_isPasswordVisible,
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() => _isPasswordVisible = !_isPasswordVisible);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return appLocalizations.xboardPassword;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberPassword,
                      onChanged: (value) {
                        setState(() => _rememberPassword = value ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _rememberPassword = !_rememberPassword);
                      },
                      child: Text(
                        appLocalizations.xboardRememberPassword,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _navigateToForgotPassword,
                child: Text(appLocalizations.xboardForgotPassword),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: initState.isReady && !userState.isLoading
                  ? _login
                  : null,
              child: userState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(appLocalizations.xboardLogin),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _navigateToRegister,
            child: Text(appLocalizations.xboardRegister),
          ),
          const SizedBox(height: 16),
          Theme(
            data: theme.copyWith(
              textTheme: theme.textTheme.copyWith(
                bodyMedium: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  textStyle: theme.textTheme.bodySmall,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            child: const LegalLinks(
              prefix: '登录即表示您同意 / By signing in, you agree to',
            ),
          ),
        ],
      ),
    );
  }

  /// 构建初始化状态指示器
  Widget _buildInitializationIndicator(InitializationState initState) {
    Color statusColor;
    IconData statusIcon;

    switch (initState.status) {
      case InitializationStatus.checkingDomain:
      case InitializationStatus.initializingSDK:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        break;
      case InitializationStatus.ready:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case InitializationStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case InitializationStatus.idle:
        statusColor = Colors.grey;
        statusIcon = Icons.dns;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        initState.isInitializing
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              )
            : Icon(statusIcon, size: 12, color: statusColor),
      ],
    );
  }
}
