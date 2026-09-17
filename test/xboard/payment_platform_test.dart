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
    Map<String, dynamic>? checkoutResponse,
    int checkoutStatus = 200,
  }) async {
    // 收银台 URL 可由服务端直接生成，覆盖响应快于弹窗首帧的情况。
    server = _PaymentServer(
      checkoutResponse ?? {'type': type, 'data': data},
      checkoutStatus: checkoutStatus,
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
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: [Locale('zh', 'CN')],
          locale: Locale('zh', 'CN'),
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

  const platforms = [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ];
  const nativeQrCodes = {
    'WeChat': 'weixin://wxpay/bizpayurl?pr=test',
    'Alipay': 'https://qr.alipay.com/TEST-NATIVE-CODE',
  };
  for (final platform in platforms) {
    for (final entry in nativeQrCodes.entries) {
      testWidgets('${platform.name} displays ${entry.key} QR content', (
        tester,
      ) async {
        await purchase(tester, platform, 0, entry.value);
        for (
          var i = 0;
          i < 20 && find.byType(QrImageView).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(server.checkout!.data.containsKey('payment_mode'), isFalse);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(
          find.text(
            platform == TargetPlatform.windows ? '请使用手机扫码支付' : '请截图后扫码支付',
          ),
          findsOneWidget,
        );
        expect(launches, isEmpty);
        expect(clipboard, isNull);
        final checks = server.orderChecks;
        await tester.pump(const Duration(seconds: 3));
        expect(server.orderChecks, greaterThan(checks));
        PaymentWaitingManager.hide();
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  for (final platform in platforms) {
    testWidgets(
      '${platform.name} opens configured redirect payment without a QR code',
      (tester) async {
        await purchase(
          tester,
          platform,
          1,
          'https://pay.example/submit.php?sign=test-signature',
        );
        await tester.pump(const Duration(seconds: 1));

        expect(server.checkout!.data.containsKey('payment_mode'), isFalse);
        expect(find.byType(QrImageView), findsNothing);
        expect(find.textContaining('支付通道未返回原生支付二维码'), findsNothing);
        expect(launches, hasLength(1));
        expect(
          launches.single.arguments['url'],
          'https://pay.example/submit.php?sign=test-signature',
        );
        expect(clipboard, 'https://pay.example/submit.php?sign=test-signature');
        final checks = server.orderChecks;
        await tester.pump(const Duration(seconds: 3));
        expect(server.orderChecks, greaterThan(checks));
        PaymentWaitingManager.hide();
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('gateway QR failure is shown to the customer', (tester) async {
    const message = '支付通道未返回原生支付二维码，请联系管理员切换扫码支付通道';
    await purchase(
      tester,
      TargetPlatform.android,
      0,
      '',
      checkoutResponse: {'message': message},
      checkoutStatus: 400,
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining(message), findsOneWidget);
    expect(find.textContaining('支付请求返回空结果'), findsNothing);
    expect(launches, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
