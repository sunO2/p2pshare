import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../services/log_service.dart';
import '../../../widgets/unified_app_bar.dart';

/// 日志查看器页面控制器
class LogsViewerController extends GetxController {
  /// 最大日志行数限制（防止内存溢出）
  static const maxLogLines = 1000;

  /// UI 更新节流时间（毫秒）
  static const uiUpdateThrottleMs = 200;

  /// 选中的日期
  final selectedDate = ''.obs;

  /// 可用日期列表
  final availableDates = <String>[].obs;

  /// 日志行列表（普通 List，不使用 RxList 避免频繁触发更新）
  final logLines = <LogLine>[];

  /// UI 更新计时器（用于节流）
  Timer? _uiUpdateTimer;
  bool _pendingUpdate = false;

  /// 自动滚动
  final autoScroll = true.obs;

  /// 显示 Flutter 日志
  final showFlutterLogs = true.obs;

  /// 显示 Rust 日志（默认关闭，仅显示 Flutter 日志提升性能）
  final showRustLogs = false.obs;

  /// 是否正在实时监听
  final isRealtimeWatching = false.obs;

  /// 滚动控制器
  late final ScrollController scrollController;

  /// 实时日志订阅
  StreamSubscription<LogLine>? realtimeSubscription;

  final LogService _log = Get.find<LogService>();

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController();
    initDates();
  }

  @override
  void onReady() {
    super.onReady();
    // 页面准备完成后触发一次更新，确保 UI 正确显示
    _scheduleUpdate();
  }

  @override
  void onClose() {
    _uiUpdateTimer?.cancel();
    stopRealtimeWatch();
    scrollController.dispose();
    super.onClose();
  }

  /// 触发 UI 更新（带节流）
  void _scheduleUpdate() {
    if (_uiUpdateTimer?.isActive ?? false) {
      _pendingUpdate = true;
      return;
    }

    update(['logs']); // 只更新日志列表

    _uiUpdateTimer = Timer(Duration(milliseconds: uiUpdateThrottleMs), () {
      if (_pendingUpdate) {
        _pendingUpdate = false;
        update(['logs']);
      }
    });
  }

  /// 初始化日期
  Future<void> initDates() async {
    try {
      final dates = await _log.getAvailableDates();
      availableDates.assignAll(dates);
      if (dates.isNotEmpty) {
        selectedDate.value = dates.first;
        await loadInitialLogs();
        startRealtimeWatch();
      }
    } catch (e) {
      _log.e('Failed to load dates: $e', e);
    }
  }

  /// 加载初始日志
  Future<void> loadInitialLogs() async {
    if (selectedDate.value.isEmpty) return;

    try {
      final lines = <LogLine>[];

      // 加载 Flutter 日志
      if (showFlutterLogs.value) {
        final flutterLogs = await _log.getLogsByDate(selectedDate.value, LogType.flutter);
        lines.addAll(flutterLogs.map((log) => LogLine(
              content: log,
              type: LogType.flutter,
              timestamp: DateTime.now(),
            )).toList());
      }

      // 加载 Rust 日志（如果启用）
      if (showRustLogs.value) {
        final rustLogs = await _log.getLogsByDate(selectedDate.value, LogType.rust);
        lines.addAll(rustLogs.map((log) => LogLine(
              content: log,
              type: LogType.rust,
              timestamp: DateTime.now(),
            )).toList());
      }

      // 按时间戳倒序排序（新→旧），这样 reverse 模式下视觉上才是旧→新
      lines.sort((a, b) => _parseLogTimestamp(b.content).compareTo(_parseLogTimestamp(a.content)));

      // 限制日志行数（保留最新的）
      if (lines.length > maxLogLines) {
        lines.removeRange(maxLogLines, lines.length);
      }

      logLines.clear();
      logLines.addAll(lines);

      _scheduleUpdate();

      // reverse 模式下，新日志自动显示在底部，无需手动滚动
    } catch (e) {
      _log.e('Failed to load logs: $e', e);
    }
  }

  /// 从日志内容解析时间戳
  DateTime _parseLogTimestamp(String logContent) {
    try {
      // 日志格式: [2026-02-04 12:34:56.789] ...
      final timeMatch = RegExp(r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]').firstMatch(logContent);
      if (timeMatch != null) {
        return DateTime.parse(timeMatch.group(1)!.replaceAll(' ', 'T'));
      }
    } catch (_) {}
    return DateTime.now();
  }

  /// 切换日期
  Future<void> changeDate(String? newDate) async {
    if (newDate == null || newDate == selectedDate.value) return;

    final wasWatching = isRealtimeWatching.value;
    if (wasWatching) {
      stopRealtimeWatch();
    }

    selectedDate.value = newDate;
    logLines.clear();
    _scheduleUpdate();
    await loadInitialLogs();

    if (wasWatching) {
      startRealtimeWatch();
    }
  }

  /// 刷新日志
  Future<void> refreshLogs() async {
    final wasWatching = isRealtimeWatching.value;
    if (wasWatching) {
      stopRealtimeWatch();
    }

    logLines.clear();
    _scheduleUpdate();
    await loadInitialLogs();

    if (wasWatching) {
      startRealtimeWatch();
    }
  }

  /// 开始实时监听
  void startRealtimeWatch() {
    if (isRealtimeWatching.value) return;

    isRealtimeWatching.value = true;

    // 根据当前设置决定监听哪些日志
    final types = <LogType>[];
    if (showFlutterLogs.value) types.add(LogType.flutter);
    if (showRustLogs.value) types.add(LogType.rust);

    _log.startRealtimeWatch(selectedDate.value, types: types);

    realtimeSubscription = _log.realtimeLogStream.listen((logLine) {
      // 过滤
      if (logLine.type == LogType.flutter && !showFlutterLogs.value) return;
      if (logLine.type == LogType.rust && !showRustLogs.value) return;

      // reverse 模式下，新日志插入到开头（索引 0），视觉上会显示在底部
      logLines.insert(0, logLine);

      // 限制日志行数（移除最后的）
      if (logLines.length > maxLogLines) {
        logLines.removeLast();
      }

      // 触发 UI 更新（带节流）
      _scheduleUpdate();

      // 使用 reverse 后新日志自动在底部可见，无需手动滚动
    }, onError: (error) {
      _log.e('Realtime log stream error: $error', error);
    });
  }

  /// 停止实时监听
  void stopRealtimeWatch() {
    isRealtimeWatching.value = false;
    realtimeSubscription?.cancel();
    realtimeSubscription = null;
    _log.stopRealtimeWatch();
  }

  /// 切换实时监听
  void toggleRealtimeWatch() {
    if (isRealtimeWatching.value) {
      stopRealtimeWatch();
    } else {
      startRealtimeWatch();
    }
  }

  /// 切换 Flutter 日志显示
  Future<void> toggleFlutterLogs() async {
    final wasWatching = isRealtimeWatching.value;

    if (wasWatching) {
      stopRealtimeWatch();
    }

    showFlutterLogs.value = !showFlutterLogs.value;
    logLines.clear();
    _scheduleUpdate();
    await loadInitialLogs();

    if (wasWatching) {
      startRealtimeWatch();
    }
  }

  /// 切换 Rust 日志显示
  Future<void> toggleRustLogs() async {
    final wasWatching = isRealtimeWatching.value;

    if (wasWatching) {
      stopRealtimeWatch();
    }

    showRustLogs.value = !showRustLogs.value;
    logLines.clear();
    _scheduleUpdate();
    await loadInitialLogs();

    if (wasWatching) {
      startRealtimeWatch();
    }
  }

  /// 复制所有日志到剪贴板
  Future<void> copyAllLogs() async {
    if (logLines.isEmpty) {
      Get.snackbar('提示', '暂无日志可复制');
      return;
    }

    final allLogs = logLines.map((line) => line.content).join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));
    Get.snackbar('提示', '已复制 ${logLines.length} 条日志');
  }
}

/// 日志查看器视图
class LogsViewerView extends GetView<LogsViewerController> {
  const LogsViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          _buildControlBar(context),
          Expanded(child: _buildLogList(context)),
        ],
      ),
    );
  }

  /// 构建导航栏
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Obx(() {
        final dateStr = controller.selectedDate.value;

        return UnifiedAppBar(
          title: '日志查看',
          subtitleWidget: dateStr.isEmpty ? null : Text(dateStr),
          actions: [
            // 复制按钮
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: controller.copyAllLogs,
              tooltip: '复制所有日志',
            ),
            // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: controller.refreshLogs,
            ),
          ],
        );
      }),
    );
  }

  /// 构建控制栏
  Widget _buildControlBar(BuildContext context) {
    return Obx(() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF8F8F6),
            border: Border(bottom: BorderSide(color: Color(0xFFCCCCCC))),
          ),
          child: Row(
            children: [
              // 日期选择
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: controller.selectedDate.value.isEmpty
                      ? null
                      : controller.selectedDate.value,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: controller.availableDates.map((date) {
                    return DropdownMenuItem(
                      value: date,
                      child: Text(date),
                    );
                  }).toList(),
                  onChanged: controller.changeDate,
                ),
              ),
              const SizedBox(width: 16),

              // 实时监听开关
              _buildToggle(
                '实时',
                controller.isRealtimeWatching.value,
                controller.toggleRealtimeWatch,
                color: const Color(0xFF3D8A5A),
              ),
              const SizedBox(width: 12),

              // Flutter 日志开关
              _buildToggle(
                'Flutter',
                controller.showFlutterLogs.value,
                controller.toggleFlutterLogs,
                color: Colors.blue,
              ),
              const SizedBox(width: 12),

              // Rust 日志开关
              _buildToggle(
                'Rust',
                controller.showRustLogs.value,
                controller.toggleRustLogs,
                color: Colors.orange,
              ),
            ],
          ),
        ));
  }

  /// 构建开关
  Widget _buildToggle(
    String label,
    bool value,
    VoidCallback onTap, {
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? (color ?? const Color(0xFF3D8A5A)).withOpacity(0.1)
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? (color ?? const Color(0xFF3D8A5A)).withOpacity(0.5)
                : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: value
                    ? (color ?? const Color(0xFF3D8A5A))
                    : Colors.grey[600],
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建日志列表
  Widget _buildLogList(BuildContext context) {
    return GetBuilder<LogsViewerController>(
      id: 'logs',
      builder: (controller) {
        // 过滤逻辑已在控制器中处理，这里直接显示所有日志
        if (controller.logLines.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '暂无日志',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: controller.scrollController,
          padding: const EdgeInsets.all(8),
          reverse: true, // 反转列表，新日志在底部
          itemCount: controller.logLines.length,
          itemBuilder: (context, index) {
            final logLine = controller.logLines[index];
            return _buildLogItemWidget(logLine);
          },
        );
      },
    );
  }

  /// 构建单个日志项 Widget（极简样式）
  Widget _buildLogItemWidget(LogLine logLine) {
    return SelectableText(
      logLine.content,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.4,
      ),
    );
  }
}
