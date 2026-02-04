// 服务启动完成事件使用示例
//
// 此文件展示如何使用 onServiceReady 事件来确保依赖服务的功能
// 在服务完全启动后才执行。
//
// 🔥 事件流：
// Rust 连接服务启动完成 -> Rust 发送 SERVICE_READY 事件 ->
// Flutter 收到事件 -> Flutter 通过 EventBus 广播

/// 示例 1: 基本监听
///
/// 监听所有服务启动完成事件
///
/// 由于 EventBus 有最后事件缓存，新订阅者会立即收到当前状态。
/// 如果服务已经启动完成，会立即收到事件；如果服务还没启动完成，
/// 则会在服务启动完成后收到事件。
///
/// ```dart
/// final subscription = P2PEventBus.instance.onServiceReady.listen((event) {
///   print('🎉 所有服务已启动完成！');
///   print('Peer ID: ${event.getData<String>('local_peer_id')}');
///   print('设备名称: ${event.getData<String>('device_name')}');
///   print('端口: ${event.getData<int>('port')}');
///   print('服务状态: ${event.getData<Map>('services')}');
///
///   // 在这里执行依赖服务的初始化操作
///   // 例如：开始设备发现、初始化聊天、同步数据等
/// });
///
/// // 不再需要监听时取消订阅
/// // subscription.cancel();
/// ```

/// 示例 2: 使用 onWithLatest（推荐）
///
/// onWithLatest 会立即发送当前状态，然后继续监听新事件
///
/// 这种方式适合需要获取当前状态的场景，例如页面初始化时。
///
/// ```dart
/// final subscription = P2PEventBus.instance.onWithLatest(
///   peerId: '_system_',
///   type: 'service_ready',
/// ).listen((event) {
///   final isReady = event.getData<bool>('services.connection') ?? false;
///   if (isReady) {
///     print('✅ 服务已就绪，可以安全调用 P2P 功能');
///
///     // 安全地调用依赖服务的功能
///     // 例如：
///     // - P2PManager.instance.getVerifiedNodes();
///     // - P2PManager.instance.startChat(peerId);
///     // - FlutterMdnsService.instance.browse();
///   }
/// });
/// ```

/// 示例 3: 只等待一次（一次性初始化）
///
/// 使用 .take(1) 或 .once 只在服务启动完成时执行一次
///
/// ```dart
/// P2PEventBus.instance.onServiceReady.take(1).listen((event) {
///   print('⚡ 服务首次启动完成，执行一次性初始化');
///
///   // 执行只需要执行一次的初始化操作
///   // 例如：预加载数据、建立连接等
/// });
///
/// // 或者使用 once 方法：
/// P2PEventBus.instance.once(
///   peerId: '_system_',
///   type: 'service_ready',
/// ).listen((event) {
///   print('⚡ 服务启动完成（使用 once 方法）');
/// });
/// ```

/// 示例 4: 在 Widget 中使用
///
/// ```dart
/// class MyWidget extends StatefulWidget {
///   @override
///   _MyWidgetState createState() => _MyWidgetState();
/// }
///
/// class _MyWidgetState extends State<MyWidget> {
///   bool _serviceReady = false;
///   late P2PEventSubscription subscription;
///
///   @override
///   void initState() {
///     super.initState();
///
///     // 监听服务启动完成事件
///     subscription = P2PEventBus.instance.onWithLatest(
///       peerId: '_system_',
///       type: 'service_ready',
///     ).listen((event) {
///       if (mounted) {
///         setState(() {
///           _serviceReady = true;
///         });
///       }
///     });
///   }
///
///   @override
///   void dispose() {
///     subscription.cancel();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     if (!_serviceReady) {
///       return Center(child: CircularProgressIndicator());
///     }
///
///     // 服务已就绪，显示需要依赖服务的 UI
///     return YourServiceDependentWidget();
///   }
/// }
/// ```

/// 示例 5: 检查当前状态
///
/// 使用 currentState 检查服务是否已经启动完成
///
/// ```dart
/// final subscription = P2PEventBus.instance.onWithLatest(
///   peerId: '_system_',
///   type: 'service_ready',
/// ).listen((event) {
///   // 检查当前状态
///   final currentData = subscription.currentData;
///   if (currentData != null) {
///     final services = currentData['services'] as Map?;
///     final connectionReady = services?['connection'] == true;
///
///     print('连接服务状态: ${connectionReady ? "✅" : "❌"}');
///   }
/// });
/// ```

/// 示例 6: 获取服务信息
///
/// 从事件数据中获取详细的运行时信息
///
/// ```dart
/// P2PEventBus.instance.onWithLatest(
///   peerId: '_system_',
///   type: 'service_ready',
/// ).listen((event) {
///   // 获取本地 Peer ID
///   final localPeerId = event.getData<String>('local_peer_id');
///   print('本地 Peer ID: $localPeerId');
///
///   // 获取设备名称
///   final deviceName = event.getData<String>('device_name');
///   print('设备名称: $deviceName');
///
///   // 获取监听端口
///   final port = event.getData<int>('port');
///   print('监听端口: $port');
///
///   // 获取所有监听地址
///   final addresses = event.getData<List>('addresses') as List?;
///   if (addresses != null) {
///     print('监听地址:');
///     for (var addr in addresses) {
///       print('  - $addr');
///     }
///   }
///
///   // 获取时间戳
///   final timestamp = event.getData<String>('timestamp');
///   print('启动时间: $timestamp');
/// });
/// ```

/// 示例 7: 条件执行
///
/// 只有在服务启动完成后才执行某些操作
///
/// ```dart
/// P2PEventBus.instance.onWithLatest(
///   peerId: '_system_',
///   type: 'service_ready',
/// ).listen((event) {
///   // 检查服务是否就绪
///   if (event.getData<bool>('services.connection') == true) {
///     // 执行需要连接服务的操作
///     print('可以安全调用连接服务 API');
///
///     // 例如：获取已验证的节点列表
///     // final nodes = P2PManager.instance.getVerifiedNodes();
///     // for (var node in nodes) {
///     //   print('节点: ${node.peerId}');
///     // }
///   }
/// });
/// ```

/// 事件数据结构
///
/// SERVICE_READY 事件包含以下数据：
///
/// ```json
/// {
///   "timestamp": "2026-02-04T17:23:21.123456",
///   "local_peer_id": "12D3KooW...",
///   "device_name": "可爱火箭738",
///   "port": 42373,
///   "addresses": ["10.244.191.71", "240e:47e:2c50:..."],
///   "services": {
///     "connection": true  // Rust 连接服务已启动
///   },
///   "message": "所有服务已完全启动"
/// }
/// ```
