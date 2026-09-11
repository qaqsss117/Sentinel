import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/adapter/initialization/sdk_provider.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/payment/pages/plan_purchase_page.dart';
import 'package:fl_clash/xboard/features/payment/widgets/payment_waiting_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _AuthenticatedUser extends XBoardUserAuthNotifier {
  @override
  UserAuthState build() => const UserAuthState(isAuthenticated: true);
}

class _PaymentServer implements HttpClientAdapter {
  final Map<String, dynamic> checkoutResponse;
  final int checkoutStatus;
  RequestOptions? checkout;
  bool created = false;
  int orderChecks = 0;

  _PaymentServer(this.checkoutResponse, {this.checkoutStatus = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object response;
    switch (options.path) {
      case '/api/v1/user/order/getPaymentMethod':
        response = {
          'status': 'success',
          'data': [
            {'id': 7, 'name': '测试支付', 'handling_fee_percent': 0},
          ],
        };
      case '/api/v1/user/order/save':
        created = true;
        response = {'status': 'success', 'data': 'ORDER-1'};
      case '/api/v1/user/order/fetch':
        orderChecks++;
        response = {
          'status': 'success',
          'data': [
            if (created)
              {'trade_no': 'ORDER-1', 'status': 0, 'total_amount': 2800},
          ],
        };
      case '/api/v1/user/order/checkout':
        checkout = options;
        response = checkoutResponse;
      default:
        throw StateError('Unexpected payment request: ${options.path}');
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      options.path == '/api/v1/user/order/checkout' ? checkoutStatus : 200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PaymentServer server;
  late List<MethodCall> launches;
  String? clipboard;
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  setUp(() async {
    XBoardLogger.setLogger(ConsoleLogger(minLevel: LogLevel.error));
    launches = [];
    clipboard = null;
    await XBoardSDK.instance.initialize(
      'https://panel.example',
      panelType: 'xboard',
      useMemoryStorage: true,
    );
    await XBoardSDK.instance.saveToken('test-token');
  });

  tearDown(() {
    PaymentWaitingManager.hide();
    XBoardSDK.instance.dispose();
    XBoardLogger.reset();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> purchase(
    WidgetTester tester,
    TargetPlatform platform,
    int type,
    String data, {
    String? checkoutError,
    bool launchSucceeds = true,
    bool canLaunch = true,
  }) async {
    // 即时响应覆盖支付数据早于弹窗首帧到达的情况。
    server = _PaymentServer(
      checkoutError == null
          ? {'type': type, 'data': data}
          : {'message': checkoutError},
      checkoutStatus: checkoutError == null ? 200 : 400,
    );
    XBoardSDK.instance.httpService.dio.httpClientAdapter = server;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = call.arguments['text'] as String;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
          if (call.method == 'canLaunch') return canLaunch;
          if (call.method == 'launch') {
            launches.add(call);
            return launchSucceeds;
          }
          return false;
        });
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          xboardUserAuthProvider.overrideWith(_AuthenticatedUser.new),
          xboardSdkProvider.overrideWith((ref) async => XBoardSDK.instance),
        ],
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN')],
          locale: const Locale('zh', 'CN'),
          home: const PlanPurchasePage(
            plan: DomainPlan(
              id: 1,
              name: '测试套餐',
              groupId: 1,
              transferQuota: 1073741824,
              monthlyPrice: 28,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final buy = find.widgetWithText(ElevatedButton, '确认购买');
    await tester.ensureVisible(buy);
    await tester.tap(buy);
    // 创建订单有一秒等待。
    for (var i = 0; i < 20 && server.checkout == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(server.checkout, isNotNull);
    await tester.pump();
  }

  for (final type in [0, 1]) {
    testWidgets('Windows shows a QR code for Xboard type $type', (
      tester,
    ) async {
      final data = type == 0
          ? 'weixin://wxpay/bizpayurl?pr=test'
          : 'https://pay.example/checkout';
      await purchase(tester, TargetPlatform.windows, type, data);
      for (
        var i = 0;
        i < 20 && find.byType(QrImageView).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(server.checkout!.data['payment_mode'], 'qrcode');
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('请使用手机扫码支付'), findsOneWidget);
      expect(launches, isEmpty);

      final checks = server.orderChecks;
      await tester.pump(const Duration(seconds: 3));
      expect(server.orderChecks, greaterThan(checks));
      PaymentWaitingManager.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final data in [
    'https://pay.example/checkout?token=a%2Bb%26c',
    'weixin://dl/business/?ticket=test-ticket',
    'alipays://platformapi/startapp?appId=20000067&url=https%3A%2F%2Fpay.example',
  ]) {
    testWidgets('Android launches the ${Uri.parse(data).scheme} payment URL', (
      tester,
    ) async {
      await purchase(tester, TargetPlatform.android, 1, data, canLaunch: false);
      for (var i = 0; i < 20 && launches.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(server.checkout!.data['payment_mode'], 'url');
      expect(find.byType(QrImageView), findsNothing);
      expect(launches, hasLength(1));
      expect(launches.single.arguments['url'], data);
      expect(launches.single.arguments['useWebView'], isFalse);
      expect(launches.single.arguments['useSafariVC'], isFalse);
      expect(clipboard, data.startsWith('https:') ? data : isNull);
      final checks = server.orderChecks;
      await tester.pump(const Duration(seconds: 3));
      expect(server.orderChecks, greaterThan(checks));
      PaymentWaitingManager.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final data in [
    'weixin://wxpay/bizpayurl?pr=test',
    'https://qr.example/payment',
  ]) {
    testWidgets('Android rejects ${Uri.parse(data).scheme} QR payloads', (
      tester,
    ) async {
      await purchase(tester, TargetPlatform.android, 0, data);
      await tester.pump(const Duration(milliseconds: 100));
      expect(launches, isEmpty);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('请联系管理员检查手机支付通道'), findsOneWidget);
      PaymentWaitingManager.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'Android displays the gateway error without launching a browser',
    (tester) async {
      await purchase(
        tester,
        TargetPlatform.android,
        1,
        '',
        checkoutError: '当前通道不支持手机支付',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(launches, isEmpty);
      expect(find.textContaining('当前通道不支持手机支付'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Android explains when no wallet can handle the link', (
    tester,
  ) async {
    await purchase(
      tester,
      TargetPlatform.android,
      1,
      'weixin://dl/business/?ticket=test-ticket',
      launchSucceeds: false,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(launches, hasLength(1));
    expect(find.textContaining('请确认已安装微信或支付宝'), findsOneWidget);
    expect(find.byType(PaymentWaitingOverlay), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
