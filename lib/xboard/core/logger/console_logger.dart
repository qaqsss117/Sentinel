/// 控制台日志实现
///
/// 使用 Dart 原生 print 输出日志，不依赖任何外部包
library;

import 'dart:io';

import 'logger_interface.dart';

/// 控制台日志实现
class ConsoleLogger implements LoggerInterface {
  static const String _prefix = '[XBoard]';

  /// 同时落盘的日志文件（相对应用数据目录）。GUI/托盘应用没有 console，
  /// stdout 会丢失 —— 落盘是唯一可靠的排查通道。
  static const String logFileName = 'sentinel_client.log';

  /// 单文件上限，超过则截断重写（避免无限增长）。
  static const int _maxFileBytes = 2 * 1024 * 1024;

  @override
  LogLevel minLevel;

  /// 是否启用时间戳
  final bool enableTimestamp;

  /// 是否启用颜色（仅在支持 ANSI 的终端中有效）
  final bool enableColor;

  /// 是否同时写入日志文件
  final bool enableFile;

  ConsoleLogger({
    this.minLevel = LogLevel.info,
    this.enableTimestamp = true,
    this.enableColor = false,
    this.enableFile = true,
  });

  /// ANSI 颜色代码
  static const String _resetColor = '\x1B[0m';
  static const String _debugColor = '\x1B[36m'; // Cyan
  static const String _infoColor = '\x1B[32m'; // Green
  static const String _warningColor = '\x1B[33m'; // Yellow
  static const String _errorColor = '\x1B[31m'; // Red

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    if (minLevel.index <= LogLevel.debug.index) {
      _log('DEBUG', message, error, stackTrace, _debugColor);
    }
  }

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    if (minLevel.index <= LogLevel.info.index) {
      _log('INFO', message, error, stackTrace, _infoColor);
    }
  }

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    if (minLevel.index <= LogLevel.warning.index) {
      _log('WARN', message, error, stackTrace, _warningColor);
    }
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (minLevel.index <= LogLevel.error.index) {
      _log('ERROR', message, error, stackTrace, _errorColor);
    }
  }

  void _log(
    String level,
    String message,
    Object? error,
    StackTrace? stackTrace,
    String colorCode,
  ) {
    final timestamp = enableTimestamp ? _getTimestamp() : '';
    final prefix = enableColor ? '$colorCode$_prefix' : _prefix;
    final levelStr = enableColor ? '[$level]' : '[$level]';
    final resetColor = enableColor ? _resetColor : '';

    // 构建日志消息
    final buffer = StringBuffer();
    buffer.write('$prefix$timestamp$levelStr $message$resetColor');

    // 输出主消息
    // ignore: avoid_print
    print(buffer.toString());
    if (enableFile) {
      _appendToFile('$timestamp[$level] $message');
    }

    // 输出错误信息（保持格式一致）
    if (error != null) {
      // ignore: avoid_print
      print('$prefix$timestamp$levelStr Error: $error$resetColor');
      if (enableFile) {
        _appendToFile('$timestamp[$level] Error: $error');
      }
    }

    // 输出堆栈跟踪（保持格式一致）
    if (stackTrace != null) {
      // ignore: avoid_print
      print('$prefix$timestamp$levelStr StackTrace:\n$stackTrace$resetColor');
      if (enableFile) {
        _appendToFile('$timestamp[$level] StackTrace: $stackTrace');
      }
    }
  }

  /// 追加落盘（任何失败都静默忽略 —— 日志绝不能影响主流程）。
  void _appendToFile(String line) {
    try {
      final file = File('${_logDir.path}${Platform.pathSeparator}$logFileName');
      if (file.existsSync()) {
        final length = file.lengthSync();
        if (length > _maxFileBytes) {
          // 保留尾部一半，避免完全丢失上下文
          final bytes = file.readAsBytesSync();
          final keep = bytes.sublist(bytes.length - _maxFileBytes ~/ 2);
          file.writeAsBytesSync(keep, flush: true);
        }
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // 忽略：日志失败不能抛
    }
  }

  /// 日志目录：应用支持目录（Windows 下由 path_provider 落到 %APPDATA%\<id>）。
  /// 这里用环境变量推导，避免在纯 Dart 层引入 Flutter 依赖。
  static Directory get _logDir {
    final home = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return Directory(home);
  }

  String _getTimestamp() {
    final now = DateTime.now();
    return '[${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}]';
  }
}

