import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class ManagedSubscriptionProfile {
  static File _stamp(File file) => File('${file.path}.upstream.json');

  static Future<String?> version(File file, String coreVersion) async {
    final stamp = _stamp(file);
    if (!await stamp.exists()) return null;
    try {
      final saved = jsonDecode(await stamp.readAsString()) as Map;
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (saved['core_version'] != coreVersion ||
          saved['sha256'] != digest ||
          saved['version'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(saved['version'] as String)) {
        throw const FormatException();
      }
      return saved['version'] as String;
    } catch (_) {
      throw StateError('订阅配置已变化，请刷新订阅后再连接');
    }
  }

  static Future<void> install({
    required File file,
    required String content,
    required String version,
    required String coreVersion,
    required FutureOr<String> Function(String) validate,
  }) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(version)) {
      throw StateError('面板未返回配置版本，请更新上游订阅插件');
    }
    if ((await validate(content)).isNotEmpty) {
      throw StateError('节点配置校验失败');
    }
    await file.parent.create(recursive: true);
    final stamp = _stamp(file);
    final oldContent = await file.exists() ? await file.readAsBytes() : null;
    final oldStamp = await stamp.exists() ? await stamp.readAsBytes() : null;
    try {
      await _replace(file, utf8.encode(content));
      await _replace(
        stamp,
        utf8.encode(
          jsonEncode({
            'version': version,
            'core_version': coreVersion,
            'sha256': sha256.convert(utf8.encode(content)).toString(),
          }),
        ),
      );
    } catch (_) {
      if (oldContent != null) {
        await _replace(file, oldContent);
      } else if (await file.exists()) {
        await file.delete();
      }
      if (oldStamp != null) {
        await _replace(stamp, oldStamp);
      } else if (await stamp.exists()) {
        await stamp.delete();
      }
      rethrow;
    }
  }

  static Future<void> _replace(File file, List<int> bytes) async {
    final staged = File('${file.path}.tmp');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }
}
