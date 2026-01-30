//! mDNS 服务发现模块
//!
//! 基于 mdns-sd 的 mDNS 服务发现实现，用于局域网内的设备发现和连接。
//!
//! ## 架构
//!
//! - **mdns_discovery**: mDNS 服务发现（使用 mdns-sd 库，同时支持广播和浏览）
//! - **connection_service**: 连接服务（使用 libp2p Swarm，处理 TCP 连接、Identify、Ping、聊天）
//! - **managed_discovery**: 管理式发现（兼容层，集成 identify 验证、ping 心跳、用户信息交换）
//! - **p2p_manager**: P2P 管理器（统一管理 mDNS 发现和连接服务）

use thiserror::Error;

/// 全局日志回调函数类型
/// 参数：(level, target, message)
pub type LogCallback = fn(&'static str, &'static str, String);

/// 全局日志回调（由 FFI 层设置）
static mut LOG_CALLBACK: Option<LogCallback> = None;

/// 设置全局日志回调
///
/// # Safety
/// 此函数应在初始化时调用一次
pub unsafe fn set_log_callback(callback: LogCallback) {
    LOG_CALLBACK = Some(callback);
}

/// 发送日志到回调（如果已设置）
pub fn send_log(level: &'static str, target: &'static str, message: String) {
    unsafe {
        if let Some(callback) = LOG_CALLBACK {
            callback(level, target, message);
        }
    }
}

pub mod config;
pub mod node;
pub mod managed_discovery;
pub mod user_info;
pub mod chat;
pub mod identity;
pub mod events;
pub mod connection_service;
pub mod p2p_manager;
pub mod mdns_discovery;

pub use config::{MdnsConfig, ServiceInfo};
pub use node::{VerifiedNode, NodeManager, NodeManagerConfig, NodeStatus};
pub use connection_service::{ConnectionService, ConnectionServiceConfig, set_chat_event_callback};
pub use p2p_manager::{P2PManager, P2PManagerConfig};
pub use mdns_discovery::{MdnsServiceDiscovery, MdnsDiscoveryError, DeviceMetadata};
pub use managed_discovery::{
    ManagedDiscovery,
    DiscoveryEvent as ManagedDiscoveryEvent,
    NodeHealth,
    HealthStatus,
    HealthCheckConfig,
};
pub use user_info::UserInfo;
pub use identity::IdentityManager;
pub use events::{DiscoveryEvent, ConnectionEvent};

// 聊天模块公共 API
pub use chat::{
    ChatMessage, TextMessage, TypingIndicator, MessageAck,
    ChatExtension, ChatEvent, ChatError, ChatManager, ChatSession,
};

/// mDNS 相关错误
#[derive(Error, Debug)]
pub enum MdnsError {
    #[error("IO 错误: {0}")]
    Io(#[from] std::io::Error),

    #[error("Swarm 构建失败: {0}")]
    SwarmBuild(String),

    #[error("服务已停止")]
    Stopped,
}

/// mDNS 服务结果类型
pub type Result<T> = std::result::Result<T, MdnsError>;
