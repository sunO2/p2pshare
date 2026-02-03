import 'package:get/get.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import '../../../bridge/frb_generated.dart';
import '../../../bridge/types.dart';
import '../../services/log_service.dart';

/// 会话列表控制器
///
/// 管理：会话列表、加载状态、未读消息、刷新
class ConversationController extends GetxController {
  // ========== 状态变量 ==========

  /// 会话列表
  final conversations = <ConversationJson>[].obs;

  /// 是否正在加载
  final isLoading = true.obs;

  /// 错误信息
  final Rxn<String> error = Rxn<String>();

  // ========== 依赖注入 ==========

  final LogService _log = Get.find<LogService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[ConversationController] onInit');
    loadConversations();
  }

  @override
  void onReady() {
    super.onReady();
    _log.i('[ConversationController] onReady');
  }

  @override
  void onClose() {
    _log.i('[ConversationController] onClose');
    super.onClose();
  }

  // ========== 数据加载 ==========

  /// 加载会话列表
  Future<void> loadConversations() async {
    _log.i('[ConversationController] 加载会话列表');
    isLoading.value = true;
    error.value = null;

    try {
      final result = await RustLib.instance.api.localp2PFfiBridgeP2PGetConversations();
      conversations.assignAll(result);
      _log.i('[ConversationController] 加载成功: ${result.length} 个会话');
    } catch (e, stackTrace) {
      _log.e('[ConversationController] 加载失败: $e', e, stackTrace);
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  /// 刷新会话列表
  Future<void> refreshConversations() async {
    await loadConversations();
  }

  // ========== 排序后的会话列表 ==========

  /// 按最后消息时间排序的会话列表
  List<ConversationJson> get sortedConversations {
    final list = List<ConversationJson>.from(conversations);
    list.sort((a, b) {
      final timeA = a.lastMessageTime?.toInt() ?? 0;
      final timeB = b.lastMessageTime?.toInt() ?? 0;
      return timeB.compareTo(timeA);
    });
    return list;
  }

  // ========== 导航操作 ==========

  /// 打开聊天
  void openChat(ConversationJson conversation) {
    _log.i('[ConversationController] 打开聊天: peerId=${conversation.peerId}');
    Get.toNamed(
      '/chat',
      parameters: {
        'peerId': conversation.peerId,
        'peerName': conversation.peerName ?? conversation.peerId,
      },
    )?.then((_) {
      // 从聊天页面返回时，刷新会话列表
      _log.i('[ConversationController] 返回，刷新会话列表');
      loadConversations();
    });
  }

  // ========== 工具方法 ==========

  /// 格式化时间
  String formatTime(PlatformInt64? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final msgTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
    final diff = now.difference(msgTime);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${msgTime.month}/${msgTime.day}';
    }
  }
}
