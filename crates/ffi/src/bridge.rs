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
    pub event_type: i32,
    /// 事件数据 (JSON 字符串)
    pub data: String,
}

/// 类型别名，用于兼容 lib.rs 中的引用
pub type P2PEvent = P2PBridgeEvent;

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
/// * `identity_path` - 密钥对保存路径（空字符串表示不持久化）
#[frb(sync)]
pub fn p2p_init(device_name: String, identity_path: String) -> Result<(), String> {
    crate::internal_init(device_name, identity_path)
}

/// 启动 P2P 服务
#[frb(sync)]
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
