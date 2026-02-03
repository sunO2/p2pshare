import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../p2p_manager.dart';
import '../../../services/log_service.dart';
import '../../../services/storage_service.dart';
import '../views/debug/logs_viewer_view.dart';

/// 设置页面控制器
///
/// 管理：设备信息、用户资料、应用设置、调试功能
class SettingsController extends GetxController {
  // ========== 状态变量 ==========

  /// 本地 Peer ID
  final localPeerId = ''.obs;

  /// 设备名称
  final deviceName = ''.obs;

  /// 昵称
  final nickname = ''.obs;

  /// 状态
  final status = '在线'.obs;

  /// 通知开关
  final notificationsEnabled = true.obs;

  /// 自动扫描开关
  final autoScanEnabled = false.obs;

  /// 日志文件大小
  final logFileSize = 0.obs;

  // ========== 依赖注入 ==========

  final LogService _log = Get.find<LogService>();
  final StorageService _storage = Get.find<StorageService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[SettingsController] onInit');
    loadDeviceInfo();
    loadLogInfo();
  }

  @override
  void onReady() {
    super.onReady();
    _log.i('[SettingsController] onReady');
  }

  @override
  void onClose() {
    _log.i('[SettingsController] onClose');
    super.onClose();
  }

  // ========== 数据加载 ==========

  /// 加载设备信息
  Future<void> loadDeviceInfo() async {
    try {
      final peerId = P2PManager.instance.getLocalPeerId();
      final name = P2PManager.instance.getDeviceName();
      final nick = await _storage.getNickname() ?? '未设置';
      final stat = await _storage.getStatus() ?? '在线';

      localPeerId.value = peerId;
      deviceName.value = name;
      nickname.value = nick;
      status.value = stat;
      _log.i('[SettingsController] 加载设备信息成功');
    } catch (e) {
      _log.e('加载设备信息失败: $e', e);
    }
  }

  /// 加载日志信息
  Future<void> loadLogInfo() async {
    final size = await _log.getLogFileSize();
    logFileSize.value = size;
  }

  // ========== 设备设置 ==========

  /// 编辑设备名称
  Future<void> editDeviceName(String newValue) async {
    if (newValue.isEmpty) {
      Get.snackbar(
        '提示',
        '设备名称不能为空',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      await _storage.setDeviceName(newValue);
      deviceName.value = newValue;
      Get.snackbar(
        '成功',
        '设备名称已更新，重启应用后生效',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      _log.e('保存设备名称失败: $e', e);
      Get.snackbar(
        '失败',
        '保存失败: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // ========== 用户资料 ==========

  /// 编辑昵称
  Future<void> editNickname(String newValue) async {
    try {
      if (newValue.isEmpty) {
        await _storage.setNickname(null);
        nickname.value = '未设置';
      } else {
        await _storage.setNickname(newValue);
        nickname.value = newValue;
      }
      Get.snackbar(
        '成功',
        '昵称已更新',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      _log.e('保存昵称失败: $e', e);
      Get.snackbar(
        '失败',
        '保存失败: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  /// 选择状态
  Future<void> selectStatus(String newStatus) async {
    try {
      await _storage.setStatus(newStatus);
      status.value = newStatus;
      Get.snackbar(
        '成功',
        '状态已更改为: $newStatus',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      _log.e('保存状态失败: $e', e);
      Get.snackbar(
        '失败',
        '保存失败: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  /// 切换通知开关
  void toggleNotifications(bool value) {
    notificationsEnabled.value = value;
  }

  /// 切换自动扫描开关
  void toggleAutoScan(bool value) {
    autoScanEnabled.value = value;
  }

  // ========== 调试功能 ==========

  /// 查看日志
  void showLogs() {
    Get.to(() => const LogsViewerView());
    loadLogInfo();
  }

  /// 清空日志
  Future<void> clearLogs() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有日志吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _log.clearLogs();
        Get.snackbar(
          '成功',
          '日志已清空',
          snackPosition: SnackPosition.BOTTOM,
        );
        loadLogInfo();
      } catch (e) {
        _log.e('清空日志失败: $e', e);
        Get.snackbar(
          '失败',
          '清空失败: $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  // ========== 工具方法 ==========

  /// 格式化文件大小
  String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// 缩短 Peer ID 显示
  String shortenPeerId(String peerId) {
    if (peerId.length > 12) {
      return '${peerId.substring(0, 10)}...';
    }
    return peerId;
  }
}
