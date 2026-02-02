import 'dart:async';
import 'package:nsd/nsd.dart' as nsd_pkg;
import 'package:nsd/nsd.dart'
    show
        Discovery,
        Registration,
        Service,
        ServiceStatus,
        stopDiscovery,
        unregister;
import 'log_service.dart';

/// Flutter mDNS 辅助服务（使用 nsd）
///
/// nsd 是跨平台的 mDNS 库，支持 Android 和 iOS
/// 用于在检测到 VPN 时，作为 Rust mDNS 的补充
///
/// ⚠️ 注意：nsd 在 Android 上使用 NsdManager，iOS 上使用 Bonjour
class FlutterMdnsService {
  static FlutterMdnsService? _instance;
  static FlutterMdnsService get instance =>
      _instance ??= FlutterMdnsService._();

  FlutterMdnsService._();

  final _log = LogService.instance;

  bool _isRunning = false;
  Discovery? _discovery;
  Registration? _registration;
  StreamSubscription? _serviceListenerSubscription;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 注册 mDNS 服务（广播自己的存在）
  Future<bool> registerService({
    required String name,
    required int port,
    required String serviceType,
  }) async {
    try {
      _log.i('[Flutter mDNS] 注册服务请求: $name@$port ($serviceType)');

      // nsd 库期望服务类型格式: "_localp2p._tcp" (不带 .local. 后缀)
      String nsdServiceType = serviceType;
      if (nsdServiceType.endsWith('.local.')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 7);
      } else if (nsdServiceType.endsWith('.local')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 6);
      }

      _log.d('[Flutter mDNS] 转换后的服务类型: $nsdServiceType');

      // nsd 支持注册服务
      final service = Service(name: name, type: nsdServiceType, port: port);

      _registration = await nsd_pkg.register(service);
      _log.i('[Flutter mDNS] 服务注册成功: $_registration');
      _isRunning = true;
      return true;
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 注册服务失败: $e', e, stackTrace);
      return false;
    }
  }

  /// 开始浏览服务（发现其他设备）
  Future<Discovery> startServiceDiscovery(String serviceType) async {
    _log.i('[Flutter mDNS] 开始浏览服务: $serviceType');

    try {
      // nsd 库期望服务类型格式: "_localp2p._tcp" (不带 .local. 后缀)
      String nsdServiceType = serviceType;
      if (nsdServiceType.endsWith('.local.')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 7);
      } else if (nsdServiceType.endsWith('.local')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 6);
      }

      _log.d('[Flutter mDNS] 转换后的服务类型: $nsdServiceType');

      // nsd 会自动解析服务（autoResolve: true）
      _discovery = await nsd_pkg.startDiscovery(
        nsdServiceType,
        autoResolve: true,
      );

      _isRunning = true;
      _log.i('[Flutter mDNS] 浏览已启动，等待设备发现...');

      return _discovery!;
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 启动浏览失败: $e', e, stackTrace);
      _isRunning = false;
      rethrow;
    }
  }

  /// 停止所有服务
  Future<void> stop() async {
    if (!_isRunning) return;

    _log.i('[Flutter mDNS] 停止服务');

    await _serviceListenerSubscription?.cancel();
    _serviceListenerSubscription = null;

    // 停止浏览
    if (_discovery != null) {
      try {
        await stopDiscovery(_discovery!);
        _discovery = null;
      } catch (e) {
        _log.w('[Flutter mDNS] 停止浏览时出错（可忽略）: $e');
      }
    }

    // 停止注册
    if (_registration != null) {
      try {
        await unregister(_registration!);
        _registration = null;
      } catch (e) {
        _log.w('[Flutter mDNS] 取消注册时出错（可忽略）: $e');
      }
    }

    _isRunning = false;

    _log.i('[Flutter mDNS] 服务已停止');
  }

  /// 完整启动：注册服务 + 开始浏览
  Future<bool> start({
    required String name,
    required int port,
    required String serviceType,
    required Function(Service) onDeviceFound,
    Function(String)? onDeviceLost,
  }) async {
    _log.i('[Flutter mDNS] 完整启动: $name@$port ($serviceType)');

    try {
      // 1. 注册服务（广播自己的存在）
      await registerService(name: name, port: port, serviceType: serviceType);

      // 2. 开始浏览（发现其他设备）
      _log.i('[Flutter mDNS] 开始浏览其他设备');

      // nsd 库期望服务类型格式: "_localp2p._tcp" (不带 .local. 后缀)
      String nsdServiceType = serviceType;
      if (nsdServiceType.endsWith('.local.')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 7);
      } else if (nsdServiceType.endsWith('.local')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 6);
      }

      _log.d('[Flutter mDNS] 转换后的服务类型: $nsdServiceType');

      _discovery = await nsd_pkg.startDiscovery(
        nsdServiceType,
        autoResolve: true,
      );

      // 添加服务监听器
      _discovery!.addServiceListener((service, status) {
        _log.i('[Flutter mDNS] 服务状态变化: ${service.name} - $status');

        if (status == ServiceStatus.found) {
          _log.i('[Flutter mDNS] 发现设备: ${service.name}');
          onDeviceFound(service);
        } else if (status == ServiceStatus.lost) {
          _log.i('[Flutter mDNS] 设备离线: ${service.name}');
          onDeviceLost?.call(service.name ?? '');
        }
      });

      _isRunning = true;
      _log.i('[Flutter mDNS] 浏览启动成功');
      return true;
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 启动失败: $e', e, stackTrace);
      _isRunning = false;
      await _serviceListenerSubscription?.cancel();
      _serviceListenerSubscription = null;
      return false;
    }
  }
}
