import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/xboard/features/subscription/services/managed_subscription_profile.dart';
import 'package:fl_clash/xboard/features/subscription/services/upstream_usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldVersion = 'a' * 64;
  final newVersion = 'b' * 64;
  const oldContent = 'proxies: []';
  const newContent = 'proxies: [{name: HK refreshed, type: direct}]';
  late Directory directory;
  late File profile;
  late File journal;
  late UpstreamUsageService service;
  late List<String> actions;
  late List<Map<String, dynamic>> begins;
  var changesAgain = false;
  var invalid = false;
  var downloadFails = false;
  var cancelValidation = false;
  var cancelReopen = false;
  var badVersion = false;
  String? denial;
  Completer<void>? downloading;
  Completer<void>? releaseDownload;

  Map<String, dynamic> lease() => {
    'allowed': true,
    'status': 'active',
    'period': '0:0',
    'configuration_version': newVersion,
    'nodes': {
      'HK refreshed': {'id': 9},
    },
    'remaining': 1000,
    'lease_until': 400,
    'server_time': 100,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'xboard_token': 'account-token',
      'upstream_device_id': 'device-a',
    });
    directory = await Directory.systemTemp.createTemp('upstream-refresh-');
    profile = File('${directory.path}/profile.yaml');
    journal = File('${directory.path}/journal.json');
    await ManagedSubscriptionProfile.install(
      file: profile,
      content: oldContent,
      version: oldVersion,
      coreVersion: UpstreamUsageService.coreVersion,
      validate: (_) async => '',
    );
    actions = [];
    begins = [];
    changesAgain = false;
    invalid = false;
    downloadFails = false;
    cancelValidation = false;
    cancelReopen = false;
    badVersion = false;
    denial = null;
    downloading = null;
    releaseDownload = null;
    service = UpstreamUsageService(
      profileFile: (_) async => profile,
      journalFile: () async => journal,
      validateConfiguration: (_) async {
        if (cancelValidation) await service.stop('closed');
        return invalid ? 'invalid config' : '';
      },
      invokeCore: (request) async {
        if (request['operation'] == 'begin') {
          begins.add(request);
          expect(await profile.readAsString(), newContent);
          expect(
            await ManagedSubscriptionProfile.version(
              profile,
              UpstreamUsageService.coreVersion,
            ),
            newVersion,
          );
        }
        return {'metering_version': 1, 'reason': '', 'traffic': {}};
      },
      sendRequest: (action, body, token) async {
        if (action == 'open') {
          expect(token, 'account-token');
          final preview = body['configuration_only'] == true;
          actions.add(preview ? 'preview' : 'open');
          if (denial != null) return {'allowed': false, 'status': denial};
          if (!preview &&
              (body['configuration_version'] != newVersion || changesAgain)) {
            return {
              'allowed': false,
              'status': 'configuration_changed',
              'configuration_version': changesAgain ? 'c' * 64 : newVersion,
            };
          }
          if (!preview && cancelReopen) await service.stop('closed');
          return {
            ...lease(),
            'session_id': preview ? 'preview' : 'running',
            'session_token': preview ? 'preview-token' : 'running-token',
          };
        }
        if (action == 'configuration') {
          actions.add('configuration');
          expect(token, 'preview-token');
          downloading?.complete();
          if (releaseDownload != null) await releaseDownload!.future;
          if (downloadFails) throw const SocketException('offline');
          return {
            ...lease(),
            'content': newContent,
            if (badVersion) 'configuration_version': 'c' * 64,
          };
        }
        if (action == 'close') {
          actions.add('close:$token');
          return {'allowed': false, 'status': 'closed'};
        }
        throw StateError('Unexpected request: $action');
      },
    );
  });

  tearDown(() async {
    await service.stop('closed');
    await directory.delete(recursive: true);
  });

  test(
    'a changed upstream configuration refreshes once and connects with the new mapping',
    () async {
      await service.prepare('profile');
      expect(actions, [
        'open',
        'preview',
        'configuration',
        'close:preview-token',
        'open',
      ]);
      expect(begins.single['tags'], {'HK refreshed': '9'});
      expect(jsonDecode(await journal.readAsString())['session_id'], 'running');

      // A subsequent connection with the same version keeps the fast path.
      await service.stop('closed');
      await service.prepare('profile');
      expect(
        actions.where((action) => action == 'configuration'),
        hasLength(1),
      );
      expect(begins, hasLength(2));
    },
  );

  test(
    'continuous upstream changes do not cause an unlimited refresh loop',
    () async {
      changesAgain = true;
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(
        actions.where((action) => action == 'configuration'),
        hasLength(1),
      );
      expect(actions.where((action) => action == 'open'), hasLength(2));
      expect(begins, isEmpty);
      expect(await journal.exists(), isFalse);
    },
  );

  test(
    'invalid refreshed configuration preserves the previous profile and version',
    () async {
      invalid = true;
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(actions, contains('configuration'));
      expect(await profile.readAsString(), oldContent);
      expect(
        await ManagedSubscriptionProfile.version(
          profile,
          UpstreamUsageService.coreVersion,
        ),
        oldVersion,
      );
      expect(begins, isEmpty);
    },
  );

  test(
    'cancelling a refresh prevents a late download from starting or replacing the profile',
    () async {
      downloading = Completer<void>();
      releaseDownload = Completer<void>();
      final preparing = service.prepare('profile');
      final failure = expectLater(preparing, throwsStateError);
      await downloading!.future.timeout(const Duration(seconds: 3));
      await service.stop('closed');
      releaseDownload!.complete();
      await failure;
      expect(await profile.readAsString(), oldContent);
      expect(begins, isEmpty);
      expect(actions, contains('close:preview-token'));
    },
  );

  test(
    'account denial never triggers a configuration refresh or native session',
    () async {
      denial = 'quota_exhausted';
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(actions, ['open']);
      expect(begins, isEmpty);
    },
  );

  test(
    'a failed download closes the preview session and preserves the cached profile',
    () async {
      downloadFails = true;
      await expectLater(
        service.prepare('profile'),
        throwsA(isA<SocketException>()),
      );
      expect(actions, [
        'open',
        'preview',
        'configuration',
        'close:preview-token',
      ]);
      expect(await profile.readAsString(), oldContent);
      expect(begins, isEmpty);
    },
  );

  test(
    'a version change during download never installs mismatched content',
    () async {
      badVersion = true;
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(actions, [
        'open',
        'preview',
        'configuration',
        'close:preview-token',
      ]);
      expect(await profile.readAsString(), oldContent);
      expect(begins, isEmpty);
    },
  );

  test('cancelling native validation preserves the previous file', () async {
    cancelValidation = true;
    await expectLater(service.prepare('profile'), throwsStateError);
    expect(await profile.readAsString(), oldContent);
    expect(begins, isEmpty);
  });

  test(
    'cancelling a successful retry closes its unused authorization',
    () async {
      cancelReopen = true;
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(begins, isEmpty);
      expect(actions.last, 'close:running-token');
      expect(await journal.exists(), isFalse);
    },
  );

  test(
    'a disabled source cannot bypass authorization through original display names',
    () async {
      denial = 'disabled';
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(actions, ['open']);
      expect(begins, isEmpty);
    },
  );

  test(
    'a modified local profile is rejected before requesting authorization',
    () async {
      await profile.writeAsString('proxies: [{name: modified, type: direct}]');
      await expectLater(service.prepare('profile'), throwsStateError);
      expect(actions, isEmpty);
      expect(begins, isEmpty);
      expect(await journal.exists(), isFalse);
    },
  );
}
