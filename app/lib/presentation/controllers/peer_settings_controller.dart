import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/peer_config_service.dart';
import '../../../services/log_service.dart';
import '../../../app/routes/app_pages.dart';

/// 设备设置控制器
class PeerSettingsController extends GetxController {
  /// 对方 Peer ID（从路由参数获取）
  final String peerId = Get.parameters['peerId'] ?? '';

  /// 对方名称（从路由参数获取）
  final String peerName = Get.parameters['peerName'] ?? 'Unknown';

  /// 配置数据
  final Rx<PeerConfig> config = const PeerConfig().obs;

  /// 是否正在加载
  final isLoading = false.obs;

  /// 是否正在保存
  final isSaving = false.obs;

  // ========== 依赖注入 ==========

  final PeerConfigService _configService = Get.find<PeerConfigService>();
  final LogService _log = Get.find<LogService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[PeerSettingsController] onInit - peerId: $peerId, peerName: $peerName');
    loadConfig();
  }

  @override
  void onClose() {
    super.onClose();
  }

  // ========== 数据加载 ==========

  /// 加载配置
  Future<void> loadConfig() async {
    if (peerId.isEmpty) {
      _log.e('[PeerSettingsController] Peer ID 为空');
      Get.back();
      return;
    }

    try {
      isLoading.value = true;
      final loadedConfig = await _configService.getConfig(peerId);
      config.value = loadedConfig;
      _log.d('[PeerSettingsController] 配置加载成功: ${config.value}');
    } catch (e, stackTrace) {
      _log.e('[PeerSettingsController] 加载配置失败: $e', e, stackTrace);
    } finally {
      isLoading.value = false;
    }
  }

  // ========== 配置更新 ==========

  /// 切换自动接收文件
  void toggleAutoReceiveFiles(bool value) {
    final currentConfig = config.value;
    config.value = currentConfig.copyWith(autoReceiveFiles: value);
  }

  /// 切换自动复制剪切板
  void toggleAutoCopyClipboard(bool value) {
    final currentConfig = config.value;
    config.value = currentConfig.copyWith(autoCopyClipboard: value);
  }

  /// 切换通知
  void toggleNotifications(bool value) {
    final currentConfig = config.value;
    config.value = currentConfig.copyWith(notificationsEnabled: value);
  }

  /// 切换自动下载图片
  void toggleAutoDownloadImages(bool value) {
    final currentConfig = config.value;
    config.value = currentConfig.copyWith(autoDownloadImages: value);
  }

  /// 切换消息提示音
  void toggleMessageSound(bool value) {
    final currentConfig = config.value;
    config.value = currentConfig.copyWith(messageSoundEnabled: value);
  }

  /// 切换消息振动
  void toggleMessageVibration(bool value) {
    final currentConfig = config.value;
    config.value = currentConfig.copyWith(messageVibrationEnabled: value);
  }

  /// 保存配置
  Future<void> saveConfig() async {
    try {
      isSaving.value = true;

      final success = await _configService.saveConfig(peerId, config.value);

      if (success) {
        _log.i('[PeerSettingsController] 配置保存成功');
        Get.snackbar(
          '成功',
          '配置已保存',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
        );
        Get.back(); // 返回上一页
      } else {
        _log.e('[PeerSettingsController] 配置保存失败');
        Get.snackbar(
          '失败',
          '配置保存失败，请重试',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e, stackTrace) {
      _log.e('[PeerSettingsController] 保存配置异常: $e', e, stackTrace);
      Get.snackbar(
        '错误',
        '保存配置时发生错误',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isSaving.value = false;
    }
  }

  /// 重置为默认配置
  Future<void> resetToDefault() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('确认重置'),
        content: const Text('确定要将此设备的配置重置为默认值吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('重置'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      config.value = PeerConfig();
      await saveConfig();
    }
  }

  // ========== 导航操作 ==========

  /// 打开设备详情
  void openDeviceDetail() {
    Get.toNamed(
      Routes.deviceDetail,
      parameters: {'peerId': peerId},
    );
  }
}
