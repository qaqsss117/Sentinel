import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:path/path.dart' as path;

typedef UpdateDownloadProgress = void Function(double progress);

class UpdateInstaller {
  UpdateInstaller({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final CancelToken _cancelToken = CancelToken();

  void cancel() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('Update dialog closed');
    }
  }

  Future<void> downloadAndInstall({
    required String url,
    required String version,
    required UpdateDownloadProgress onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('In-app installation is only available on Android');
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('The APK download URL must use HTTPS');
    }

    final updateDirectory = Directory(
      path.join(await appPath.homeDirPath, 'updates'),
    );
    await updateDirectory.create(recursive: true);

    final safeVersion = version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final apkFile = File(
      path.join(updateDirectory.path, 'sentinel-$safeVersion.apk'),
    );
    final partialFile = File('${apkFile.path}.download');
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    try {
      await _dio.download(
        uri.toString(),
        partialFile.path,
        cancelToken: _cancelToken,
        deleteOnError: true,
        options: Options(
          followRedirects: true,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
      );

      if (!await _hasZipHeader(partialFile)) {
        throw const FormatException('The downloaded file is not a valid APK');
      }
      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      await partialFile.rename(apkFile.path);

      final opened = await app?.openFile(
            apkFile.path,
            mimeType: 'application/vnd.android.package-archive',
          ) ??
          false;
      if (!opened) {
        throw StateError('Unable to open the Android package installer');
      }
    } catch (_) {
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      rethrow;
    }
  }

  Future<bool> _hasZipHeader(File file) async {
    if (!await file.exists() || await file.length() < 4) {
      return false;
    }
    final bytes = await file.openRead(0, 4).fold<List<int>>(
          <int>[],
          (buffer, chunk) => buffer..addAll(chunk),
        );
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }
}