import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/xboard/features/subscription/services/upstream_usage_service.dart';
import 'package:fl_clash/xboard/features/subscription/services/managed_subscription_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _configuration = '''proxies:
  - {name: self-hosted, type: trojan, server: self.example.com, port: 443, password: own-password}
  - {name: upstream-7, type: anytls, server: node.example.com, port: 443, password: test-password}
proxy-groups:
  - {name: PROXY, type: select, proxies: [self-hosted, upstream-7]}
rules: ['MATCH,PROXY']
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in [
    (legacyEnvelope: true, omitStatus: false),
    (legacyEnvelope: false, omitStatus: false),
    (legacyEnvelope: false, omitStatus: true),
  ]) {
    test(
      'managed startup and settlement through encrypted SDK ($scenario)',
      () async {
        SharedPreferences.setMockInitialValues({
          'xboard_token': 'account-token',
          'upstream_device_id': 'device-a',
        });
        final directory = await Directory.systemTemp.createTemp(
          'upstream-gateway-',
        );
        final profile = File('${directory.path}/profile.yaml');
        final journal = File('${directory.path}/usage.json');
        await profile.writeAsString('proxies: []');
        final key = await X25519().newKeyPairFromSeed(
          List.generate(32, (i) => i + 10),
        );
        final publicKey = await key.extractPublicKey();
        final gateway = _UpstreamGateway(
          EncryptedGatewayServer(serverKeyPairs: {27: key}),
          legacyEnvelope: scenario.legacyEnvelope,
          omitStatus: scenario.omitStatus,
        );
        final http = await HttpService.create(
          'https://127.0.0.1',
          requireEncryptedGateway: true,
          directConnections: true,
          httpConfig: HttpConfig(
            encryptedGateway: EncryptedGatewayConfig(
              path: '/abcdefghijklmnopqrstuvwxyz012345',
              keyId: 27,
              serverPublicKey: base64Url
                  .encode(publicKey.bytes)
                  .replaceAll('=', ''),
            ),
          ),
        );
        http.dio.httpClientAdapter = gateway;
        final operations = <Map<String, dynamic>>[];
        final renewed = Completer<void>();
        final service = UpstreamUsageService(
          httpService: http,
          profileFile: (_) async => profile,
          journalFile: () async => journal,
          validateConfiguration: (content) async {
            expect(content, _configuration);
            return '';
          },
          invokeCore: (request) async {
            operations.add(request);
            if (request['operation'] == 'renew') renewed.complete();
            return {
              'metering_version': 1,
              'reason': '',
              'traffic': {
                '7': [10, 20],
              },
            };
          },
        );
        addTearDown(() async {
          await service.stop('closed');
          http.dio.close(force: true);
          await directory.delete(recursive: true);
        });

        if (scenario.omitStatus) {
          await expectLater(
            service.prepare('profile'),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('授权接口返回格式异常（open）'),
              ),
            ),
          );
          expect(await profile.readAsString(), 'proxies: []');
          expect(operations.where((r) => r['operation'] == 'begin'), isEmpty);
          expect(await journal.exists(), isFalse);
          return;
        }
        final configuration = (await service.fetchConfiguration())!;
        await ManagedSubscriptionProfile.install(file: profile,
          content: configuration['content'] as String,
          version: configuration['configuration_version'] as String,
          coreVersion: UpstreamUsageService.coreVersion, validate: (_) async => '');
        expect(await profile.readAsString(), contains('self-hosted'));
        expect(operations.where((request) => request['operation'] == 'begin'), isEmpty);
        await service.prepare('profile');
        expect(await profile.readAsString(), contains('upstream-7'));
        expect(
          operations.singleWhere((r) => r['operation'] == 'begin')['tags'],
          {'upstream-7': '7'},
        );
        expect(
          jsonDecode(await journal.readAsString())['session_id'],
          'session-a',
        );
        await service.checkpoint(reportNow: true);
        await renewed.future.timeout(const Duration(seconds: 5));
        expect(
          operations.singleWhere((r) => r['operation'] == 'renew')['confirmed'],
          {
            '7': [10, 20],
          },
        );
        await service.stop('closed');
        expect(gateway.actions, ['open', 'configuration', 'close', 'open', 'report', 'close']);
        expect(gateway.finalTraffic, {
          '7': [10, 20],
        });
        expect(await journal.exists(), isFalse);
      },
    );
  }
}

class _UpstreamGateway implements HttpClientAdapter {
  _UpstreamGateway(
    this.server, {
    required this.legacyEnvelope,
    required this.omitStatus,
  });
  final EncryptedGatewayServer server;
  final bool legacyEnvelope;
  final bool omitStatus;
  final actions = <String>[];
  Object? finalTraffic;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'POST');
    expect(options.uri.path, '/abcdefghijklmnopqrstuvwxyz012345');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk
        in requestStream ?? const Stream<Uint8List>.empty()) {
      bytes.add(chunk);
    }
    final request = await server.decryptRequest(bytes.takeBytes());
    final action = request.payload.path.split('/').last;
    actions.add(action);
    expect(
      request.payload.headers['authorization'],
      action == 'open' ? 'Bearer account-token' : 'Bearer restricted-token',
    );
    final data = <String, dynamic>{
      'allowed': true,
      'status': 'active',
      'server_time': 100,
      'lease_until': 400,
      'remaining': 1000,
      'period': '0:0',
      'deadline_reason': 'authorization_timeout',
      'configuration_version': 'a' * 64,
      'nodes': {'upstream-7': {'id': 7, 'name': 'HK', 'rate': 1}},
    };
    switch (action) {
      case 'open':
        final body = jsonDecode(utf8.decode(request.payload.body)) as Map;
        if (actions.length == 1 && !omitStatus) {
          expect(body['configuration_only'], isTrue);
        } else if (!omitStatus) {
          expect(body['configuration_version'], 'a' * 64);
          expect(body['configuration_only'], isNull);
        }
        data.addAll({
          'session_id': 'session-a',
          'session_token': 'restricted-token',
        });
      case 'configuration':
        data.addAll({
          'content': _configuration,
          'nodes': {
            'upstream-7': {'id': 7, 'name': 'HK', 'rate': 1},
          },
        });
      case 'report':
        data['confirmed'] = jsonDecode(
          utf8.decode(request.payload.body),
        )['traffic'];
      case 'close':
        finalTraffic = jsonDecode(utf8.decode(request.payload.body))['traffic'];
        data.addAll({'allowed': false, 'status': 'closed'});
      default:
        fail('Unexpected action $action');
    }
    if (omitStatus) data.remove('status');
    // Match ClientController's actual wire envelope, then exercise SDK normalization.
    final response = GatewayResponsePayload(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(
        jsonEncode({if (!legacyEnvelope) 'status': 'success', 'data': data}),
      ),
    );
    return ResponseBody.fromBytes(
      await server.encryptResponse(request.context, response),
      200,
      headers: const {
        'content-type': ['application/octet-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
