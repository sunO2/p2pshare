import 'package:flutter/services.dart';
import 'log_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// mDNS 诊断服务
///
/// 用于诊断 mDNS 广播/接收问题，帮助用户自助排查故障
class MdnsDiagnosticService {
  static MdnsDiagnosticService? _instance;
  static MdnsDiagnosticService get instance =>
      _instance ??= MdnsDiagnosticService._();

  MdnsDiagnosticService._();

  final _log = LogService.instance;

  static const _channel = MethodChannel('com.suno2.localp2p/mdns');

  /// 诊断结果
  final Map<String, dynamic> _diagnosticResults = {};

  /// 获取诊断结果
  Map<String, dynamic> get results => Map.unmodifiable(_diagnosticResults);

  /// 清除诊断结果
  void clearResults() {
    _diagnosticResults.clear();
  }

  /// 运行完整诊断
  Future<MdnsDiagnosticStatus> runFullDiagnostic() async {
    _log.i('═══════════════════════════════════════');
    _log.i('🔍 开始 mDNS 诊断');
    _log.i('═══════════════════════════════════════');

    clearResults();

    try {
      // 1. 检查网络连接
      await _checkConnectivity();

      // 2. 检查 MulticastLock
      await _checkMulticastLock();

      // 3. 检查 WiFi 信息
      await _checkWiFiInfo();

      // 4. 检查位置服务
      await _checkLocationService();

      // 5. 生成诊断报告
      return _generateReport();
    } catch (e, stackTrace) {
      _log.e('诊断过程出错: $e', e, stackTrace);
      return MdnsDiagnosticStatus.error('诊断失败: $e');
    }
  }

  /// 1. 检查网络连接
  Future<void> _checkConnectivity() async {
    _log.i('[1/5] 检查网络连接...');

    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();

      final isConnected = results.any((r) => r != ConnectivityResult.none);
      _diagnosticResults['isConnected'] = isConnected;

      if (isConnected) {
        _log.i('✅ 网络已连接: $results');
        _diagnosticResults['connectivityResult'] = results.toString();
      } else {
        _log.e('❌ 无网络连接');
        _diagnosticResults['error_connectivity'] = '未连接到任何网络';
      }
    } catch (e) {
      _log.e('检查网络连接失败: $e');
      _diagnosticResults['error_connectivity'] = e.toString();
    }
  }

  /// 2. 检查 MulticastLock
  Future<void> _checkMulticastLock() async {
    _log.i('[2/5] 检查 MulticastLock...');

    try {
      final isHeld =
          await _channel.invokeMethod<bool>('isMulticastLockHeld') ?? false;
      _diagnosticResults['multicastLockHeld'] = isHeld;

      if (isHeld) {
        _log.i('✅ MulticastLock 已获取（mDNS 可以正常工作）');
      } else {
        _log.e('❌ MulticastLock 未获取！mDNS 可能无法工作');
        _diagnosticResults['error_multicastLock'] = 'MulticastLock 未获取';
      }
    } catch (e) {
      _log.e('检查 MulticastLock 失败: $e');
      _diagnosticResults['error_multicastLock'] = e.toString();
    }
  }

  /// 3. 检查 WiFi 信息
  Future<void> _checkWiFiInfo() async {
    _log.i('[3/5] 检查 WiFi 信息...');

    try {
      // 从原生获取网络信息
      final networkInfo = await _channel.invokeMapMethod<String, dynamic>(
        'getNetworkInfo',
      );
      if (networkInfo != null) {
        _diagnosticResults.addAll(networkInfo);

        final wifiEnabled = networkInfo['wifiEnabled'] as bool? ?? false;
        if (wifiEnabled) {
          final ssid = networkInfo['ssid'] as String?;
          final ipAddress = networkInfo['ipAddress'] as String?;
          _log.i('✅ WiFi 已连接');
          _log.i('   SSID: $ssid');
          _log.i('   IP: $ipAddress');
        } else {
          _log.w('⚠️  WiFi 未启用');
          _diagnosticResults['error_wifi'] = 'WiFi 未启用';
        }
      }

      // 使用 network_info_plus 获取额外信息
      final info = NetworkInfo();
      final wifiName = await info.getWifiName();
      final wifiIP = await info.getWifiIP();

      _diagnosticResults['wifiName'] = wifiName;
      _diagnosticResults['wifiIP'] = wifiIP;

      _log.d('WiFi 名称: $wifiName');
      _log.d('WiFi IP: $wifiIP');
    } catch (e) {
      _log.e('获取 WiFi 信息失败: $e');
      _diagnosticResults['error_wifiInfo'] = e.toString();
    }
  }

  /// 4. 检查位置服务
  Future<void> _checkLocationService() async {
    _log.i('[4/5] 检查位置服务...');

    try {
      // 位置服务检查需要 permission_handler
      // 这里先记录日志，实际检查需要在 UI 层使用 permission_handler
      _log.i('ℹ️  位置服务状态需要在 UI 层检查');

      _diagnosticResults['locationServiceRequired'] = true;
      _diagnosticResults['locationServiceNote'] =
          'Android 10+ 需要开启位置服务才能使用 mDNS';
    } catch (e) {
      _log.e('检查位置服务失败: $e');
    }
  }

  /// 生成诊断报告
  MdnsDiagnosticStatus _generateReport() {
    _log.i('[5/5] 生成诊断报告...');

    final hasError = _diagnosticResults.keys.any((k) => k.startsWith('error_'));

    if (hasError) {
      _log.e('═══════════════════════════════════════');
      _log.e('❌ 诊断发现问题');
      _log.e('═══════════════════════════════════════');

      final errors = _diagnosticResults.entries
          .where((e) => e.key.startsWith('error_'))
          .map((e) => '  - ${e.key.substring(6)}: ${e.value}')
          .join('\n');

      _log.e('发现的问题:\n$errors');

      return MdnsDiagnosticStatus.hasIssues(_diagnosticResults);
    } else {
      _log.i('═══════════════════════════════════════');
      _log.i('✅ 诊断通过，所有检查正常');
      _log.i('═══════════════════════════════════════');

      return MdnsDiagnosticStatus.ok(_diagnosticResults);
    }
  }

  /// 获取用户友好的建议
  List<String> getSuggestions() {
    final suggestions = <String>[];

    // 网络连接问题
    if (_diagnosticResults['isConnected'] != true) {
      suggestions.add('请连接到 WiFi 网络');
    }

    // MulticastLock 问题
    if (_diagnosticResults['multicastLockHeld'] != true) {
      suggestions.add('MulticastLock 未获取，请重启 App');
    }

    // WiFi 未启用
    if (_diagnosticResults['wifiEnabled'] != true) {
      suggestions.add('请开启 WiFi');
    }

    // 位置服务提示
    suggestions.add('请确保已授予位置权限（Android 10+ 需要）');
    suggestions.add('请确保位置服务已开启（设置 > 位置）');

    // 厂商特定建议
    suggestions.addAll(_getVendorSpecificSuggestions());

    return suggestions;
  }

  /// 获取厂商特定建议
  List<String> _getVendorSpecificSuggestions() {
    // 这里可以通过检测设备型号给出特定建议
    // 暂时返回通用建议
    return [
      '小米/红米手机: 设置 > 应用管理 > 本应用 > 省电策略 > 无限制',
      '华为手机: 设置 > 应用 > 应用启动管理 > 本应用 > 关闭自动管理',
      'OPPO/Vivo: 设置 > 电池 > 耗电保护 > 允许后台运行',
    ];
  }

  /// 手动获取 MulticastLock
  Future<bool> acquireMulticastLock() async {
    try {
      _log.i('手动获取 MulticastLock...');
      final result = await _channel.invokeMethod<bool>('acquireMulticastLock');
      _log.i('获取结果: $result');
      return result ?? false;
    } catch (e) {
      _log.e('获取 MulticastLock 失败: $e');
      return false;
    }
  }

  /// 手动释放 MulticastLock
  Future<bool> releaseMulticastLock() async {
    try {
      _log.i('手动释放 MulticastLock...');
      final result = await _channel.invokeMethod<bool>('releaseMulticastLock');
      _log.i('释放结果: $result');
      return result ?? false;
    } catch (e) {
      _log.e('释放 MulticastLock 失败: $e');
      return false;
    }
  }
}

/// 诊断状态
class MdnsDiagnosticStatus {
  final bool isSuccess;
  final Map<String, dynamic> results;
  final String? errorMessage;

  MdnsDiagnosticStatus.ok(this.results) : isSuccess = true, errorMessage = null;

  MdnsDiagnosticStatus.hasIssues(this.results)
    : isSuccess = false,
      errorMessage = '诊断发现问题，请查看详情';

  MdnsDiagnosticStatus.error(this.errorMessage)
    : isSuccess = false,
      results = {};

  @override
  String toString() {
    if (isSuccess) {
      return '诊断通过';
    } else {
      return errorMessage ?? '未知错误';
    }
  }
}
