import 'package:fl_clash/xboard/features/shared/widgets/notice_banner.dart';
import 'package:fl_clash/xboard/features/payment/widgets/payment_waiting_overlay.dart';
import 'package:fl_clash/xboard/features/payment/models/payment_step.dart';
import 'package:fl_clash/xboard/features/payment/pages/payment_gateway_page.dart';
import 'package:fl_clash/xboard/features/subscription/pages/subscription_page.dart';
import 'package:fl_clash/xboard/features/payment/widgets/payment_method_selector_dialog.dart';
import 'package:fl_clash/xboard/features/invite/dialogs/theme_dialog.dart';
import 'package:fl_clash/xboard/features/update_check/widgets/update_dialog.dart';
import 'package:fl_clash/xboard/features/update_check/models/update_check_state.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:fl_clash/theme/sentinel_assets.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/initialization/initialization.dart';
import 'package:fl_clash/xboard/features/invite/pages/invite_page.dart';
import 'package:fl_clash/xboard/features/invite/providers/invite_provider.dart';
import 'package:fl_clash/xboard/features/latency/services/auto_latency_service.dart';
import 'package:fl_clash/xboard/features/notice/providers/notice_provider.dart';
import 'package:fl_clash/xboard/features/payment/pages/plans.dart';
import 'package:fl_clash/xboard/features/payment/pages/plan_purchase_page.dart';
import 'package:fl_clash/xboard/features/payment/providers/xboard_payment_provider.dart';
import 'package:fl_clash/xboard/features/profile/profile.dart';
import 'package:fl_clash/xboard/features/subscription/pages/xboard_home_page.dart';
import 'package:fl_clash/xboard/features/discovery/discovery_page.dart';
import 'package:fl_clash/xboard/features/subscription/widgets/subscription_usage_card.dart';
import 'package:fl_clash/xboard/features/subscription/widgets/xboard_connect_button.dart';
import 'package:fl_clash/xboard/features/subscription/providers/xboard_subscription_provider.dart';
import 'package:fl_clash/xboard/features/ticket_support/pages/ticket_support_page.dart';
import 'package:fl_clash/xboard/infrastructure/storage/shared_prefs_storage.dart';
import 'package:fl_clash/xboard/router/shell_layout.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
const _plan = DomainPlan(
  id: 1,
  name: '星际畅游',
  groupId: 1,
  transferQuota: 200,
  monthlyPrice: 29,
  quarterlyPrice: 79,
  yearlyPrice: 279,
  speedLimit: 500,
  description: '全球优选线路 · 多设备连接\n高清流媒体与日常工作',
);
const _subscription = DomainSubscription(
  subscribeUrl: 'https://example.invalid/sub',
  email: 'preview@example.invalid',
  uuid: 'preview',
  planId: 1,
  transferLimit: 214748364800,
  uploadedBytes: 1073741824,
  downloadedBytes: 12884901888,
);
const _profile = Profile(
  id: 'preview',
  autoUpdateDuration: Duration(days: 1),
  subscriptionInfo: SubscriptionInfo(
    total: 214748364800,
    upload: 1073741824,
    download: 12884901888,
    expire: 1893456000,
  ),
);

class _ThemeSettings extends ThemeSetting {
  @override
  ThemeProps build() => defaultThemeProps;
}

class _AppSettings extends AppSetting {
  @override
  AppSettingProps build() => const AppSettingProps(locale: 'zh_CN');
}

class _Patch extends PatchClashConfig {
  @override
  ClashConfig build() => const ClashConfig();
}

class _Auth extends XBoardUserAuthNotifier {
  @override
  UserAuthState build() => const UserAuthState(isInitialized: true);
}

class _Plans extends XBoardSubscriptionNotifier {
  _Plans({this.empty = false});
  final bool empty;
  @override
  List<DomainPlan> build() => empty
      ? []
      : [
          _plan,
          _plan.copyWith(
            id: 2,
            name: '寰宇探索',
            monthlyPrice: 49,
            transferQuota: 500,
          ),
        ];
  @override
  Future<void> autoRefreshIfNeeded() async {}
  @override
  Future<void> refreshPlans() async {}
}

class _Payment extends XBoardPaymentNotifier {
  @override
  void build() {}
}

class _Invite extends InviteNotifier {
  _Invite({this.fail = false});
  final bool fail;
  @override
  InviteState build() => fail
      ? const InviteState(errorMessage: 'Connection unavailable')
      : const InviteState(
          inviteData: DomainInvite(
            codes: [DomainInviteCode(code: 'SENTINEL')],
            stats: InviteStats(
              invitedCount: 12,
              commissionRate: 20,
              totalCommission: 128,
              availableCommission: 96,
              pendingCommission: 32,
            ),
          ),
        );
  @override
  Future<void> refresh() async {}
  @override
  Future<DomainInviteCode?> generateInviteCode() async => null;
}

class _Notice extends NoticeNotifier {
  _Notice(super.ref) {
    state = NoticeState(
      notices: [
        DomainNotice(
          id: 1,
          title: '欢迎使用哨兵，随时随地畅享连接',
          content: '此页面使用固定模拟数据进行 UI 验证。',
          createdAt: DateTime(2026, 9, 21),
        ),
      ],
    );
  }
  @override
  Future<void> fetchNotices() async {}
}

class _Import extends ProfileImportNotifier {
  _Import(super.ref) {
    state = const ImportState();
  }
}

class _Initialization extends XBoardInitializationNotifier {
  _Initialization(super.ref) {
    state = const InitializationState(status: InitializationStatus.ready);
  }
  @override
  Future<void> initialize() async {}
}

class _Tickets extends Fake implements TicketApi {
  _Tickets({this.fail = false, this.empty = false});
  final bool empty;
  final bool fail;
  final date = DateTime(2026, 9, 21, 10, 30);
  @override
  Future<List<TicketModel>> getTickets({
    int page = 1,
    int pageSize = 10,
  }) async {
    if (fail) throw StateError('Connection unavailable');
    if (empty) return [];
    return [
      TicketModel(
        id: 1,
        level: 1,
        replyStatus: 1,
        status: 0,
        subject: '连接使用帮助',
        createdAt: date,
        updatedAt: date,
        userId: 1,
      ),
    ];
  }

  @override
  Future<TicketDetailModel> getTicket(int id) async => TicketDetailModel(
    id: 1,
    level: 1,
    replyStatus: 1,
    status: 0,
    subject: '连接使用帮助',
    createdAt: date,
    updatedAt: date,
    userId: 1,
    messages: [
      TicketMessageModel(
        id: 1,
        ticketId: 1,
        isMe: true,
        message: '你好，请问如何切换连接线路？',
        createdAt: date,
        updatedAt: date,
      ),
      TicketMessageModel(
        id: 2,
        ticketId: 1,
        isMe: false,
        message: '您好，在首页点击当前节点，即可选择线路并查看延迟。我们随时为您提供帮助。',
        createdAt: date,
        updatedAt: date,
      ),
    ],
  );
}

class _Orders extends Fake implements OrderApi {
  _Orders(this.status);
  final int status;
  @override
  Future<List<OrderModel>> getOrders({int page = 1, int pageSize = 10}) async =>
      [OrderModel(tradeNo: 'SENTINEL-20260921-001', status: status)];
}

Future<void> _pumpScreen(
  WidgetTester tester,
  String route,
  Size size,
  Brightness brightness, {
  double textScale = 1,
  String language = 'zh',
  bool error = false,
  bool empty = false,
  int paymentStatus = 0,
  int? runTime,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  SharedPreferences.setMockInitialValues({});
  final storage = await SharedPrefsStorage.create();
  final router = GoRouter(
    initialLocation: route,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AdaptiveShellLayout(child: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const XBoardHomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/plans', builder: (_, _) => const PlansView()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (_, _) => const DiscoveryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/invite', builder: (_, _) => const InvitePage()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/support',
        builder: (_, _) => TicketSupportPage(
          ticketApi: _Tickets(fail: error, empty: empty),
        ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/reset', builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(
        path: '/gateway',
        builder: (_, _) => PaymentGatewayPage(
          paymentUrl: 'https://example.invalid/pay/preview',
          tradeNo: 'SENTINEL-20260921-001',
          orderApi: _Orders(paymentStatus),
          launchPayment: (_) async => !error,
        ),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, _) => const SubscriptionPage(),
      ),
      GoRoute(
        path: '/theme',
        builder: (_, _) => const Scaffold(body: ThemeDialog()),
      ),
      GoRoute(
        path: '/update',
        builder: (_, _) => const Scaffold(
          body: UpdateDialog(
            state: UpdateCheckState(
              hasUpdate: true,
              currentVersion: '1.0.0',
              latestVersion: '1.1.0',
              releaseNotes: '优化连接体验与页面布局。',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/methods',
        builder: (_, _) => const Scaffold(
          body: PaymentMethodSelectorDialog(
            paymentMethods: [
              DomainPaymentMethod(id: 1, name: '支付宝'),
              DomainPaymentMethod(id: 2, name: '微信支付', feePercentage: 1.5),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/purchase',
        builder: (_, _) => const PlanPurchasePage(plan: _plan),
      ),
      GoRoute(
        path: '/plans/purchase',
        builder: (_, state) =>
            PlanPurchasePage(plan: state.extra! as DomainPlan),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(XBoardStorageService(storage)),
        initializationProvider.overrideWith(_Initialization.new),
        appSettingProvider.overrideWith(_AppSettings.new),
        themeSettingProvider.overrideWith(_ThemeSettings.new),
        patchClashConfigProvider.overrideWith(_Patch.new),
        xboardUserAuthProvider.overrideWith(_Auth.new),
        xboardSubscriptionProvider.overrideWith(() => _Plans(empty: empty)),
        xboardPaymentProvider.overrideWith(_Payment.new),
        inviteProvider.overrideWith(() => _Invite(fail: error)),
        configProvider.overrideWith(
          (ref) async => const ConfigModel(appUrl: 'https://example.invalid'),
        ),
        noticeProvider.overrideWith((ref) => _Notice(ref)),
        userUIStateProvider.overrideWith(
          (ref) => error
              ? const UIState(errorMessage: 'Connection unavailable')
              : const UIState(),
        ),
        subscriptionInfoProvider.overrideWith(
          (ref) => empty ? null : _subscription,
        ),
        currentProfileProvider.overrideWithValue(_profile),
        startButtonSelectorStateProvider.overrideWithValue(
          const StartButtonSelectorState(isInit: true, hasProfile: true),
        ),
        runTimeProvider.overrideWithValue(runTime),
        groupsProvider.overrideWithValue(const [
          Group(
            type: GroupType.Selector,
            name: '节点选择',
            all: [Proxy(name: '香港 · HK 01', type: 'Shadowsocks')],
          ),
        ]),
        getDelayProvider(
          proxyName: '香港 · HK 01',
          testUrl: const AppSettingProps().testUrl,
        ).overrideWithValue(42),
        selectedMapProvider.overrideWithValue(const {}),
        profileImportProvider.overrideWith((ref) => _Import(ref)),
      ],
      child: RepaintBoundary(
        key: const ValueKey('screen'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme:
              SentinelTheme.build(
                brightness: brightness,
                fontFamily: _capture ? 'UiTestFont' : null,
              ).copyWith(
                platform: size.width < 600
                    ? TargetPlatform.android
                    : TargetPlatform.windows,
                textTheme: SentinelTheme.build(
                  brightness: brightness,
                  fontFamily: _capture ? 'UiTestFont' : null,
                ).textTheme.apply(fontFamily: _capture ? 'UiTestFont' : null),
              ),
          locale: language == 'zh'
              ? const Locale('zh', 'CN')
              : const Locale('en'),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: SentinelBackground(decorated: true, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (_capture) {
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold).first);
      await Future.wait([
        for (final asset in [
          SentinelAssets.logo,
          SentinelAssets.planet,
          SentinelAssets.globe,
        ])
          precacheImage(AssetImage(asset), context),
      ]);
    });
    await tester.pump();
  }
}

Future<void> _captureScreen(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screen')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/layout-previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  autoLatencyService.dispose();
  await tester.pump(const Duration(seconds: 7));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(() async {
    if (_capture) {
      await ConfigFileLoaderHelper.getAppTitle();
      await ConfigFileLoaderHelper.getAppWebsite();
      final file = File('C:/Windows/Fonts/msyh.ttc');
      if (file.existsSync()) {
        final loader = FontLoader('UiTestFont')
          ..addFont(file.readAsBytes().then(ByteData.sublistView));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      }
    }
  });
  for (final brightness in Brightness.values) {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      for (final route in [
        '/',
        '/login',
        '/register',
        '/reset',
        '/plans',
        '/purchase',
        '/invite',
        '/support',
        '/gateway',
        '/subscription',
        '/theme',
        '/update',
        '/methods',
      ]) {
        final name =
            '${route == '/' ? 'home' : route.substring(1)}-${brightness.name}-${size.width.toInt()}';
        testWidgets(name, (tester) async {
          await _pumpScreen(tester, route, size, brightness);
          expect(tester.takeException(), isNull);
          if (route == '/') {
            expect(
              tester.getTopLeft(find.byType(SubscriptionUsageCard)).dy,
              lessThan(tester.getTopLeft(find.byType(XBoardConnectButton)).dy),
            );
            expect(find.byIcon(Icons.support_agent_outlined), findsOneWidget);
          }
          await _captureScreen(tester, name);
          await _disposeScreen(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final route in [
    '/',
    '/register',
    '/reset',
    '/plans',
    '/purchase',
    '/invite',
    '/support',
    '/gateway',
    '/subscription',
    '/theme',
    '/update',
    '/methods',
  ]) {
    testWidgets('large English text on small viewport: $route', (tester) async {
      await _pumpScreen(
        tester,
        route,
        const Size(360, 640),
        Brightness.dark,
        textScale: 2,
        language: 'en',
      );
      expect(tester.takeException(), isNull);
      await _disposeScreen(tester);
    });
  }
  for (final size in [const Size(360, 800), const Size(850, 600)]) {
    for (final route in [
      '/',
      '/login',
      '/plans',
      '/purchase',
      '/invite',
      '/support',
      '/gateway',
      '/subscription',
      '/theme',
      '/update',
      '/methods',
    ]) {
      testWidgets('additional viewport ${size.width}: $route', (tester) async {
        await _pumpScreen(tester, route, size, Brightness.dark);
        expect(tester.takeException(), isNull);
        await _disposeScreen(tester);
      });
    }
  }
  for (final route in ['/', '/plans', '/support', '/subscription']) {
    testWidgets('empty state: $route', (tester) async {
      await _pumpScreen(
        tester,
        route,
        const Size(390, 844),
        Brightness.dark,
        empty: true,
      );
      expect(tester.takeException(), isNull);
      await _captureScreen(
        tester,
        '${route == '/' ? 'home' : route.substring(1)}-empty',
      );
      await _disposeScreen(tester);
    });
  }
  testWidgets('notice pagination remains reachable at large text', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      '/',
      const Size(360, 640),
      Brightness.dark,
      textScale: 2,
    );
    final context = tester.element(find.byType(Scaffold).first);
    showDialog<void>(
      context: context,
      builder: (_) => NoticeDetailDialog(
        notices: [
          for (var i = 0; i < 10; i++)
            DomainNotice(
              id: i,
              title: '服务公告 ${i + 1}',
              content: '## 欢迎使用哨兵\n请在首页选择节点后开始连接。',
              createdAt: DateTime(2026, 9, 21),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2 / 10'), findsOneWidget);
    await _captureScreen(tester, 'notice-large-text');
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await _disposeScreen(tester);
  });
  for (final step in [PaymentStep.waitingPayment, PaymentStep.paymentSuccess]) {
    testWidgets('payment dialog at large text: ${step.name}', (tester) async {
      await _pumpScreen(
        tester,
        '/purchase',
        const Size(360, 640),
        Brightness.dark,
        textScale: 2,
        language: 'en',
      );
      var closed = false;
      PaymentWaitingManager.show(
        tester.element(find.byType(Scaffold).first),
        onClose: () => closed = true,
        onPaymentSuccess: () {},
      );
      await tester.pump();
      PaymentWaitingManager.updateStep(step);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _captureScreen(tester, 'payment-${step.name}');
      if (step == PaymentStep.waitingPayment) {
        await tester.tap(find.text(AppLocalizations.current.xboardHandleLater));
        await tester.pump();
        expect(closed, isTrue);
      }
      PaymentWaitingManager.hide();
      await _disposeScreen(tester);
    });
  }
  for (final status in [0, 2, 3]) {
    testWidgets('payment result is confirmed by backend: $status', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        '/gateway',
        const Size(390, 844),
        Brightness.dark,
        paymentStatus: status,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        find.text(AppLocalizations.current.xboardPaymentSuccess),
        status == 3 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await _captureScreen(tester, 'gateway-status-$status');
      await _disposeScreen(tester);
    });
  }
  testWidgets('connected home uses runtime state', (tester) async {
    await _pumpScreen(
      tester,
      '/',
      const Size(390, 844),
      Brightness.dark,
      runTime: 120000,
    );
    expect(find.text(AppLocalizations.current.xboardStopProxy), findsOneWidget);
    await _captureScreen(tester, 'home-connected');
    await _disposeScreen(tester);
  });
  for (final route in ['/plans', '/support', '/invite', '/gateway']) {
    testWidgets('retry state: $route', (tester) async {
      await _pumpScreen(
        tester,
        route,
        const Size(390, 844),
        Brightness.dark,
        error: true,
      );
      expect(tester.takeException(), isNull);
      await _captureScreen(tester, '${route.substring(1)}-error');
      await _disposeScreen(tester);
    });
  }
}
