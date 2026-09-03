import 'package:fl_clash/common/build_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MSIX builds disable privileged Windows features', () {
    const capabilities = BuildCapabilities(isMsix: true);

    expect(capabilities.supportsTun, isFalse);
    expect(capabilities.supportsHelperService, isFalse);
    expect(capabilities.supportsLoopbackExemption, isFalse);
    expect(capabilities.supportsAutoLaunchControl, isFalse);
    expect(capabilities.resolveTunEnabled(true), isFalse);
  });

  test('standard builds preserve existing features', () {
    const capabilities = BuildCapabilities(isMsix: false);

    expect(capabilities.supportsTun, isTrue);
    expect(capabilities.supportsHelperService, isTrue);
    expect(capabilities.supportsLoopbackExemption, isTrue);
    expect(capabilities.supportsAutoLaunchControl, isTrue);
    expect(capabilities.resolveTunEnabled(true), isTrue);
    expect(capabilities.resolveTunEnabled(false), isFalse);
  });

  test('Microsoft Store builds defer updates to the Store', () {
    const capabilities = BuildCapabilities(
      isMsix: true,
      isStoreBuild: true,
    );

    expect(capabilities.supportsExternalUpdateCheck, isFalse);
  });

  test('sideload MSIX builds keep external update checks', () {
    const capabilities = BuildCapabilities(
      isMsix: true,
      isStoreBuild: false,
    );

    expect(capabilities.supportsExternalUpdateCheck, isTrue);
  });
}
