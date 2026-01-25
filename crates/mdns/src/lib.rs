//! mDNS 服务发现模块
//!
//! 基于 libp2p 的 mDNS 实现，用于局域网内的服务发布和发现。

use thiserror::Error;

pub mod config;
pub mod discovery;
pub mod publisher;
pub mod node;
pub mod managed_discovery;
pub mod user_info;
pub mod chat;

pub use config::{MdnsConfig, ServiceInfo};
pub use discovery::{MdnsDiscovery, DiscoveredPeer, DiscoveredEvent};
pub use publisher::MdnsPublisher;
pub use node::{VerifiedNode, NodeManager, NodeManagerConfig};
pub use managed_discovery::{
    ManagedDiscovery,
    DiscoveryEvent as ManagedDiscoveryEvent,
    NodeHealth,
    HealthStatus,
    HealthCheckConfig,
};
pub use user_info::UserInfo;

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
