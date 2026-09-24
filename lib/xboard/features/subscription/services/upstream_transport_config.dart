import 'dart:convert';

import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';

/// Non-account settings passed only over the application's private isolate IPC.
/// The service still creates its own encrypted, direct HTTP client, with no
/// account-token interceptor that could overwrite a restricted session token.
class UpstreamTransportConfig {
  UpstreamTransportConfig(this.baseUrl, this.httpConfig) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('授权服务地址无效');
    }
    if (httpConfig.encryptedGateway == null ||
        httpConfig.ignoreCertificateHostname ||
        (httpConfig.enableCertificatePinning &&
            (httpConfig.certificatePath?.isEmpty ?? true))) {
      throw StateError('授权服务安全配置无效');
    }
  }

  final String baseUrl;
  final HttpConfig httpConfig;

  factory UpstreamTransportConfig.fromService(HttpService service) =>
      UpstreamTransportConfig(service.baseUrl, service.httpConfig);

  factory UpstreamTransportConfig.fromJson(Map<String, dynamic> value) {
    final config = value['http_config'] as Map;
    final gateway = config['encrypted_gateway'] as Map;
    return UpstreamTransportConfig(
      value['base_url'] as String,
      HttpConfig(
        encryptedGateway: EncryptedGatewayConfig(
          path: gateway['path'] as String,
          keyId: gateway['key_id'] as int,
          serverPublicKey: gateway['server_public_key'] as String,
          previousKeyId: gateway['previous_key_id'] as int?,
          previousServerPublicKey:
              gateway['previous_server_public_key'] as String?,
          allowedClockSkew: Duration(
            microseconds: gateway['clock_skew_us'] as int,
          ),
          maxEnvelopeSize: gateway['max_envelope_size'] as int,
        ),
        userAgent: config['user_agent'] as String?,
        obfuscationPrefix: config['obfuscation_prefix'] as String?,
        enableAutoDeobfuscation: config['auto_deobfuscation'] as bool,
        certificatePath: config['certificate_path'] as String?,
        enableCertificatePinning: config['certificate_pinning'] as bool,
        // No proxy or hostname-validation override is accepted through IPC.
        connectTimeoutSeconds: config['connect_timeout'] as int,
        receiveTimeoutSeconds: config['receive_timeout'] as int,
        sendTimeoutSeconds: config['send_timeout'] as int,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final gateway = httpConfig.encryptedGateway!;
    return {
      'base_url': baseUrl,
      'http_config': {
        'encrypted_gateway': {
          'path': gateway.path,
          'key_id': gateway.keyId,
          'server_public_key': gateway.serverPublicKey,
          'previous_key_id': gateway.previousKeyId,
          'previous_server_public_key': gateway.previousServerPublicKey,
          'clock_skew_us': gateway.allowedClockSkew.inMicroseconds,
          'max_envelope_size': gateway.maxEnvelopeSize,
        },
        'user_agent': httpConfig.userAgent,
        'obfuscation_prefix': httpConfig.obfuscationPrefix,
        'auto_deobfuscation': httpConfig.enableAutoDeobfuscation,
        'certificate_path': httpConfig.certificatePath,
        'certificate_pinning': httpConfig.enableCertificatePinning,
        'connect_timeout': httpConfig.connectTimeoutSeconds,
        'receive_timeout': httpConfig.receiveTimeoutSeconds,
        'send_timeout': httpConfig.sendTimeoutSeconds,
      },
    };
  }

  bool matches(UpstreamTransportConfig? other) =>
      other != null && jsonEncode(toJson()) == jsonEncode(other.toJson());
}
