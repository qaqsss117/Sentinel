import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/profile/profile.dart';
import 'package:fl_clash/xboard/features/subscription/widgets/xboard_connect_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestProfileImportNotifier extends ProfileImportNotifier {
  _TestProfileImportNotifier(super.ref, ImportState initialState) {
    state = initialState;
  }
}

const _subscription = DomainSubscription(
  subscribeUrl: 'https://example.com/subscription',
  email: 'user@example.com',
  uuid: 'test-user',
  planId: 1,
  transferLimit: 1024,
  uploadedBytes: 0,
  downloadedBytes: 0,
);

const _importedProfile = Profile(
  id: 'subscription-profile',
  autoUpdateDuration: Duration(days: 1),
  subscriptionInfo: SubscriptionInfo(),
);

Future<void> _pumpButton(
  WidgetTester tester, {
  required DomainSubscription? subscription,
  required bool isImporting,
  Profile? currentProfile,
  ImportStatus status = ImportStatus.idle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        startButtonSelectorStateProvider.overrideWithValue(
          const StartButtonSelectorState(isInit: true, hasProfile: true),
        ),
        runTimeProvider.overrideWithValue(null),
        currentProfileProvider.overrideWithValue(currentProfile),
        subscriptionInfoProvider.overrideWith((ref) => subscription),
        profileImportProvider.overrideWith(
          (ref) => _TestProfileImportNotifier(
            ref,
            ImportState(status: status, isImporting: isImporting),
          ),
        ),
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
        home: Scaffold(body: XBoardConnectButton()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('disables connection before subscription is delivered', (
    tester,
  ) async {
    await _pumpButton(tester, subscription: null, isImporting: false);

    final button = tester.widget<InkWell>(find.byType(InkWell));
    expect(button.onTap, isNull);
  });

  testWidgets('disables connection while subscription is importing', (
    tester,
  ) async {
    await _pumpButton(tester, subscription: _subscription, isImporting: true);

    final button = tester.widget<InkWell>(find.byType(InkWell));
    expect(button.onTap, isNull);
  });

  testWidgets('enables connection after subscription import completes', (
    tester,
  ) async {
    await _pumpButton(
      tester,
      subscription: _subscription,
      isImporting: false,
      currentProfile: _importedProfile,
    );

    final button = tester.widget<InkWell>(find.byType(InkWell));
    expect(button.onTap, isNotNull);
  });

  testWidgets('keeps connection disabled after subscription import fails', (
    tester,
  ) async {
    await _pumpButton(
      tester,
      subscription: _subscription,
      isImporting: false,
      status: ImportStatus.failed,
    );

    final button = tester.widget<InkWell>(find.byType(InkWell));
    expect(button.onTap, isNull);
  });

  testWidgets('allows an existing subscription after refresh fails', (
    tester,
  ) async {
    await _pumpButton(
      tester,
      subscription: _subscription,
      currentProfile: _importedProfile,
      isImporting: false,
      status: ImportStatus.failed,
    );

    final button = tester.widget<InkWell>(
      find.byType(InkWell),
    );
    expect(button.onTap, isNotNull);
  });
}
