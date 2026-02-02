//! Flutter Rust Bridge API
//!
//! 这一层定义了与 Flutter/Dart 交互的接口
//! flutter_rust_bridge 会自动生成对应的 Dart 代码

#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

use flutter_rust_bridge::frb;
use serde::{Serialize, Deserialize};
pub use mdns::UserInfo;

// 导入生成的 StreamSink 类型
use crate::frb_generated::StreamSink;
// 导入类型定义
use crate::types;

// ============================================================================
// 数据结构定义
// ============================================================================

/// P2P 事件（用于 FRB）
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct P2PBridgeEvent {
    /// 事件类型
    /// 1 = NodeDiscovered
    /// 2 = NodeExpired
    /// 3 = NodeVerified
    /// 4 = NodeOffline
    /// 5 = UserInfoReceived
    /// 6 = MessageReceived
    /// 7 = MessageSent
    /// 8 = PeerTyping
    /// 9 = Log (Rust 日志)
    /// 10 = ServiceStatusChanged (服务状态变化)
    pub event_type: i32,
    /// 事件数据 (JSON 字符串)
    pub data: String,
}

/// 类型别名，用于兼容 lib.rs 中的引用
pub type P2PEvent = P2PBridgeEvent;

/// 🔥 服务健康状态（用于 FRB）
#[derive(Clone, Serialize, Deserialize, Debug)]
pub enum ServiceHealthJson {
    Healthy,
    Degraded,
    Unhealthy,
}

/// 🔥 服务状态（用于 FRB）
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct ServiceStatusJson {
    pub name: String,
    pub health: ServiceHealthJson,
    pub is_running: bool,
    pub message: Option<String>,
}

/// 🔥 系统状态（用于 FRB）
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct SystemStatusJson {
    pub mdns_service: ServiceStatusJson,
    pub connection_service: ServiceStatusJson,
    pub connected_peers: usize,
    pub discovered_peers: usize,
}

/// 🔥 广播信息（用于 FRB）
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct BroadcastInfoJson {
    /// 本地 Peer ID
    pub peer_id: String,
    /// 设备名称
    pub device_name: String,
    /// 监听端口（TCP 端口）
    pub port: u16,
    /// 监听地址列表（IP 地址列表）
    pub addresses: Vec<String>,
}

/// 节点信息（用于 FRB）
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct P2PBridgeNodeInfo {
    pub peer_id: String,
    pub display_name: String,
    pub device_name: String,
    pub nickname: Option<String>,
    pub status: Option<String>,
    pub avatar_url: Option<String>,
    /// 节点地址列表（例如: ["/ip4/192.168.1.100/tcp/50001"]）
    pub addresses: Vec<String>,
    /// 协议版本（例如: "/localp2p/1.0.0"）
    pub protocol_version: String,
}

impl P2PBridgeNodeInfo {
    pub fn from_peer_id_and_info(peer_id: String, info: &mdns::UserInfo) -> Self {
        Self {
            peer_id,
            display_name: info.display_name(),
            device_name: info.device_name.clone(),
            nickname: info.nickname.clone(),
            status: info.status.clone(),
            avatar_url: info.avatar_url.clone(),
            addresses: Vec::new(),
            protocol_version: String::new(),
        }
    }

    /// 简化版本，只有基本信息（用于兼容旧代码）
    pub fn from_basic_info(peer_id: String, display_name: String, device_name: String) -> Self {
        Self {
            peer_id,
            display_name,
            device_name,
            nickname: None,
            status: None,
            avatar_url: None,
            addresses: Vec::new(),
            protocol_version: String::new(),
        }
    }
}

/// 类型别名，用于兼容 lib.rs 中的引用
pub type InternalNodeInfo = P2PBridgeNodeInfo;

// ============================================================================
// 初始化和生命周期
// ============================================================================

/// 检查 P2P 是否已初始化
#[frb(sync)]
pub fn p2p_is_initialized() -> bool {
    crate::internal_is_initialized()
}

/// 检查 P2P 服务是否正在运行
#[frb(sync)]
pub fn p2p_is_running() -> bool {
    crate::internal_is_running()
}

/// 检查 discovery 线程是否真的活着
///
/// 通过发送 Ping 命令来检查线程是否响应
/// 比 p2p_is_running() 更可靠，因为它实际检查线程状态
#[frb(sync)]
pub fn p2p_is_discovery_thread_alive() -> bool {
    crate::internal_is_discovery_thread_alive()
}

/// 重启 discovery 服务
///
/// 用于应用从后台恢复时，如果发现线程已死，重启它
/// 如果服务仍在运行，会先停止再重启
///
/// 🔄 改为异步：避免使用 block_on 导致 UI 卡顿
pub async fn p2p_restart_discovery() -> Result<(), String> {
    crate::internal_restart_discovery_async().await
}

/// 初始化 P2P 模块
///
/// # Arguments
/// * `device_name` - 本设备的显示名称
/// * `work_dir` - 工作目录路径（所有数据将存储在此目录下的子目录中）
///
/// # 目录结构
/// - `{work_dir}/data/` - 数据库文件
/// - `{work_dir}/logs/` - 日志文件
/// - `{work_dir}/certs/` - 证书文件（identity.key）
#[frb(sync)]
pub fn p2p_init(device_name: String, work_dir: String) -> Result<(), String> {
    crate::internal_init(device_name, work_dir)
}

pub fn p2p_start() -> Result<(), String> {
    crate::internal_start()
}

/// 停止 P2P 服务
#[frb(sync)]
pub fn p2p_stop() -> Result<(), String> {
    crate::internal_stop()
}

/// 清理资源
#[frb(sync)]
pub fn p2p_cleanup() {
    crate::internal_cleanup();
}

// ============================================================================
// 节点管理
// ============================================================================

/// 获取本地 Peer ID
#[frb(sync)]
pub fn p2p_get_local_peer_id() -> Result<String, String> {
    let runtime = crate::get_runtime().ok_or("No runtime")?;
    let peer_id = runtime.block_on(crate::internal_get_local_peer_id())?;
    Ok(peer_id)
}

/// 获取已发现的节点列表
///
/// 返回当前所有已发现的设备，包括在线和离线的设备
/// 可以用作刷新设备列表
#[frb(sync)]
pub fn p2p_get_devices() -> Result<Vec<P2PBridgeNodeInfo>, String> {
    // 记录刷新请求
    tracing::info!("🔄 [Bridge] Flutter 请求获取设备列表");

    // 获取当前节点列表
    crate::internal_get_nodes_sync()
        .map(|nodes| {
            nodes.into_iter().map(|n| P2PBridgeNodeInfo {
                peer_id: n.peer_id.clone(),
                display_name: n.display_name.clone(),
                device_name: n.device_name.clone(),
                nickname: n.nickname.clone(),
                status: n.status.clone(),
                avatar_url: n.avatar_url.clone(),
                addresses: n.addresses.clone(),
                protocol_version: n.protocol_version.clone(),
            }).collect()
        })
}

/// 刷新设备列表（别名，语义更清晰）
///
/// 功能同 p2p_get_devices，但语义上表示"刷新"操作
/// mDNS 会自动发现设备，此函数用于获取最新的设备列表状态
#[frb(sync)]
pub fn p2p_refresh_devices() -> Result<Vec<P2PBridgeNodeInfo>, String> {
    tracing::info!("🔄 [Bridge] Flutter 请求刷新设备列表");
    p2p_get_devices()
}

/// 主动触发设备发现刷新
///
/// 触发 mDNS 重新广播和重新发现，并尝试重新连接到所有已知节点
#[frb(sync)]
pub fn p2p_trigger_refresh() -> Result<(), String> {
    tracing::info!("🔄 [Bridge] Flutter 请求主动刷新");
    crate::internal_trigger_refresh_sync()
}

/// 获取设备名称
#[frb(sync)]
pub fn p2p_get_device_name() -> Result<String, String> {
    // 简单的值访问，不需要异步
    let runtime = crate::get_runtime().ok_or("No runtime")?;
    let device_name = runtime.block_on(crate::internal_get_device_name())?;
    Ok(device_name)
}

/// 获取已验证的节点列表
#[frb(sync)]
pub fn p2p_get_verified_nodes() -> Result<Vec<P2PBridgeNodeInfo>, String> {
    let nodes = crate::internal_get_nodes_sync()?;
    Ok(nodes.into_iter().map(|n| P2PBridgeNodeInfo {
        peer_id: n.peer_id,
        display_name: n.display_name,
        device_name: n.device_name,
        nickname: n.nickname,
        status: n.status,
        avatar_url: n.avatar_url,
        addresses: n.addresses,
        protocol_version: n.protocol_version,
    }).collect())
}

/// 🔥 获取系统状态
///
/// 返回当前所有服务的运行状态和健康状态
#[frb(sync)]
pub fn p2p_get_system_status() -> Result<SystemStatusJson, String> {
    crate::internal_get_system_status_sync()
}

/// 🔥 获取广播信息
///
/// 返回当前设备的广播信息（Peer ID、设备名称、监听端口、IP 地址列表）
///
/// 🔄 改为异步：避免锁竞争导致 UI 卡顿
#[frb(dart_async)]
pub async fn p2p_get_broadcast_info() -> Result<BroadcastInfoJson, String> {
    crate::internal_get_broadcast_info_async().await
}

// /// 获取所有节点的用户信息（包括昵称、状态等）
// pub async fn p2p_list_user_info() -> Result<Vec<P2PBridgeNodeInfo>, String> {
//     crate::internal_list_user_info().await
// }

// ============================================================================
// 消息功能
// ============================================================================

/// 发送消息给指定节点
///
/// # Arguments
/// * `target_peer_id` - 目标节点的 Peer ID
/// * `message` - 消息内容
///
/// 🔄 改为异步：避免使用 block_on 导致 UI 卡顿
pub async fn p2p_send_message(
    target_peer_id: String,
    message: String,
) -> Result<(), String> {
    crate::internal_send_message(target_peer_id, message).await
}

/// 广播消息给多个节点
///
/// # Arguments
/// * `target_peer_ids` - 目标节点的 Peer ID 列表
/// * `message` - 消息内容
///
/// 🔄 改为异步：避免使用 block_on 导致 UI 卡顿
pub async fn p2p_broadcast_message(
    target_peer_ids: Vec<String>,
    message: String,
) -> Result<(), String> {
    crate::internal_broadcast_message(target_peer_ids, message).await
}

// ============================================================================
// 数据库操作（新增）
// ============================================================================

/// 获取所有会话列表（在后台线程执行，不阻塞 UI）
pub async fn p2p_get_conversations() -> Result<Vec<types::ConversationJson>, String> {
    let runtime = crate::get_runtime().ok_or("No runtime")?;
    // 在后台线程中执行，避免阻塞 UI
    let handle = runtime.spawn_blocking(move || {
        runtime.block_on(crate::internal_get_conversations())
    });
    handle.await.map_err(|e| format!("Join error: {}", e))?
}

/// 通过 peer_id 获取消息列表（支持分页，在后台线程执行，不阻塞 UI）
///
/// # Arguments
/// * `peer_id` - 对方的 Peer ID
/// * `limit` - 每次获取的消息数量（推荐 20-50）
/// * `before_timestamp` - 获取此时间戳之前的消息（None 表示获取最新消息）
///
/// # 分页使用方式
/// ```dart
/// // 首次加载：获取最新的 30 条消息
/// final messages = await RustLib.instance.api.p2pGetMessagesByPeer(
///   peerId: "12D3KooW...",
///   limit: 30,
///   beforeTimestamp: null,
/// );
///
/// // 加载更多：使用最旧消息的时间戳
/// final oldestTimestamp = messages.last.timestamp;
/// final moreMessages = await RustLib.instance.api.p2pGetMessagesByPeer(
///   peerId: "12D3KooW...",
///   limit: 30,
///   beforeTimestamp: oldestTimestamp,
/// );
/// ```
pub async fn p2p_get_messages_by_peer(
    peer_id: String,
    limit: i32,
    before_timestamp: Option<i64>,
) -> Result<Vec<types::MessageJson>, String> {
    let runtime = crate::get_runtime().ok_or("No runtime")?;
    // 在后台线程中执行，避免阻塞 UI
    let handle = runtime.spawn_blocking(move || {
        runtime.block_on(crate::internal_get_messages_by_peer(peer_id, limit, before_timestamp))
    });
    handle.await.map_err(|e| format!("Join error: {}", e))?
}

/// 发送扩展消息（支持多种消息类型）
///
/// # Arguments
/// * `target_peer_id` - 目标节点的 Peer ID
/// * `message_type` - 消息类型 (1=文本, 2=图片, 3=视频, 4=文件, 5=音频, 6=红包, 7=系统)
/// * `content` - 消息内容（JSON 字符串）
/// * `extra` - 额外数据（可选，JSON 字符串）
pub async fn p2p_send_message_ex(
    target_peer_id: String,
    message_type: i32,
    content: String,
    extra: Option<String>,
) -> Result<String, String> {
    crate::internal_send_message_ex(target_peer_id, message_type, content, extra).await
}

/// 标记消息为已读
///
/// # Arguments
/// * `conversation_id` - 会话 ID
/// * `message_ids` - 消息 ID 列表
pub async fn p2p_mark_messages_read(
    conversation_id: String,
    message_ids: Vec<String>,
) -> Result<(), String> {
    crate::internal_mark_messages_read(conversation_id, message_ids).await
}

/// 删除消息
///
/// # Arguments
/// * `message_id` - 消息 ID
pub async fn p2p_delete_message(message_id: String) -> Result<(), String> {
    crate::internal_delete_message(message_id).await
}

/// 撤回消息
///
/// # Arguments
/// * `message_id` - 消息 ID
pub async fn p2p_revoke_message(message_id: String) -> Result<(), String> {
    crate::internal_revoke_message(message_id).await
}

/// 清空聊天记录
///
/// # Arguments
/// * `conversation_id` - 会话 ID
pub async fn p2p_clear_conversation(conversation_id: String) -> Result<(), String> {
    crate::internal_clear_conversation(conversation_id).await
}

// ============================================================================
// 文件操作（新增）
// ============================================================================

/// 注册文件（发送前调用）
///
/// # Arguments
/// * `file_name` - 文件名
/// * `file_size` - 文件大小（字节）
/// * `mime_type` - MIME 类型
/// * `local_path` - 本地存储路径
pub async fn p2p_register_file(
    file_name: String,
    file_size: i64,
    mime_type: String,
    local_path: String,
) -> Result<String, String> {
    crate::internal_register_file(file_name, file_size, mime_type, local_path).await
}

/// 获取文件元数据
///
/// # Arguments
/// * `file_id` - 文件 ID
pub async fn p2p_get_file_info(file_id: String) -> Result<types::FileInfoJson, String> {
    crate::internal_get_file_info(file_id).await
}

// ============================================================================
// 事件功能
// ============================================================================

/// 设置事件流接收器（用于 Stream 模式）
///
/// 调用此函数后，Rust 会将事件推送到 Stream，Flutter 端可以订阅这个 Stream
/// 这是推荐的方式，比轮询更高效
#[frb(sync)]
pub fn p2p_set_event_stream(stream_sink: StreamSink<P2PBridgeEvent>) -> Result<(), String> {
    crate::set_event_stream_sink(stream_sink)
}

/// 轮询事件（返回所有待处理的事件）
///
/// @deprecated 推荐使用 p2p_set_event_stream + p2p_start_with_stream 代替
/// Flutter 应该定期调用此函数来获取事件
/// 返回的事件按时间顺序排列
#[frb(sync)]
pub fn p2p_poll_events() -> Vec<P2PBridgeEvent> {
    crate::poll_events()
}

// ============================================================================
// 外部 mDNS 发现（Flutter mDNS 辅助）
// ============================================================================

/// 报告外部发现的设备（由 Flutter mDNS 发现）
///
/// 当 Flutter 的 mDNS 辅助服务发现设备时，调用此方法通知 Rust 层
/// Rust 层会尝试连接到该设备
///
/// # Arguments
/// * `peer_id` - 对端的 Peer ID
/// * `address` - 对端的地址（例如 "/ip4/192.168.1.100/tcp/50001"）
///
/// # Example
/// ```dart
/// RustLib.instance.api.p2pReportExternalDiscovery(
///     peerId: "12D3KooW...",
///     address: "/ip4/192.168.1.100/tcp/50001",
/// );
/// ```
#[frb(sync)]
pub fn p2p_report_external_discovery(
    peer_id: String,
    address: String,
) -> Result<(), String> {
    tracing::info!("📡 [FFI] Flutter mDNS 发现设备: {} at {}", peer_id, address);
    crate::internal_report_external_discovery(peer_id, address)
}

/// 报告多个外部发现的设备
///
/// 批量报告设备，减少 FFI 调用次数
#[frb(sync)]
pub fn p2p_report_external_discoveries(
    discoveries: Vec<ExternalDiscovery>,
) -> Result<(), String> {
    tracing::info!("📡 [FFI] Flutter mDNS 批量报告 {} 个设备", discoveries.len());
    crate::internal_report_external_discoveries(discoveries)
}

/// 外部发现的设备信息
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct ExternalDiscovery {
    pub peer_id: String,
    pub address: String,
}

/// 报告外部发现的设备离线
///
/// 当 Flutter 的 mDNS 辅助服务检测到设备离线时，调用此方法通知 Rust 层
#[frb(sync)]
pub fn p2p_report_external_device_lost(
    peer_id: String,
) -> Result<(), String> {
    tracing::info!("📡 [FFI] Flutter mDNS 设备离线: {}", peer_id);
    crate::internal_report_external_device_lost(peer_id)
}
