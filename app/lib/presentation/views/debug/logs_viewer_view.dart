import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/log_service.dart';
import '../../../widgets/unified_app_bar.dart';

/// 日志查看器页面控制器
class LogsViewerController extends GetxController {
  /// 选中的日期
  final selectedDate = ''.obs;

  /// 可用日期列表
  final availableDates = <String>[].obs;

  /// 日志行列表
  final logLines = <LogLine>[].obs;

  /// 自动滚动
  final autoScroll = true.obs;

  /// 显示 Flutter 日志
  final showFlutterLogs = true.obs;

  /// 显示 Rust 日志
  final showRustLogs = true.obs;

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
  void onClose() {
    stopRealtimeWatch();
    scrollController.dispose();
    super.onClose();
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
      final flutterLogs = await _log.getLogsByDate(selectedDate.value, LogType.flutter);
      final rustLogs = await _log.getLogsByDate(selectedDate.value, LogType.rust);

      final lines = [
        ...flutterLogs.map((log) => LogLine(
              content: log,
              type: LogType.flutter,
              timestamp: DateTime.now(),
            )),
        ...rustLogs.map((log) => LogLine(
              content: log,
              type: LogType.rust,
              timestamp: DateTime.now(),
            )),
      ];
      lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      logLines.assignAll(lines);
      if (autoScroll.value) {
        scrollToBottom();
      }
    } catch (e) {
      _log.e('Failed to load logs: $e', e);
    }
  }

  /// 切换日期
  Future<void> changeDate(String? newDate) async {
    if (newDate == null || newDate == selectedDate.value) return;

    stopRealtimeWatch();
    selectedDate.value = newDate;
    logLines.clear();
    await loadInitialLogs();
    startRealtimeWatch();
  }

  /// 刷新日志
  Future<void> refreshLogs() async {
    stopRealtimeWatch();
    logLines.clear();
    await loadInitialLogs();
    startRealtimeWatch();
  }

  /// 开始实时监听
  void startRealtimeWatch() {
    if (isRealtimeWatching.value) return;

    isRealtimeWatching.value = true;
    _log.startRealtimeWatch(selectedDate.value);

    realtimeSubscription = _log.realtimeLogStream.listen((logLine) {
      // 过滤
      if (logLine.type == LogType.flutter && !showFlutterLogs.value) return;
      if (logLine.type == LogType.rust && !showRustLogs.value) return;

      logLines.add(logLine);

      if (autoScroll.value) {
        scrollToBottom();
      }
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

  /// 切换自动滚动
  void toggleAutoScroll() {
    autoScroll.value = !autoScroll.value;
    if (autoScroll.value) {
      scrollToBottom();
    }
  }

  /// 切换 Flutter 日志显示
  void toggleFlutterLogs() {
    showFlutterLogs.value = !showFlutterLogs.value;
  }

  /// 切换 Rust 日志显示
  void toggleRustLogs() {
    showRustLogs.value = !showRustLogs.value;
  }

  /// 滚动到底部
  void scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 过滤后的日志
  List<LogLine> get filteredLogs {
    return logLines.where((logLine) {
      if (logLine.type == LogType.flutter && !showFlutterLogs.value) return false;
      if (logLine.type == LogType.rust && !showRustLogs.value) return false;
      return true;
    }).toList();
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

              // 自动滚动开关
              _buildToggle(
                '自动滚动',
                controller.autoScroll.value,
                controller.toggleAutoScroll,
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
    return Obx(() {
      final logs = controller.filteredLogs;

      if (logs.isEmpty) {
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
        padding: const EdgeInsets.all(16),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final logLine = logs[index];
          final isFlutter = logLine.type == LogType.flutter;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isFlutter ? Colors.blue[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isFlutter ? Colors.blue : Colors.orange)!.withOpacity(0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: isFlutter ? Colors.blue : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    logLine.content,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
