import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'log_service.dart';

/// 设备节点配置
///
/// 每个设备节点可以有独立的配置
class PeerConfig {
  /// 是否自动接收文件
  final bool autoReceiveFiles;

  /// 是否自动复制剪切板消息
  final bool autoCopyClipboard;

  /// 是否启用通知
  final bool notificationsEnabled;

  /// 是否自动下载图片
  final bool autoDownloadImages;

  /// 消息提示音
  final bool messageSoundEnabled;

  /// 消息振动
  final bool messageVibrationEnabled;

  const PeerConfig({
    this.autoReceiveFiles = false,
    this.autoCopyClipboard = false,
    this.notificationsEnabled = true,
    this.autoDownloadImages = true,
    this.messageSoundEnabled = true,
    this.messageVibrationEnabled = true,
  });

  /// 从 JSON 创建
  factory PeerConfig.fromJson(Map<String, dynamic> json) {
    return PeerConfig(
      autoReceiveFiles: json['autoReceiveFiles'] as bool? ?? false,
      autoCopyClipboard: json['autoCopyClipboard'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      autoDownloadImages: json['autoDownloadImages'] as bool? ?? true,
      messageSoundEnabled: json['messageSoundEnabled'] as bool? ?? true,
      messageVibrationEnabled: json['messageVibrationEnabled'] as bool? ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'autoReceiveFiles': autoReceiveFiles,
      'autoCopyClipboard': autoCopyClipboard,
      'notificationsEnabled': notificationsEnabled,
      'autoDownloadImages': autoDownloadImages,
      'messageSoundEnabled': messageSoundEnabled,
      'messageVibrationEnabled': messageVibrationEnabled,
    };
  }

  /// 复制并修改部分字段
  PeerConfig copyWith({
    bool? autoReceiveFiles,
    bool? autoCopyClipboard,
    bool? notificationsEnabled,
    bool? autoDownloadImages,
    bool? messageSoundEnabled,
    bool? messageVibrationEnabled,
  }) {
    return PeerConfig(
      autoReceiveFiles: autoReceiveFiles ?? this.autoReceiveFiles,
      autoCopyClipboard: autoCopyClipboard ?? this.autoCopyClipboard,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoDownloadImages: autoDownloadImages ?? this.autoDownloadImages,
      messageSoundEnabled: messageSoundEnabled ?? this.messageSoundEnabled,
      messageVibrationEnabled: messageVibrationEnabled ?? this.messageVibrationEnabled,
    );
  }

  @override
  String toString() => toJson().toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerConfig &&
          runtimeType == other.runtimeType &&
          autoReceiveFiles == other.autoReceiveFiles &&
          autoCopyClipboard == other.autoCopyClipboard &&
          notificationsEnabled == other.notificationsEnabled &&
          autoDownloadImages == other.autoDownloadImages &&
          messageSoundEnabled == other.messageSoundEnabled &&
          messageVibrationEnabled == other.messageVibrationEnabled;

  @override
  int get hashCode =>
      autoReceiveFiles.hashCode ^
      autoCopyClipboard.hashCode ^
      notificationsEnabled.hashCode ^
      autoDownloadImages.hashCode ^
      messageSoundEnabled.hashCode ^
      messageVibrationEnabled.hashCode;
}

/// 设备节点配置服务
///
/// 使用 SharedPreferences 存储每个设备的独立配置
/// 存储格式：peer_config_{peerId} = JSON字符串
class PeerConfigService extends GetxService {
  static const String _configPrefix = 'peer_config_';

  /// SharedPreferences 实例
  SharedPreferences? _prefs;

  /// 内存缓存（避免频繁读取）
  final Map<String, PeerConfig> _cache = {};

  /// 默认配置
  static const PeerConfig defaultConfig = PeerConfig();

  /// 日志服务（懒加载获取）
  LogService get _log => Get.find<LogService>();

  @override
  void onInit() {
    super.onInit();
    _initPrefs();
  }

  /// 初始化 SharedPreferences
  Future<void> _initPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _log.d('[PeerConfigService] SharedPreferences 初始化成功');
    } catch (e) {
      _log.e('[PeerConfigService] SharedPreferences 初始化失败: $e', e);
    }
  }

  /// 确保 SharedPreferences 已初始化
  Future<void> _ensurePrefs() async {
    if (_prefs == null) {
      await _initPrefs();
    }
  }

  /// 获取指定 peerId 的配置
  ///
  /// 如果没有配置则返回默认配置
  Future<PeerConfig> getConfig(String peerId) async {
    // 先检查内存缓存
    if (_cache.containsKey(peerId)) {
      return _cache[peerId]!;
    }

    await _ensurePrefs();

    try {
      final configJson = _prefs?.getString('$_configPrefix$peerId');
      if (configJson != null && configJson.isNotEmpty) {
        final json = jsonDecode(configJson) as Map<String, dynamic>;
        final config = PeerConfig.fromJson(json);
        _cache[peerId] = config;
        return config;
      }
    } catch (e) {
      _log.e('[PeerConfigService] 获取配置失败: $peerId, $e', e);
    }

    // 返回默认配置并缓存
    _cache[peerId] = defaultConfig;
    return defaultConfig;
  }

  /// 保存指定 peerId 的配置
  Future<bool> saveConfig(String peerId, PeerConfig config) async {
    await _ensurePrefs();

    try {
      final configJson = jsonEncode(config.toJson());
      final success = await _prefs!.setString('$_configPrefix$peerId', configJson);

      if (success) {
        _cache[peerId] = config;
        _log.d('[PeerConfigService] 保存配置成功: $peerId');
      }

      return success;
    } catch (e) {
      _log.e('[PeerConfigService] 保存配置失败: $peerId, $e', e);
      return false;
    }
  }

  /// 更新指定 peerId 的部分配置
  Future<bool> updateConfig(
    String peerId, {
    bool? autoReceiveFiles,
    bool? autoCopyClipboard,
    bool? notificationsEnabled,
    bool? autoDownloadImages,
    bool? messageSoundEnabled,
    bool? messageVibrationEnabled,
  }) async {
    final currentConfig = await getConfig(peerId);
    final newConfig = currentConfig.copyWith(
      autoReceiveFiles: autoReceiveFiles,
      autoCopyClipboard: autoCopyClipboard,
      notificationsEnabled: notificationsEnabled,
      autoDownloadImages: autoDownloadImages,
      messageSoundEnabled: messageSoundEnabled,
      messageVibrationEnabled: messageVibrationEnabled,
    );

    return await saveConfig(peerId, newConfig);
  }

  /// 删除指定 peerId 的配置
  Future<bool> deleteConfig(String peerId) async {
    await _ensurePrefs();

    try {
      final success = await _prefs!.remove('$_configPrefix$peerId');
      if (success) {
        _cache.remove(peerId);
        _log.d('[PeerConfigService] 删除配置成功: $peerId');
      }
      return success;
    } catch (e) {
      _log.e('[PeerConfigService] 删除配置失败: $peerId, $e', e);
      return false;
    }
  }

  /// 清空所有设备配置
  Future<bool> clearAllConfigs() async {
    await _ensurePrefs();

    try {
      final keys = _prefs!.getKeys().where((key) => key.startsWith(_configPrefix));
      for (final key in keys) {
        await _prefs!.remove(key);
      }
      _cache.clear();
      _log.d('[PeerConfigService] 清空所有配置成功');
      return true;
    } catch (e) {
      _log.e('[PeerConfigService] 清空所有配置失败: $e', e);
      return false;
    }
  }

  /// 获取所有已配置的 peerId 列表
  Future<List<String>> getConfiguredPeerIds() async {
    await _ensurePrefs();

    try {
      final keys = _prefs!.getKeys()
          .where((key) => key.startsWith(_configPrefix))
          .map((key) => key.substring(_configPrefix.length))
          .toList();

      return keys;
    } catch (e) {
      _log.e('[PeerConfigService] 获取配置列表失败: $e', e);
      return [];
    }
  }

  /// 检查是否自动接收文件
  Future<bool> shouldAutoReceiveFiles(String peerId) async {
    final config = await getConfig(peerId);
    return config.autoReceiveFiles;
  }

  /// 检查是否自动复制剪切板
  Future<bool> shouldAutoCopyClipboard(String peerId) async {
    final config = await getConfig(peerId);
    return config.autoCopyClipboard;
  }

  /// 检查是否启用通知
  Future<bool> shouldNotify(String peerId) async {
    final config = await getConfig(peerId);
    return config.notificationsEnabled;
  }

  /// 检查是否自动下载图片
  Future<bool> shouldAutoDownloadImages(String peerId) async {
    final config = await getConfig(peerId);
    return config.autoDownloadImages;
  }
}
