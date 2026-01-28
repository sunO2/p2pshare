import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 存储服务
///
/// 提供持久化存储功能，用于保存设备名称等配置
class StorageService {
  static StorageService? _instance;
  SharedPreferences? _prefs;

  // 存储键名
  static const String _keyDeviceName = 'device_name';
  static const String _keyNickname = 'nickname';
  static const String _keyStatus = 'status';

  // 私有构造函数
  StorageService._();

  /// 获取单例实例
  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }

  /// 初始化存储服务
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      debugPrint('StorageService: 初始化成功');
    } catch (e) {
      debugPrint('StorageService: 初始化失败 - $e');
      rethrow;
    }
  }

  /// 生成随机设备名称
  ///
  /// 格式: {形容词}{名词}{数字}
  /// 例如: 快速熊猫123, 快乐手机456
  String _generateRandomDeviceName() {
    final adjectives = [
      '快乐',
      '幸运',
      '快速',
      '聪明',
      '勇敢',
      '温柔',
      '活泼',
      '安静',
      '神秘',
      '热情',
      '可爱',
      '酷炫',
      '闪亮',
      '舒适',
      '无敌',
    ];

    final nouns = [
      '熊猫',
      '老虎',
      '狮子',
      '兔子',
      '松鼠',
      '手机',
      '电脑',
      '平板',
      '笔记本',
      '台式机',
      '飞船',
      '火箭',
      '流星',
      '闪电',
      '彩虹',
    ];

    final random = Random();
    final adjective = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    final number = random.nextInt(1000);

    return '$adjective$noun$number';
  }

  /// 获取设备名称
  ///
  /// 如果不存在，会生成并保存一个随机设备名称
  Future<String> getDeviceName() async {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }

    String? deviceName = _prefs!.getString(_keyDeviceName);

    if (deviceName == null || deviceName.isEmpty) {
      // 首次启动，生成随机设备名称
      deviceName = _generateRandomDeviceName();
      await setDeviceName(deviceName);
      debugPrint('StorageService: 生成新设备名称 - $deviceName');
    }

    return deviceName;
  }

  /// 设置设备名称
  Future<void> setDeviceName(String deviceName) async {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }

    final success = await _prefs!.setString(_keyDeviceName, deviceName);
    if (success) {
      debugPrint('StorageService: 设备名称已更新 - $deviceName');
    } else {
      debugPrint('StorageService: 设备名称更新失败');
    }
  }

  /// 获取昵称
  String? getNickname() {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }
    return _prefs!.getString(_keyNickname);
  }

  /// 设置昵称
  Future<void> setNickname(String? nickname) async {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }

    if (nickname == null || nickname.isEmpty) {
      await _prefs!.remove(_keyNickname);
      debugPrint('StorageService: 昵称已清除');
    } else {
      await _prefs!.setString(_keyNickname, nickname);
      debugPrint('StorageService: 昵称已更新 - $nickname');
    }
  }

  /// 获取状态
  String? getStatus() {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }
    return _prefs!.getString(_keyStatus);
  }

  /// 设置状态
  Future<void> setStatus(String? status) async {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }

    if (status == null || status.isEmpty) {
      await _prefs!.remove(_keyStatus);
      debugPrint('StorageService: 状态已清除');
    } else {
      await _prefs!.setString(_keyStatus, status);
      debugPrint('StorageService: 状态已更新 - $status');
    }
  }

  /// 清除所有数据
  Future<void> clearAll() async {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化');
    }

    await _prefs!.clear();
    debugPrint('StorageService: 所有数据已清除');
  }
}
