import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/xboard/features/subscription/services/upstream_usage_service.dart';
import 'package:fl_clash/xboard/features/subscription/services/managed_subscription_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File journal;
  late File profile;
  late Map<String, dynamic> counters;
  late List<String> operations;
  late List<Map<String, dynamic>> closes;
  late Completer<Map<String, dynamic>> report;
  late UpstreamUsageService service;
  var closeFails = false;
  var configurationFails = false;
  var opens = 0;
  final configurationVersion = 'a' * 64;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'xboard_token': 'account-token',
      'upstream_device_id': 'device-a',
    });
    directory = await Directory.systemTemp.createTemp(
      'sentinel-upstream-test-',
    );
    journal = File('${directory.path}/journal.json');
    profile = File('${directory.path}/profile.yaml');
    await ManagedSubscriptionProfile.install(file: profile, content: 'proxies: []',
      version: configurationVersion, coreVersion: UpstreamUsageService.coreVersion, validate: (_) async => '');
    counters = {
      '7': [10, 20],
    };
    operations = [];
    closes = [];
    report = Completer<Map<String, dynamic>>();
    closeFails = false;
    configurationFails = false;
    opens = 0;
    service = UpstreamUsageService(
      journalFile: () async => journal,
      profileFile: (_) async => profile,
      validateConfiguration: (_) async => configurationFails ? 'invalid' : '',
      invokeCore: (request) async {
        operations.add(request['operation'] as String);
        return {
          'metering_version': 1,
          'traffic': jsonDecode(jsonEncode(counters)),
          'reason': '',
        };
      },
      sendRequest: (action, body, token) async {
        switch (action) {
          case 'open':
            expect(body['configuration_version'], configurationVersion);
            return {
              'allowed': true,
              'session_id': 'session-${++opens}',
              'session_token': 'restricted',
              'period': '0:0',
              'configuration_version': configurationVersion,
              'nodes': {'upstream-7': {'id': 7}},
              'remaining': 1000,
              'lease_until': 400,
              'server_time': 100,
            };
          case 'configuration':
            fail('Connecting must not download configuration');
          case 'report':
            return report.future;
          case 'close':
            closes.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
            if (closeFails) throw const SocketException('offline');
            return {'allowed': false, 'status': 'closed'};
          default:
            throw StateError(action);
        }
      },
    );
  });

  tearDown(() async {
    await service.stop('closed');
    if (!report.isCompleted) {
      report.complete({'allowed': false, 'status': 'closed'});
    }
    await directory.delete(recursive: true);
  });

  test(
    'a slow report does not block checkpoints; stopping rejects a late renewal',
    () async {
      await service.prepare('profile');
      await service.checkpoint(reportNow: true);
      counters = {
        '7': [30, 50],
      };
      await service.checkpoint();
      expect(jsonDecode(await journal.readAsString())['traffic']['7'], [
        30,
        50,
      ]);
      await service.stop('closed');
      expect(operations, contains('stop'));
      expect(closes.single['traffic']['7'], [30, 50]);
      report.complete({
        'allowed': true,
        'remaining': 920,
        'confirmed': {
          '7': [30, 50],
        },
        'lease_until': 430,
        'server_time': 130,
      });
      await Future<void>.delayed(Duration.zero);
      expect(operations, isNot(contains('renew')));
    },
  );

  test(
    'failed final report is durable and settled before the next session opens',
    () async {
      await service.prepare('profile');
      closeFails = true;
      await service.stop('closed');
      expect(await journal.exists(), isTrue);
      final previous = jsonDecode(await journal.readAsString());
      closeFails = false;
      await service.prepare('profile');
      expect(closes[1]['traffic'], previous['traffic']);
      expect(closes[1]['seq'], greaterThan(previous['seq'] as int));
      expect(opens, 2);
    },
  );

  test(
    'configuration failure never charges the previous native counters to a new session',
    () async {
      configurationFails = true;
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(closes.single['traffic'], isEmpty);
      expect(operations, isNot(contains('stop')));
    },
  );
}
