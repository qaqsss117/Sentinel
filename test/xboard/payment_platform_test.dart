import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/l10n/l10n.dart';
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
  RequestOptions? checkout;
  bool created = false;
  int orderChecks = 0;

  _PaymentServer(this.checkoutResponse);

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
      200,
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
    String data,
  ) async {
    // 收银台 URL 可由服务端直接生成，覆盖响应快于弹窗首帧的情况。
    server = _PaymentServer({'type': type, 'data': data});
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
          if (call.method == 'launch') launches.add(call);
          return true;
        });
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          xboardUserAuthProvider.overrideWith(_AuthenticatedUser.new),
          xboardSdkProvider.overrideWith((ref) async => XBoardSDK.instance),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: [Locale('zh', 'CN')],
          locale: Locale('zh', 'CN'),
          home: PlanPurchasePage(
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

    testWidgets('Android opens the URL for Xboard type $type', (tester) async {
      // type=0 的 HTTPS 二维码链接也应在 Android 上交给浏览器打开。
      const data = 'https://pay.example/checkout';
      await purchase(tester, TargetPlatform.android, type, data);
      for (var i = 0; i < 20 && launches.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(server.checkout!.data['payment_mode'], 'url');
      expect(find.byType(QrImageView), findsNothing);
      expect(launches, hasLength(1));
      expect(launches.single.arguments['url'], data);
      expect(launches.single.arguments['useWebView'], isFalse);
      expect(launches.single.arguments['useSafariVC'], isFalse);
      expect(clipboard, data);
      final checks = server.orderChecks;
      await tester.pump(const Duration(seconds: 3));
      expect(server.orderChecks, greaterThan(checks));
      PaymentWaitingManager.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
