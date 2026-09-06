import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'subscription identification uses the installed application version',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'appName': 'Sentinel',
              'packageName': 'com.example.sentinel',
              'version': '2.6.2',
              'buildNumber': '2025091115',
              'buildSignature': '',
            },
          );
      expect(
        await UserAgentConfig.get(UserAgentScenario.subscription),
        'FlClash/2.6.2',
      );
      expect(
        await UserAgentConfig.get(UserAgentScenario.subscriptionRacing),
        'FlClash/2.6.2',
      );
    },
  );
}
