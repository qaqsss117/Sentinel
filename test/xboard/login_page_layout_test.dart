import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/features/auth/pages/login_page.dart';
import 'package:fl_clash/xboard/features/initialization/initialization.dart';
import 'package:fl_clash/xboard/infrastructure/storage/shared_prefs_storage.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReadyInitializationNotifier extends XBoardInitializationNotifier {
  _ReadyInitializationNotifier(super.ref) {
    state = const InitializationState(status: InitializationStatus.ready);
  }

  @override
  Future<void> initialize() async {}
}

class _TestAppSetting extends AppSetting {
  @override
  AppSettingProps build() => const AppSettingProps(locale: 'zh_CN');
}

Future<void> _pumpLogin(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
  final storage = await SharedPrefsStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(XBoardStorageService(storage)),
        initializationProvider.overrideWith(_ReadyInitializationNotifier.new),
        appSettingProvider.overrideWith(_TestAppSetting.new),
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
        home: LoginPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop places branding beside a compact login form', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(850, 555));
    final email = find.byType(TextFormField).first;
    final brand = find.byKey(const ValueKey('login-brand'));
    expect(tester.getRect(brand).right, lessThan(tester.getRect(email).left));
    expect(tester.getSize(email).width, inInclusiveRange(300, 440));
    expect(find.byType(FilledButton).hitTestable(), findsOneWidget);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(tester.getRect(brand).right, lessThan(tester.getRect(email).left));
    expect(tester.getSize(email).width, inInclusiveRange(300, 440));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing layout preserves credentials and password options', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(390, 800));
    final email = find.byType(TextFormField).first;
    final password = find.byType(TextFormField).last;
    final brand = find.byKey(const ValueKey('login-brand'));
    await tester.enterText(email, 'user@example.com');
    await tester.enterText(password, 'test-password');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));

    for (final width in [1000.0, 390.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('test-password'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      if (width < 760) {
        expect(
          tester.getRect(brand).bottom,
          lessThan(tester.getRect(email).top),
        );
      } else {
        expect(
          tester.getRect(brand).right,
          lessThan(tester.getRect(email).left),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('phone login fits and scrolls above the keyboard', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(360, 800));
    final email = find.byType(TextFormField).first;
    final bounds = tester.getRect(email);
    expect(bounds.left, greaterThanOrEqualTo(16));
    expect(bounds.right, lessThanOrEqualTo(344));
    expect(bounds.width, greaterThanOrEqualTo(280));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final login = find.byType(FilledButton);
    await tester.ensureVisible(login);
    await tester.pumpAndSettle();
    expect(login.hitTestable(), findsOneWidget);
    expect(tester.getRect(login).bottom, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short windows keep scrolled content below the toolbar', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(850, 460));
    final scrollView = find.byType(SingleChildScrollView);
    final toolbar = tester.getRect(find.byType(AppBar));
    expect(
      tester.getRect(scrollView).top,
      greaterThanOrEqualTo(toolbar.bottom),
    );
    final login = find.byType(FilledButton);
    await tester.ensureVisible(login);
    await tester.pumpAndSettle();
    expect(login.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text fits around the responsive breakpoint', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpLogin(tester, const Size(320, 640));

    for (final width in [320.0, 759.0, 760.0, 1080.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpAndSettle();
      final login = find.byType(FilledButton);
      await tester.ensureVisible(login);
      await tester.pumpAndSettle();
      expect(login.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
