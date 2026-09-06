import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/xboard/features/subscription/services/encrypted_subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _subscription = '''proxies:
  - name: HY2
    type: hysteria2
    server: node.example.com
    port: 20000
    ports: 20000-20010
    hop-interval: 10
    password: test-password
    obfs: salamander
    obfs-password: test-obfs
    sni: node.example.com
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'login import and refresh send matching versions inside the gateway',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Sentinel',
        packageName: 'test.sentinel',
        version: '2.6.2',
        buildNumber: '1',
        buildSignature: '',
      );
      final key = await X25519().newKeyPairFromSeed(
        List.generate(32, (i) => i + 10),
      );
      final publicKey = await key.extractPublicKey();
      final server = EncryptedGatewayServer(serverKeyPairs: {27: key});
      final sdk = XBoardSDK.instance;
      await sdk.initialize(
        'https://client.example',
        panelType: 'xboard',
        useMemoryStorage: true,
        httpConfig: HttpConfig(
          userAgent: 'Sentinel/Test',
          encryptedGateway: EncryptedGatewayConfig(
            path: '/abcdefghijklmnopqrstuvwxyz012345',
            keyId: 27,
            serverPublicKey: base64Url
                .encode(publicKey.bytes)
                .replaceAll('=', ''),
          ),
        ),
      );
      addTearDown(sdk.dispose);
      final adapter = _SubscriptionGateway(server);
      sdk.httpService.dio.httpClientAdapter = adapter;
      await sdk.saveToken('login-token');

      final imported =
          await EncryptedSubscriptionService.getEncryptedSubscriptionFromLogin();
      expect(imported.success, isTrue, reason: imported.error);
      expect(imported.content, _subscription);
      final refreshed = await EncryptedSubscriptionService.getSubscriptionSmart(
        'sub-token',
      );
      expect(refreshed.success, isTrue, reason: refreshed.error);
      expect(refreshed.content, _subscription);
      expect(adapter.subscriptionRequests, 2);
    },
  );
}

class _SubscriptionGateway implements HttpClientAdapter {
  _SubscriptionGateway(this.server);
  final EncryptedGatewayServer server;
  int subscriptionRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'POST');
    expect(
      options.uri.toString(),
      'https://client.example/abcdefghijklmnopqrstuvwxyz012345',
    );
    final bytes = BytesBuilder(copy: false);
    await for (final chunk
        in requestStream ?? const Stream<Uint8List>.empty()) {
      bytes.add(chunk);
    }
    final request = await server.decryptRequest(bytes.takeBytes());
    final GatewayResponsePayload response;
    if (request.payload.path == '/api/v1/user/getSubscribe') {
      expect(request.payload.headers['authorization'], 'Bearer login-token');
      response = GatewayResponsePayload(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(
          '{"status":"success","data":{"token":"sub-token","subscribe_url":"https://client.example/sub?token=sub-token"}}',
        ),
      );
    } else {
      expect(request.payload.path, '/api/v1/client/subscribe');
      final query = {
        for (final pair in request.payload.query) pair.name: pair.value,
      };
      expect(query, {'token': 'sub-token', 'flag': 'flclash/2.6.2'});
      expect(request.payload.headers['user-agent'], 'FlClash/2.6.2');
      subscriptionRequests++;
      response = GatewayResponsePayload(
        statusCode: 200,
        headers: const {'content-type': 'text/yaml'},
        body: utf8.encode(_subscription),
      );
    }
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
