import 'dart:io';

import 'package:fl_clash/xboard/config/fetchers/remote_config_manager.dart';
import 'package:yaml/yaml.dart';

Future<void> main() async {
  final yaml = loadYaml(
    await File('assets/config/xboard.config.yaml').readAsString(),
  ) as YamlMap;
  final xboard = yaml['xboard'] as YamlMap;
  final remoteConfig = xboard['remote_config'] as YamlMap;
  final sources = remoteConfig['sources'] as YamlList;
  final gitee = sources.cast<YamlMap>().singleWhere(
    (source) => source['name'] == 'gitee',
  );

  final stopwatch = Stopwatch()..start();
  final result = await GiteeConfigSource(
    giteeUrl: gitee['url'] as String,
    encryptionKeyBase64: gitee['encryption_key'] as String,
  ).fetchConfig();
  stopwatch.stop();

  final panels = result.data?['panels'];
  final providerPanels = panels is Map ? panels[xboard['provider']] : null;
  print('success=${result.isSuccess}');
  print('elapsedMs=${stopwatch.elapsedMilliseconds}');
  print('error=${result.error ?? ''}');
  print('topLevelKeys=${result.data?.keys.join(',') ?? ''}');
  print('providerPanelCount=${providerPanels is List ? providerPanels.length : 0}');

  if (!result.isSuccess || providerPanels is! List || providerPanels.isEmpty) {
    exitCode = 1;
  }
}