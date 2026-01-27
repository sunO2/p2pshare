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

/// 初始化 P2P 模块
///
/// # Arguments
/// * `device_name` - 本设备的显示名称
#[frb(sync)]
pub fn p2p_init(device_name: String) -> Result<(), String> {
    crate::internal_init(device_name)
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
    // 简单的值访问，不需要异步
    let runtime = crate::get_runtime().ok_or("No runtime")?;
    let peer_id = runtime.block_on(crate::internal_get_local_peer_id())?;
    Ok(peer_id)
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
#[frb(sync)]
pub fn p2p_send_message(
    target_peer_id: String,
    message: String,
) -> Result<(), String> {
    crate::internal_send_message_sync(target_peer_id, message)
}

/// 广播消息给多个节点
///
/// # Arguments
/// * `target_peer_ids` - 目标节点的 Peer ID 列表
/// * `message` - 消息内容
#[frb(sync)]
pub fn p2p_broadcast_message(
    target_peer_ids: Vec<String>,
    message: String,
) -> Result<(), String> {
    crate::internal_broadcast_message_sync(target_peer_ids, message)
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
