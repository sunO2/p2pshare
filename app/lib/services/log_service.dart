import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 日志服务 - 将日志写入文件
class LogService {
  static LogService? _instance;
  static LogService get instance => _instance ??= LogService._();

  LogService._();

  late Logger _logger;
  late File _logFile;
  late IOSink _logSink;
  late _FileLogOutput _logOutput;  // 保存 output 引用，用于更新 sink
  final _logsController = StreamController<String>.broadcast();
  bool _initialized = false;

  /// 日志流
  Stream<String> get logStream => _logsController.stream;

  /// 获取日志文件
  File get logFile => _logFile;

  /// 初始化日志服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      // 获取应用文档目录
      final appDocDir = await getApplicationDocumentsDirectory();
      final logsDir = Directory(p.join(appDocDir.path, 'logs'));

      // 创建日志目录
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // 创建日志文件（按日期命名）
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _logFile = File(p.join(logsDir.path, 'localp2p_$dateStr.log'));

      // 打开文件用于追加
      _logSink = _logFile.openWrite(mode: FileMode.append);

      // 创建 LogOutput
      _logOutput = _FileLogOutput(
        sink: _logSink,
        onLog: (log) => _logsController.add(log),
      );

      // 初始化 Logger
      _logger = Logger(
        level: Level.trace,
        output: _logOutput,
        printer: _PrettyFilePrinter(),
        filter: ProductionFilter(),
      );

      _initialized = true;

      // 写入启动日志
      _logger.i('════════════════════════════════════════════════════════════');
      _logger.i('应用启动 - ${DateTime.now()}');
      _logger.i('日志文件: ${_logFile.path}');
      _logger.i('════════════════════════════════════════════════════════════');
    } catch (e, stackTrace) {
      // 如果日志初始化失败，使用控制台输出
      debugPrint('日志服务初始化失败: $e');
      debugPrint('Stack trace: $stackTrace');
      _logger = Logger(
        output: ConsoleOutput(),
        printer: PrettyPrinter(
          methodCount: 8,
          errorMethodCount: 8,
          lineLength: 120,
          colors: true,
          printEmojis: true,
          printTime: true,
        ),
      );
      _initialized = true;
    }
  }

  /// 获取 Logger 实例
  Logger get logger => _logger;

  /// 写入日志
  void log(
    Level level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) {
      debugPrint('[NOT INITIALIZED] $message');
      return;
    }

    _logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// Trace 级别日志
  void t(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.trace, message, error: error, stackTrace: stackTrace);
  }

  /// Debug 级别日志
  void d(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.debug, message, error: error, stackTrace: stackTrace);
  }

  /// Info 级别日志
  void i(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.info, message, error: error, stackTrace: stackTrace);
  }

  /// Warning 级别日志
  void w(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.warning, message, error: error, stackTrace: stackTrace);
  }

  /// Error 级别日志
  void e(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.error, message, error: error, stackTrace: stackTrace);
  }

  /// Fatal 级别日志
  void f(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.fatal, message, error: error, stackTrace: stackTrace);
  }

  /// 获取所有日志内容
  Future<String> getAllLogs() async {
    try {
      if (await _logFile.exists()) {
        return await _logFile.readAsString();
      }
      return '日志文件不存在';
    } catch (e) {
      return '读取日志失败: $e';
    }
  }

  /// 获取最近的日志
  Future<String> getRecentLogs({int lines = 500}) async {
    try {
      if (await _logFile.exists()) {
        final contents = await _logFile.readAsString();
        final allLines = contents.split('\n');
        final start = allLines.length > lines ? allLines.length - lines : 0;
        return allLines.skip(start).join('\n');
      }
      return '日志文件不存在';
    } catch (e) {
      return '读取日志失败: $e';
    }
  }

  /// 清空日志文件
  Future<void> clearLogs() async {
    try {
      if (await _logFile.exists()) {
        // ⚠️ 关键修复：先关闭旧的 sink，避免文件句柄冲突
        await _logSink.flush();
        await _logSink.close();

        // 清空文件
        await _logFile.writeAsString('');

        // 重新打开 sink（append 模式）
        _logSink = _logFile.openWrite(mode: FileMode.append);

        // 更新 _FileLogOutput 使用的 sink
        _logOutput.sink = _logSink;

        _logger.i('日志已清空 - ${DateTime.now()}');
      }
    } catch (e) {
      _logger.e('清空日志失败: $e');
    }
  }

  /// 获取日志文件大小
  Future<int> getLogFileSize() async {
    try {
      if (await _logFile.exists()) {
        return await _logFile.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// 获取所有日志文件
  Future<List<File>> getAllLogFiles() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final logsDir = Directory(p.join(appDocDir.path, 'logs'));

      if (!await logsDir.exists()) {
        return [];
      }

      final files = await logsDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path)); // 按时间倒序
      return files;
    } catch (e) {
      return [];
    }
  }

  /// 关闭日志服务
  Future<void> close() async {
    if (_initialized) {
      _logger.i('应用退出 - ${DateTime.now()}');
      _logger.i('════════════════════════════════════════════════════════════');
      await _logSink.flush();
      await _logSink.close();
      await _logsController.close();
      _initialized = false;
    }
  }

  void debugPrint(String message) {
    print(message);
  }
}

/// 自定义文件日志输出
class _FileLogOutput extends LogOutput {
  IOSink sink;
  final void Function(String) onLog;

  _FileLogOutput({required this.sink, required this.onLog});

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      sink.writeln(line);
      onLog(line);
    }
  }
}

/// 自定义文件日志格式化器
class _PrettyFilePrinter extends LogPrinter {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  @override
  List<String> log(LogEvent event) {
    final time = _dateFormat.format(DateTime.now());
    final level = _levelToString(event.level);
    final message = _formatMessage(event.message);

    final buffer = StringBuffer();
    buffer.write('[$time] [$level] $message');

    if (event.error != null) {
      buffer.write('\n  Error: ${event.error}');
    }

    if (event.stackTrace != null) {
      buffer.write('\n  StackTrace:\n${event.stackTrace}');
    }

    return [buffer.toString()];
  }

  String _levelToString(Level level) {
    switch (level) {
      case Level.trace:
        return 'TRACE';
      case Level.debug:
        return 'DEBUG ';
      case Level.info:
        return 'INFO  ';
      case Level.warning:
        return 'WARN  ';
      case Level.error:
        return 'ERROR ';
      case Level.fatal:
        return 'FATAL ';
      default:
        return 'UNKNOWN';
    }
  }

  String _formatMessage(dynamic message) {
    if (message is Map || message is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(message);
      } catch (e) {
        return message.toString();
      }
    }
    return message.toString();
  }
}

/// P2P 日志助手 - 专门记录 P2P 交互
class P2PLogHelper {
  final LogService _log = LogService.instance;

  // 基础日志方法
  void t(String message, [Object? error, StackTrace? stackTrace]) {
    _log.t(message, error, stackTrace);
  }

  void d(String message, [Object? error, StackTrace? stackTrace]) {
    _log.d(message, error, stackTrace);
  }

  void i(String message, [Object? error, StackTrace? stackTrace]) {
    _log.i(message, error, stackTrace);
  }

  void w(String message, [Object? error, StackTrace? stackTrace]) {
    _log.w(message, error, stackTrace);
  }

  void e(String message, [Object? error, StackTrace? stackTrace]) {
    _log.e(message, error, stackTrace);
  }

  /// 记录 Rust 调用
  void rustCall(String function, {Map<String, dynamic>? params}) {
    final paramsStr = params != null ? ' | params: $params' : '';
    _log.d('🔴 Rust Call: $function$paramsStr');
  }

  /// 记录 Rust 返回
  void rustReturn(String function, {dynamic result}) {
    final resultStr = result != null ? ' | result: $result' : '';
    _log.d('🟢 Rust Return: $function$resultStr');
  }

  /// 记录 Rust 错误
  void rustError(String function, Object error, [StackTrace? stackTrace]) {
    _log.e('🔴 Rust Error: $function | error: $error', error, stackTrace);
  }

  /// 记录事件
  void event(String eventType, {Map<String, dynamic>? data}) {
    final dataStr = data != null ? ' | $data' : '';
    _log.i('📡 Event: $eventType$dataStr');
  }

  /// 记录节点操作
  void node(String action, String peerId, {Map<String, dynamic>? details}) {
    final detailsStr = details != null ? ' | $details' : '';
    _log.i('📱 Node $action: $peerId$detailsStr');
  }

  /// 记录消息
  void message(String direction, String peerId, String content) {
    final preview = content.length > 50
        ? '${content.substring(0, 50)}...'
        : content;
    _log.d('💬 Message $direction: $peerId | "$preview"');
  }

  /// 记录状态变化
  void stateChange(String from, String to) {
    _log.i('🔄 State Change: $from → $to');
  }

  /// 记录性能数据
  void performance(String operation, Duration duration) {
    _log.d('⚡ Performance: $operation took ${duration.inMilliseconds}ms');
  }
}
