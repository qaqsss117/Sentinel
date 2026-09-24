import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/features/subscription/services/managed_subscription_profile.dart';
import 'package:fl_clash/xboard/features/subscription/services/upstream_usage_service.dart';
import 'package:fl_clash/xboard/features/subscription/services/upstream_transport_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold service uses the ready UI transport before opening a session',
    () async {
      SharedPreferences.setMockInitialValues({
        'xboard_token': 'account-token',
        'upstream_device_id': 'device-a',
      });
      final directory = await Directory.systemTemp.createTemp(
        'upstream-handoff-',
      );
      final profile = File('${directory.path}/profile.yaml');
      final journal = File('${directory.path}/usage.json');
      await ManagedSubscriptionProfile.install(
        file: profile,
        content: 'proxies: []',
        version: 'a' * 64,
        coreVersion: UpstreamUsageService.coreVersion,
        validate: (_) async => '',
      );
      final uiConfig = HttpConfig(
        encryptedGateway: EncryptedGatewayConfig(
          path: '/abcdefghijklmnopqrstuvwxyz012345',
          keyId: 27,
          serverPublicKey: base64Url
              .encode(List.filled(32, 7))
              .replaceAll('=', ''),
        ),
        userAgent: 'handoff-test',
        // The background transport must retain the UI's security settings.
        certificatePath: 'assets/cer/client-cert.crt',
        enableCertificatePinning: true,
        proxyUrl: '127.0.0.1:7890',
        connectTimeoutSeconds: 7,
      );
      await XBoardSDK.instance.initialize(
        'https://127.0.0.1',
        panelType: 'xboard',
        httpConfig: uiConfig,
        useMemoryStorage: true,
        requireEncryptedGateway: true,
      );
      await XBoardSDK.instance.saveToken('ui-token-must-not-be-copied');
      final wire = jsonEncode(UpstreamUsageService.prepareCommand('profile'));
      // Model Android's separate service isolate: no UI singleton survives IPC.
      XBoardSDK.instance.dispose();
      XBoardConfig.reset();
      rootBundle.evict(ConfigFileLoader.configPath);
      var rediscoveryLoads = 0;
      binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
        message,
      ) async {
        if (utf8.decode(message!.buffer.asUint8List()) ==
            ConfigFileLoader.configPath) {
          rediscoveryLoads++;
          // Never contact production sources from this regression test.
          return ByteData.sublistView(
            Uint8List.fromList(utf8.encode('xboard: {}')),
          );
        }
        return null;
      });
      final transports = <String>[];
      var reachedAuthorization = false;
      final service = UpstreamUsageService(
        profileFile: (_) async => profile,
        journalFile: () async => journal,
        createHttp: (url, config) async {
          transports.add(url);
          expect(config.encryptedGateway!.keyId, 27);
          expect(
            config.encryptedGateway!.serverPublicKey,
            uiConfig.encryptedGateway!.serverPublicKey,
          );
          expect(config.certificatePath, uiConfig.certificatePath);
          expect(config.enableCertificatePinning, isTrue);
          expect(config.ignoreCertificateHostname, isFalse);
          expect(config.userAgent, uiConfig.userAgent);
          expect(config.connectTimeoutSeconds, 7);
          expect(config.proxyUrl, isNull);
          // Stop at the authorization boundary; this test targets discovery latency.
          throw const _AuthorizationReached();
        },
      );
      addTearDown(() async {
        binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        );
        rootBundle.evict(ConfigFileLoader.configPath);
        XBoardSDK.instance.dispose();
        XBoardConfig.reset();
        await directory.delete(recursive: true);
      });
      Object? unexpectedError;
      try {
        await service.handleControl(jsonDecode(wire) as Map<String, dynamic>);
      } on _AuthorizationReached {
        reachedAuthorization = true;
      } catch (error) {
        unexpectedError = error;
      }
      expect(
        rediscoveryLoads,
        0,
        reason:
            'Connect must not reload remote panel discovery after UI initialization',
      );
      expect(unexpectedError, isNull);
      expect(reachedAuthorization, isTrue);
      expect(transports, ['https://127.0.0.1']);
      expect(wire, isNot(contains('ui-token-must-not-be-copied')));
      expect(await journal.exists(), isFalse);
    },
  );

  test(
    'headless start retains discovery when no UI transport is available',
    () async {
      SharedPreferences.setMockInitialValues({
        'xboard_token': 'account-token',
        'upstream_device_id': 'device-a',
      });
      XBoardSDK.instance.dispose();
      XBoardConfig.reset();
      rootBundle.evict(ConfigFileLoader.configPath);
      final directory = await Directory.systemTemp.createTemp(
        'upstream-headless-',
      );
      final profile = File('${directory.path}/profile.yaml');
      await profile.writeAsString('proxies: []');
      var discoveryLoads = 0;
      binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
        message,
      ) async {
        if (utf8.decode(message!.buffer.asUint8List()) ==
            ConfigFileLoader.configPath) {
          discoveryLoads++;
          return ByteData.sublistView(
            Uint8List.fromList(utf8.encode('xboard: {}')),
          );
        }
        return null;
      });
      addTearDown(() async {
        binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        );
        rootBundle.evict(ConfigFileLoader.configPath);
        XBoardConfig.reset();
        await directory.delete(recursive: true);
      });
      final service = UpstreamUsageService(
        profileFile: (_) async => profile,
        journalFile: () async => File('${directory.path}/usage.json'),
      );
      final command = UpstreamUsageService.prepareCommand('profile');
      expect(command.containsKey('transport'), isFalse);
      // The empty fixture deliberately stops discovery before any public request.
      await expectLater(
        service.handleControl(command),
        throwsA(
          predicate(
            (error) => error.toString().contains(
              'Remote config sources cannot be empty',
            ),
          ),
        ),
      );
      expect(discoveryLoads, 1);
    },
  );

  test(
    'transport handoff rejects unsafe destinations and missing security',
    () {
      final config = HttpConfig(
        encryptedGateway: EncryptedGatewayConfig(
          path: '/abcdefghijklmnopqrstuvwxyz012345',
          keyId: 27,
          serverPublicKey: base64Url
              .encode(List.filled(32, 7))
              .replaceAll('=', ''),
        ),
      );
      for (final url in [
        'http://panel.example',
        'https://user:password@panel.example',
        'https://panel.example?token=private',
        'https://panel.example#fragment',
      ]) {
        expect(() => UpstreamTransportConfig(url, config), throwsStateError);
      }
      expect(
        () => UpstreamTransportConfig(
          'https://panel.example',
          const HttpConfig(),
        ),
        throwsStateError,
      );
      expect(
        () => UpstreamTransportConfig(
          'https://panel.example',
          config.copyWith(ignoreCertificateHostname: true),
        ),
        throwsStateError,
      );
      expect(
        () => UpstreamTransportConfig(
          'https://panel.example',
          config.copyWith(enableCertificatePinning: true),
        ),
        throwsStateError,
      );
    },
  );
}

class _AuthorizationReached implements Exception {
  const _AuthorizationReached();
}
