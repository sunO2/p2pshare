import 'package:get/get.dart';
import '../../presentation/views/home/home_view.dart';
import '../../presentation/bindings/home_binding.dart';
import '../../presentation/views/devices/device_list_view.dart';
import '../../presentation/bindings/device_binding.dart';
import '../../presentation/views/conversations/conversation_list_view.dart';
import '../../presentation/bindings/conversation_binding.dart';
import '../../presentation/views/chat/chat_view.dart';
import '../../presentation/bindings/chat_binding.dart';
import '../../presentation/views/settings/settings_view.dart';
import '../../presentation/bindings/settings_binding.dart';
import '../../presentation/views/device_detail/device_detail_view.dart';
import '../../presentation/bindings/device_detail_binding.dart';
import '../../presentation/views/debug/logs_viewer_view.dart';
import '../../presentation/bindings/logs_viewer_binding.dart';
import '../../presentation/views/peer_settings/peer_settings_view.dart';
import '../../presentation/bindings/peer_settings_binding.dart';

/// 路由名称常量
class Routes {
  static const home = '/home';
  static const deviceList = '/devices';
  static const conversationList = '/conversations';
  static const chat = '/chat';
  static const settings = '/settings';
  static const deviceDetail = '/device-detail';
  static const logsViewer = '/logs-viewer';
  static const peerSettings = '/peer-settings';
}

/// GetX 路由配置
///
/// 定义应用的所有路由页面
class AppPages {
  /// 初始路由
  static const String initial = Routes.home;

  /// 路由列表
  static final routes = [
    // 首页（主框架，包含底部导航）
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      transition: Transition.fadeIn,
    ),

    // 设备列表（使用新的 GetX MVVM 架构）
    GetPage(
      name: Routes.deviceList,
      page: () => const DeviceListView(),
      binding: DeviceBinding(),
      transition: Transition.fadeIn,
    ),

    // 会话列表（使用新的 GetX MVVM 架构）
    GetPage(
      name: Routes.conversationList,
      page: () => const ConversationListView(),
      binding: ConversationBinding(),
      transition: Transition.fadeIn,
    ),

    // 聊天页面（使用新的 GetX MVVM 架构）
    GetPage(
      name: Routes.chat,
      page: () => const ChatView(),
      binding: ChatBinding(),
      transition: Transition.rightToLeft,
    ),

    // 设置页面（使用新的 GetX MVVM 架构）
    GetPage(
      name: Routes.settings,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
      transition: Transition.fadeIn,
    ),

    // 设备详情页面（使用新的 GetX MVVM 架构）
    GetPage(
      name: Routes.deviceDetail,
      page: () => const DeviceDetailView(),
      binding: DeviceDetailBinding(),
      transition: Transition.rightToLeft,
    ),

    // 日志查看器页面
    GetPage(
      name: Routes.logsViewer,
      page: () => const LogsViewerView(),
      binding: LogsViewerBinding(),
      transition: Transition.rightToLeft,
    ),

    // 设备设置页面
    GetPage(
      name: Routes.peerSettings,
      page: () => const PeerSettingsView(),
      binding: PeerSettingsBinding(),
      transition: Transition.rightToLeft,
    ),
  ];
}
