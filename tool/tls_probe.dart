import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/xboard/config/fetchers/remote_config_manager.dart';
import 'package:yaml/yaml.dart';

Future<void> main() async {
  const host = 'sub2.xn--zqs52kiwdf55am3ngt2a.xn--55qx5d';
  const originHost = 'sub.xn--zqs52kiwdf55am3ngt2a.xn--55qx5d';
  const gatewayPath = '/l3wSpSuI4uaNDq1_7Ox4MbRiVO4y-bAuNXIAbgujiTE';
  for (final allowBadCertificate in [false, true]) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    if (allowBadCertificate) {
      client.badCertificateCallback = (_, _, _) => true;
    }

    try {
      final request = await client.getUrl(Uri.https(host, '/'));
      final response = await request.close();
      await response.drain<void>();
      print(
        'allowBadCertificate=$allowBadCertificate '
        'status=${response.statusCode}',
      );
    } catch (error) {
      print(
        'allowBadCertificate=$allowBadCertificate '
        'errorType=${error.runtimeType} error=$error',
      );
    } finally {
      client.close(force: true);
    }
  }

  final postClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await postClient.postUrl(Uri.https(host, gatewayPath));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/octet-stream')
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.add(utf8.encode('probe'));
    final response = await request.close();
    await response.drain<void>();
    print('binaryPostStatus=${response.statusCode} bytes=${response.contentLength}');
  } catch (error) {
    print('binaryPostErrorType=${error.runtimeType} error=$error');
  } finally {
    postClient.close(force: true);
  }

  final yaml = loadYaml(
    await File('assets/config/xboard.config.yaml').readAsString(),
  ) as YamlMap;
  final xboard = yaml['xboard'] as YamlMap;
  final sources = (xboard['remote_config'] as YamlMap)['sources'] as YamlList;
  final gitee = sources.cast<YamlMap>().singleWhere(
    (source) => source['name'] == 'gitee',
  );
  final result = await GiteeConfigSource(
    giteeUrl: gitee['url'] as String,
    encryptionKeyBase64: gitee['encryption_key'] as String,
  ).fetchConfig();
  final panels = result.data?['panels'] as Map<String, dynamic>?;
  final providerPanels = panels?[xboard['provider']] as List<dynamic>?;
  final panel = providerPanels?.firstOrNull as Map<String, dynamic>?;
  final panelUri = Uri.parse(panel?['url'] as String? ?? '');
  print('remotePanelScheme=${panelUri.scheme}');
  print('remotePanelPort=${panelUri.hasPort ? panelUri.port : 443}');
  print('remotePanelIsCdn=${panelUri.host == host}');
  print('remotePanelIsOrigin=${panelUri.host == originHost}');
}