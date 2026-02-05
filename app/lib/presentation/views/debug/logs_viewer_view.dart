import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../services/log_service.dart';
import '../../../widgets/unified_app_bar.dart';

/// 日志查看器页面控制器（优化版）
class LogsViewerController extends GetxController {
  /// 最大日志行数限制（防止内存溢出）
  static const maxLogLines = 500;

  /// UI 更新节流时间（毫秒）
  static const uiUpdateThrottleMs = 300;

  /// 选中的日期
  final selectedDate = ''.obs;

  /// 可用日期列表
  final availableDates = <String>[].obs;

  /// 日志行列表（普通 List，不使用 RxList 避免频繁触发更新）
  final logLines = <LogLine>[];

  /// UI 更新计时器（用于节流）
  Timer? _uiUpdateTimer;
  bool _pendingUpdate = false;

  /// 显示 Flutter 日志
  final showFlutterLogs = true.obs;

  /// 显示 Rust 日志（默认关闭）
  final showRustLogs = false.obs;

  /// 是否正在实时监听
  final isRealtimeWatching = true.obs;

  /// 滚动控制器
  late final ScrollController scrollController;

  /// 实时日志订阅
  StreamSubscription<LogLine>? realtimeSubscription;

  /// 🔥 缓存：已加载的原始日志（按类型分组）
  final Map<LogType, List<String>> _cachedLogs = {
    LogType.flutter: [],
    LogType.rust: [],
  };

  /// 🔥 是否已加载过历史日志
  final Set<LogType> _loadedTypes = {};

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
    // 🔥 启动实时监听，不加载历史日志
    startRealtimeWatch();
    // 触发一次 UI 更新
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

    update(['logs']);

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
      }
    } catch (e) {
      _log.e('Failed to load dates: $e', e);
    }
  }

  /// 🔥 从缓存重建显示的日志列表（不读取文件）
  void _rebuildDisplayLogs() {
    logLines.clear();

    // 从缓存中按类型过滤
    final allLogs = <LogLine>[];

    if (showFlutterLogs.value) {
      for (final log in _cachedLogs[LogType.flutter]!) {
        allLogs.add(LogLine(
          content: log,
          type: LogType.flutter,
          timestamp: _parseLogTimestamp(log),
        ));
      }
    }

    if (showRustLogs.value) {
      for (final log in _cachedLogs[LogType.rust]!) {
        allLogs.add(LogLine(
          content: log,
          type: LogType.rust,
          timestamp: _parseLogTimestamp(log),
        ));
      }
    }

    // 按时间戳排序（新→旧）
    allLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 限制行数
    if (allLogs.length > maxLogLines) {
      allLogs.removeRange(maxLogLines, allLogs.length);
    }

    logLines.addAll(allLogs);
    _scheduleUpdate();
  }

  /// 从日志内容解析时间戳
  DateTime _parseLogTimestamp(String logContent) {
    try {
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

    // 清空缓存
    _cachedLogs[LogType.flutter] = [];
    _cachedLogs[LogType.rust] = [];
    _loadedTypes.clear();

    selectedDate.value = newDate;
    logLines.clear();
    _scheduleUpdate();
  }

  /// 🔥 加载历史日志（只加载未加载过的类型）
  Future<void> loadHistoryLogs() async {
    if (selectedDate.value.isEmpty) return;

    final typesToLoad = <LogType>[];
    if (showFlutterLogs.value && !_loadedTypes.contains(LogType.flutter)) {
      typesToLoad.add(LogType.flutter);
    }
    if (showRustLogs.value && !_loadedTypes.contains(LogType.rust)) {
      typesToLoad.add(LogType.rust);
    }

    if (typesToLoad.isEmpty) {
      // 已全部加载，只需重建显示
      _rebuildDisplayLogs();
      return;
    }

    // 🔥 异步加载，不阻塞 UI
    for (final type in typesToLoad) {
      try {
        final logs = await _log.getLogsByDate(selectedDate.value, type);
        _cachedLogs[type] = logs;
        _loadedTypes.add(type);
      } catch (e) {
        _log.e('Failed to load logs for $type: $e', e);
      }
    }

    // 加载完成后重建显示
    _rebuildDisplayLogs();
  }

  /// 🔥 刷新日志（清空缓存并重新加载）
  Future<void> refreshLogs() async {
    // 清空缓存
    _cachedLogs[LogType.flutter] = [];
    _cachedLogs[LogType.rust] = [];
    _loadedTypes.clear();

    logLines.clear();
    _scheduleUpdate();

    await loadHistoryLogs();
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

    realtimeSubscription = _log.realtimeLogStream.listen(
      (logLine) {
        // 🔥 实时日志也加入缓存
        _cachedLogs[logLine.type]!.insert(0, logLine.content);

        // 限制缓存大小
        if (_cachedLogs[logLine.type]!.length > maxLogLines * 2) {
          _cachedLogs[logLine.type]!.removeLast();
        }

        // 过滤显示
        if (logLine.type == LogType.flutter && !showFlutterLogs.value) return;
        if (logLine.type == LogType.rust && !showRustLogs.value) return;

        logLines.insert(0, logLine);

        // 限制显示行数
        if (logLines.length > maxLogLines) {
          logLines.removeLast();
        }

        _scheduleUpdate();
      },
      onError: (error) {
        _log.e('Realtime log stream error: $error', error);
      },
    );
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

  /// 🔥 切换 Flutter 日志显示（只重建显示，不重新读取文件）
  Future<void> toggleFlutterLogs() async {
    showFlutterLogs.value = !showFlutterLogs.value;

    // 重建显示列表
    _rebuildDisplayLogs();

    // 重启实时监听以更新监听的日志类型
    if (isRealtimeWatching.value) {
      stopRealtimeWatch();
      startRealtimeWatch();
    }
  }

  /// 🔥 切换 Rust 日志显示（只重建显示，不重新读取文件）
  Future<void> toggleRustLogs() async {
    showRustLogs.value = !showRustLogs.value;

    // 重建显示列表
    _rebuildDisplayLogs();

    // 重启实时监听以更新监听的日志类型
    if (isRealtimeWatching.value) {
      stopRealtimeWatch();
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
  String get tag => 'logs_viewer';

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
              tooltip: '加载历史日志',
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
      tag: tag,
      builder: (controller) {
        if (controller.logLines.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '正在监听实时日志...',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击右上角刷新按钮加载历史日志',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ScrollConfiguration(
            behavior: MaterialScrollBehavior().copyWith(overscroll: false),
            child: ListView.builder(
              controller: controller.scrollController,
            padding: const EdgeInsets.all(8),
          reverse: true,
          itemCount: controller.logLines.length,
          itemBuilder: (context, index) {
            final logLine = controller.logLines[index];
            return _buildLogItemWidget(logLine);
          },
        ),
          ),
        );
      },
    );
  }

  /// 构建单个日志项 Widget
  Widget _buildLogItemWidget(LogLine logLine) {
    final color = logLine.type == LogType.rust ? Colors.orange : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类型标识
          Container(
            width: 4,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // 日志内容
          Expanded(
            child: SelectableText(
              logLine.content,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
                color: _getLogColor(logLine.content),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 根据日志内容获取颜色
  Color _getLogColor(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('[error]') || lower.contains('[exception]')) {
      return Colors.red[700]!;
    }
    if (lower.contains('[warn]')) {
      return Colors.orange[700]!;
    }
    if (lower.contains('[info]') || lower.contains('[i]')) {
      return Colors.black87;
    }
    if (lower.contains('[debug]') || lower.contains('[d]')) {
      return Colors.grey[700]!;
    }
    return Colors.black87;
  }
}
