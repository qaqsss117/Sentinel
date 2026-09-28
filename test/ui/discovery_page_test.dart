import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';
import 'package:fl_clash/xboard/features/discovery/discovery_links.dart';
import 'package:fl_clash/xboard/features/discovery/discovery_page.dart';
import 'package:fl_clash/xboard/features/discovery/discovery_provider.dart';
import 'package:fl_clash/xboard/features/discovery/discovery_shortcuts.dart';
import 'package:fl_clash/xboard/features/discovery/discovery_store.dart';
import 'package:fl_clash/xboard/features/invite/widgets/user_menu_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:go_router/go_router.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
const _catalog = DiscoveryCatalog(
  sites: [
    DiscoverySite(
      id: 1,
      name: 'Google',
      url: 'https://www.google.com/',
      category: 'search',
      description: 'Search information across the web.',
    ),
    DiscoverySite(
      id: 2,
      name: 'GitHub',
      url: 'https://github.com/',
      category: 'developer',
      description: 'Code hosting and collaboration tools.',
    ),
  ],
);
const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

DiscoveryStore _store({Future<DiscoveryCatalog> Function()? fetch}) =>
    DiscoveryStore(
      fetch: fetch ?? () async => _catalog,
      readCache: () async => null,
      writeCache: (_) async {},
    );

Future<void> _mount(
  WidgetTester tester,
  DiscoveryStore store, {
  Size size = const Size(1100, 1000),
  Brightness brightness = Brightness.dark,
  DiscoveryUrlLauncher? launcher,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [discoveryProvider.overrideWith((_) => store)],
      child: RepaintBoundary(
        key: const ValueKey('discovery-screen'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              SentinelTheme.build(
                brightness: brightness,
                fontFamily: _capture ? 'UiTestFont' : null,
              ).copyWith(
                textTheme: SentinelTheme.build(
                  brightness: brightness,
                  fontFamily: _capture ? 'UiTestFont' : null,
                ).textTheme.apply(fontFamily: _capture ? 'UiTestFont' : null),
              ),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          localizationsDelegates: _delegates,
          home: DiscoveryPage(launcher: launcher ?? (_) async => true),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    if (_capture) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (font.existsSync()) {
        await (FontLoader('UiTestFont')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
    }
  });

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    for (final brightness in Brightness.values) {
      testWidgets('discovery layout at $size in $brightness', (tester) async {
        await _mount(tester, _store(), size: size, brightness: brightness);
        await tester.pumpAndSettle();
        expect(find.text('Discover'), findsOneWidget);
        expect(find.text('Google'), findsOneWidget);
        expect(find.text('GitHub'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (_capture) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('discovery-screen')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final width = size.width.toInt();
            final mode = brightness.name;
            final file = File(
              'build/discovery-previews/discovery-$width-$mode.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  testWidgets('category and keyword filters show matching and empty states', (
    tester,
  ) async {
    await _mount(tester, _store());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Developer tools'));
    await tester.pumpAndSettle();
    expect(find.text('Google'), findsNothing);
    expect(find.text('GitHub'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching sites'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'CODE');
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('No matching sites'), findsNothing);
  });

  testWidgets(
    'loading, failure and retry clear stale entries on successful empty response',
    (tester) async {
      final pending = Completer<DiscoveryCatalog>();
      var first = true;
      final store = _store(
        fetch: () {
          if (first) return pending.future;
          return Future.value(const DiscoveryCatalog());
        },
      );
      store.catalog = _catalog;
      await _mount(tester, store);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refresh failed'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
      first = false;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('No recommended sites yet'), findsOneWidget);
      expect(find.text('Google'), findsNothing);
      expect(find.textContaining('Refresh failed'), findsNothing);
    },
  );

  testWidgets('browser failure reports target and copies exact public link', (
    tester,
  ) async {
    Uri? opened;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _mount(
      tester,
      _store(),
      launcher: (uri) async {
        opened = uri;
        return false;
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Visit website'));
    await tester.pumpAndSettle();
    expect(opened.toString(), DiscoveryCatalog.defaultLandingPageUrl);
    expect(find.text('Could not open browser'), findsOneWidget);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, DiscoveryCatalog.defaultLandingPageUrl);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Open site').first);
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://www.google.com/');
    expect(find.text('Could not open browser'), findsOneWidget);
  });

  testWidgets('throwing browser launcher also offers link copy', (
    tester,
  ) async {
    await _mount(
      tester,
      _store(),
      launcher: (_) async => throw Exception('no browser'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Visit website'));
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home and user menu reach the same page and back keeps home state',
    (tester) async {
      final store = _store();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Column(
                children: [TextField(), DiscoveryShortcuts(), UserMenuWidget()],
              ),
            ),
          ),
          GoRoute(path: '/discover', builder: (_, _) => const DiscoveryPage()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [discoveryProvider.overrideWith((_) => store)],
          child: MaterialApp.router(
            routerConfig: router,
            theme: SentinelTheme.build(brightness: Brightness.dark),
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.delegate.supportedLocales,
            localizationsDelegates: _delegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep home state');
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('keep home state'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Discover'));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryPage), findsOneWidget);
    },
  );
}
