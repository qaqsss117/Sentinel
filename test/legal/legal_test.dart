import 'package:fl_clash/legal/legal_consent_store.dart';
import 'package:fl_clash/legal/legal_documents.dart';
import 'package:fl_clash/legal/legal_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('legal documents contain complete Chinese and English versions', () {
    final termsZh = legalDocumentFor(LegalDocumentType.terms, english: false);
    final termsEn = legalDocumentFor(LegalDocumentType.terms, english: true);
    final privacyZh = legalDocumentFor(
      LegalDocumentType.privacy,
      english: false,
    );
    final privacyEn = legalDocumentFor(
      LegalDocumentType.privacy,
      english: true,
    );

    expect(termsZh.title, '用户协议');
    expect(termsEn.title, 'Terms of Service');
    expect(privacyZh.title, '隐私政策');
    expect(privacyEn.title, 'Privacy Policy');
    expect(termsZh.sections.length, greaterThanOrEqualTo(10));
    expect(termsEn.sections.length, termsZh.sections.length);
    expect(privacyZh.sections.length, greaterThanOrEqualTo(10));
    expect(privacyEn.sections.length, privacyZh.sections.length);
  });

  test('consent is valid only for the current legal version', () async {
    expect(await LegalConsentStore.isAccepted(), isFalse);

    SharedPreferences.setMockInitialValues({
      LegalConsentStore.acceptedVersionKey: 'old-version',
    });
    expect(await LegalConsentStore.isAccepted(), isFalse);

    SharedPreferences.setMockInitialValues({
      LegalConsentStore.acceptedVersionKey: legalConsentVersion,
    });
    expect(await LegalConsentStore.isAccepted(), isTrue);
  });

  test('accept stores the current version and acceptance time', () async {
    expect(await LegalConsentStore.accept(), isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(LegalConsentStore.acceptedVersionKey),
      legalConsentVersion,
    );
    expect(
      DateTime.tryParse(
        preferences.getString(LegalConsentStore.acceptedAtKey) ?? '',
      ),
      isNotNull,
    );
  });

  testWidgets('consent requires a check before continuing', (tester) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LegalConsentPage(onAccepted: () => accepted = true),
      ),
    );

    final button = find.byKey(const Key('legal-consent-accept'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('legal-consent-links')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('document page switches between Chinese and English', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentPage(type: LegalDocumentType.privacy),
      ),
    );

    expect(find.text('隐私政策'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}