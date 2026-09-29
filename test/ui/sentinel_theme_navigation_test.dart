import 'dart:convert';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/theme/sentinel_theme.dart';
import 'package:fl_clash/theme/sentinel_widgets.dart';
import 'package:fl_clash/xboard/router/shell_layout.dart';
import 'package:fl_clash/xboard/router/auth_redirect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('saved session exits loading and refresh keeps the active page', (
    tester,
  ) async {
    final auth = ValueNotifier((initialized: false, authenticated: false));
    final router = GoRouter(
      refreshListenable: auth,
      redirect: (_, state) => redirectForAuth(
        path: state.uri.path,
        isInitialized: auth.value.initialized,
        isAuthenticated: auth.value.authenticated,
      ),
      routes: [
        for (final path in ['/', '/loading', '/login', '/plans'])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text(path)),
          ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('/loading'), findsOneWidget);
    auth.value = (initialized: true, authenticated: true);
    await tester.pumpAndSettle();
    expect(find.text('/'), findsOneWidget);
    router.go('/plans');
    await tester.pumpAndSettle();
    router.refresh();
    await tester.pumpAndSettle();
    expect(find.text('/plans'), findsOneWidget);
    auth.value = (initialized: true, authenticated: false);
    await tester.pumpAndSettle();
    expect(find.text('/login'), findsOneWidget);
    auth.value = (initialized: true, authenticated: true);
    await tester.pumpAndSettle();
    expect(find.text('/'), findsOneWidget);
  });

  test('fresh install is dark; saved appearance and custom accent survive', () {
    expect(defaultThemeProps.themeMode, ThemeMode.dark);
    for (final mode in ThemeMode.values) {
      final original = ThemeProps(
        themeMode: mode,
        primaryColor: 0xFF12806F,
        pureBlack: true,
        textScale: const TextScale(enable: true, scale: 1.5),
      );
      expect(
        ThemeProps.safeFromJson(jsonDecode(jsonEncode(original))),
        original,
      );
    }
    final legacy = ThemeProps.safeFromJson({
      'primaryColor': 0xFFD8C0C3,
      'themeMode': 'light',
    });
    expect(legacy.primaryColor, SentinelTheme.primary.toARGB32());
    expect(legacy.themeMode, ThemeMode.light);
    expect(ThemeProps.safeFromJson({}).themeMode, ThemeMode.system);
    final black = SentinelTheme.build(
      brightness: Brightness.dark,
      pureBlack: true,
    );
    expect(black.extension<SentinelColors>()!.backgroundTop, Colors.black);
    expect(black.colorScheme.surface, Colors.black);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform keeps four branches, drafts, detail return and back',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = platform == TargetPlatform.android
            ? const Size(390, 844)
            : const Size(1440, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final paths = ['/', '/plans', '/discover', '/invite'];
        final router = GoRouter(
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (_, _, shell) => AdaptiveShellLayout(child: shell),
              branches: [
                for (var i = 0; i < 4; i++)
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: paths[i],
                        builder: (_, _) => _DraftPage(index: i),
                      ),
                    ],
                  ),
              ],
            ),
            GoRoute(
              path: '/detail',
              builder: (_, _) =>
                  Scaffold(appBar: AppBar(title: const Text('Detail'))),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: router,
              theme: SentinelTheme.build(
                brightness: Brightness.dark,
              ).copyWith(platform: platform),
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (_, child) => SentinelBackground(child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'preserve my draft');
        for (var i = 1; i < 4; i++) {
          if (platform == TargetPlatform.android) {
            final nav = tester.widget<NavigationBar>(
              find.byType(NavigationBar),
            );
            expect(nav.destinations, hasLength(4));
            nav.onDestinationSelected!(i);
          } else {
            final nav = tester.widget<NavigationRail>(
              find.byType(NavigationRail),
            );
            expect(nav.destinations, hasLength(4));
            nav.onDestinationSelected!(i);
          }
          await tester.pumpAndSettle();
          expect(find.text('Branch $i'), findsOneWidget);
        }
        router.push('/detail');
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Branch 3'), findsOneWidget);
        if (platform == TargetPlatform.android) {
          await tester.binding.handlePopRoute();
        } else {
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .onDestinationSelected!(0);
        }
        await tester.pumpAndSettle();
        expect(find.text('preserve my draft'), findsOneWidget);
        if (platform == TargetPlatform.windows) {
          tester.view.physicalSize = const Size(850, 600);
          await tester.pumpAndSettle();
          expect(
            tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
            isFalse,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _DraftPage extends StatefulWidget {
  const _DraftPage({required this.index});
  final int index;
  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('Branch ${widget.index}'),
          TextField(controller: controller),
        ],
      ),
    ),
  );
}
