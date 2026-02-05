import 'dart:async';
import 'dart:isolate';
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

  FlutterMdnsService._() {
    _log.i('[Flutter mDNS] 📍 FlutterMdnsService 实例创建, Isolate: ${Isolate.current.debugName}');
  }

  final _log = LogService.instance;

  bool _isRunning = false;
  Discovery? _discovery;
  Registration? _registration;
  StreamSubscription? _serviceListenerSubscription;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 应用生命周期状态
  String _appLifecycleState = 'unknown';

  /// 更新应用生命周期状态
  void updateLifecycleState(String state) {
    final oldState = _appLifecycleState;
    _appLifecycleState = state;
    _log.i('[Flutter mDNS] 🔄 生命周期状态变化: $oldState -> $state, Isolate: ${Isolate.current.debugName}');
  }

  /// 获取当前时间戳（毫秒）
  String _timestamp() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// 注册 mDNS 服务（广播自己的存在）
  Future<bool> registerService({
    required String name,
    required int port,
    required String serviceType,
  }) async {
    final startTime = DateTime.now();
    _log.i('[Flutter mDNS] [${_timestamp()}] 📝 注册服务请求: $name@$port ($serviceType)');
    _log.i('[Flutter mDNS] 📍 当前状态: isRunning=$_isRunning, lifecycle=$_appLifecycleState, Isolate: ${Isolate.current.debugName}');
    _log.i('[Flutter mDNS] 🔧 调用栈: ${StackTrace.current.toString().split('\n').take(3).join('\n')}');

    try {
      _log.d('[Flutter mDNS] [${_timestamp()}] ⏳ 开始处理服务类型...');

      // nsd 库期望服务类型格式: "_localp2p._tcp" (不带 .local. 后缀)
      String nsdServiceType = serviceType;
      if (nsdServiceType.endsWith('.local.')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 7);
      } else if (nsdServiceType.endsWith('.local')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 6);
      }

      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ 转换后的服务类型: "$nsdServiceType" (原始: "$serviceType")');

      // 检查服务名称长度（Android mDNS 限制）
      if (name.length > 63) {
        _log.w('[Flutter mDNS] ⚠️ 服务名称过长 (${name.length} 字符)，Android mDNS 限制 63 字符');
        final truncatedName = name.substring(0, 63);
        _log.i('[Flutter mDNS] 🔧 使用截断后的名称: $truncatedName');
        name = truncatedName;
      }

      _log.i('[Flutter mDNS] [${_timestamp()}] 🔧 创建 Service 对象...');

      // nsd 支持注册服务
      final service = Service(name: name, type: nsdServiceType, port: port);
      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ Service 对象创建完成: $service');

      _log.i('[Flutter mDNS] [${_timestamp()}] ⏳ 开始调用 nsd.register()...');
      _log.i('[Flutter mDNS] 🔧 此调用可能会阻塞，将在注册完成后或超时后继续');

      // 添加超时保护
      final registrationResult = await nsd_pkg.register(service).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          _log.e('[Flutter mDNS] [${_timestamp()}] ⏰ 注册超时！等待时间: ${elapsed}ms');
          _log.e('[Flutter mDNS] 🔍 超时详情: service=$service, lifecycle=$_appLifecycleState, isRunning=$_isRunning');
          throw TimeoutException('mDNS 服务注册超时 (${elapsed}ms)', const Duration(seconds: 10));
        },
      );

      _registration = registrationResult;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;

      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ 服务注册成功！耗时: ${elapsed}ms');
      _log.i('[Flutter mDNS] 📦 Registration 对象: $_registration');
      _isRunning = true;

      return true;
    } on TimeoutException catch (e, stackTrace) {
      _log.e('[Flutter mDNS] [${_timestamp()}] ⏰ 注册超时异常: $e', e, stackTrace);
      _log.e('[Flutter mDNS] 🔍 超时时状态: lifecycle=$_appLifecycleState, isRunning=$_isRunning');
      _isRunning = false;
      return false;
    } catch (e, stackTrace) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _log.e('[Flutter mDNS] [${_timestamp()}] ❌ 注册服务失败 (耗时 ${elapsed}ms): $e', e, stackTrace);
      _log.e('[Flutter mDNS] 🔍 失败时状态: lifecycle=$_appLifecycleState, isRunning=$_isRunning');
      _isRunning = false;
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
    final startTime = DateTime.now();
    _log.i('[Flutter mDNS] [${_timestamp()}] 🚀 完整启动开始: $name@$port ($serviceType)');
    _log.i('[Flutter mDNS] 📍 启动状态: lifecycle=$_appLifecycleState, isRunning=$_isRunning, Isolate: ${Isolate.current.debugName}');

    // 🔥 等待应用生命周期状态变为 'resumed'（确保应用完全准备好）
    // 如果 lifecycle 是 'unknown'，说明 HomeScreen.initState() 还没执行完成
    int waitCount = 0;
    while (_appLifecycleState == 'unknown' && waitCount < 50) {
      // 等待 100ms
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;

      if (waitCount % 10 == 1) {
        _log.d('[Flutter mDNS] [${_timestamp()}] ⏳ 等待 lifecycle 状态... ($waitCount/50)');
      }
    }

    if (_appLifecycleState == 'unknown') {
      _log.w('[Flutter mDNS] [${_timestamp()}] ⚠️ lifecycle 仍为 unknown，继续启动（可能 Headless 运行）');
    } else {
      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ lifecycle 状态已就绪: $_appLifecycleState (等待 ${waitCount * 100}ms)');
    }

    try {
      // 步骤 1: 注册服务（广播自己的存在）
      _log.i('[Flutter mDNS] [${_timestamp()}] 📝 步骤 1/2: 开始注册服务...');
      final registerSuccess = await registerService(name: name, port: port, serviceType: serviceType);

      if (!registerSuccess) {
        _log.e('[Flutter mDNS] [${_timestamp()}] ❌ 步骤 1 失败：服务注册失败，终止启动流程');
        return false;
      }

      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ 步骤 1 完成：服务注册成功');

      // 步骤 2: 开始浏览（发现其他设备）
      _log.i('[Flutter mDNS] [${_timestamp()}] 📝 步骤 2/2: 开始浏览服务...');

      // nsd 库期望服务类型格式: "_localp2p._tcp" (不带 .local. 后缀)
      String nsdServiceType = serviceType;
      if (nsdServiceType.endsWith('.local.')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 7);
      } else if (nsdServiceType.endsWith('.local')) {
        nsdServiceType = nsdServiceType.substring(0, nsdServiceType.length - 6);
      }

      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ 浏览服务类型: "$nsdServiceType"');

      _discovery = await nsd_pkg.startDiscovery(
        nsdServiceType,
        autoResolve: true,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          _log.e('[Flutter mDNS] [${_timestamp()}] ⏰ 浏览启动超时！等待时间: ${elapsed}ms');
          throw TimeoutException('mDNS 浏览启动超时 (${elapsed}ms)', const Duration(seconds: 10));
        },
      );

      _log.i('[Flutter mDNS] [${_timestamp()}] ✅ Discovery 对象创建成功: $_discovery');

      // 添加服务监听器
      _discovery!.addServiceListener((service, status) {
        _log.i('[Flutter mDNS] [${_timestamp()}] 🔔 服务状态变化: ${service.name} - $status');

        if (status == ServiceStatus.found) {
          _log.i('[Flutter mDNS] [${_timestamp()}] 📱 发现设备: ${service.name}');
          onDeviceFound(service);
        } else if (status == ServiceStatus.lost) {
          _log.i('[Flutter mDNS] [${_timestamp()}] 📱 设备离线: ${service.name}');
          onDeviceLost?.call(service.name ?? '');
        }
      });

      _log.i('[Flutter mDNS] [${_timestamp()}] 🎉 浏览启动成功，服务监听器已添加');

      _isRunning = true;
      final totalElapsed = DateTime.now().difference(startTime).inMilliseconds;

      _log.i('[Flutter mDNS] [${_timestamp()}] ✅✅✅ 完整启动成功！总耗时: ${totalElapsed}ms');
      _log.i('[Flutter mDNS] 📊 启动摘要: lifecycle=$_appLifecycleState, isRunning=$_isRunning, port=$port');

      return true;
    } on TimeoutException catch (e, stackTrace) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _log.e('[Flutter mDNS] [${_timestamp()}] ⏰ 启动超时 (耗时 ${elapsed}ms): $e', e, stackTrace);
      _log.e('[Flutter mDNS] 🔍 超时时状态: lifecycle=$_appLifecycleState, isRunning=$_isRunning');
      _isRunning = false;
      await _cleanup();
      return false;
    } catch (e, stackTrace) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _log.e('[Flutter mDNS] [${_timestamp()}] ❌ 启动失败 (耗时 ${elapsed}ms): $e', e, stackTrace);
      _log.e('[Flutter mDNS] 🔍 失败时状态: lifecycle=$_appLifecycleState, isRunning=$_isRunning');
      _isRunning = false;
      await _cleanup();
      return false;
    }
  }

  /// 清理资源
  Future<void> _cleanup() async {
    _log.i('[Flutter mDNS] [${_timestamp()}] 🧹 开始清理资源...');
    await _serviceListenerSubscription?.cancel();
    _serviceListenerSubscription = null;
    _discovery = null;
    _registration = null;
    _log.i('[Flutter mDNS] [${_timestamp()}] ✅ 清理完成');
  }
}
