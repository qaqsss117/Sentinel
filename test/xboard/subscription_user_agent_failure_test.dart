import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unavailable package information does not fabricate a version',
    () async {
      const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'unavailable'),
          );
      expect(
        await UserAgentConfig.get(UserAgentScenario.subscription),
        'FlClash',
      );
      expect(
        await UserAgentConfig.get(UserAgentScenario.subscriptionRacing),
        'FlClash',
      );
    },
  );
}
