import 'package:get/get.dart';
import '../views/debug/logs_viewer_view.dart';

/// 日志查看器依赖注入
class LogsViewerBinding extends Bindings {
  @override
  void dependencies() {
    // 使用 tag 确保每次都能找到或创建新实例
    // 检查是否已存在，如果不存在则创建
    if (!Get.isRegistered<LogsViewerController>(tag: 'logs_viewer')) {
      Get.put<LogsViewerController>(
        LogsViewerController(),
        tag: 'logs_viewer',
      );
    }
  }
}
