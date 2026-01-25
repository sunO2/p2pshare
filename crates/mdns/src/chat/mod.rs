//! 聊天模块
//!
//! 提供局域网内的点对点聊天功能，支持一对一和一对多聊天。
//!
//! # 模块化设计
//!
//! 本模块作为 mdns crate 的扩展，通过 `ChatExtension` trait 为 `ManagedDiscovery` 添加聊天能力。
//!
//! # 架构
//!
//! - [`message`] - 消息类型定义和序列化
//! - [`traits`] - ChatExtension trait 定义
//! - [`manager`] - ChatManager 实现（统一管理聊天会话）
//! - [`behaviour`] - ChatSession 和 Stream 管理
//!
//! # 示例
//!
//! ```no_run
//! use mdns::{ManagedDiscovery, ChatExtension, ChatMessage};
//! use libp2p::PeerId;
//!
//! # async fn example(mut discovery: ManagedDiscovery) -> Result<(), Box<dyn std::error::Error>> {
//! // 启用聊天功能
//! discovery.enable_chat().await?;
//!
//! // 发送消息
//! let peer_id: PeerId = "12D3KooW...".parse()?;
//! let message = ChatMessage::text("Hello!".to_string());
//! discovery.send_message(peer_id, message).await?;
//! # Ok(())
//! # }
//! ```

pub mod message;
pub mod traits;
pub mod manager;
pub mod codec;

// behaviour 将在后续阶段实现
// pub mod behaviour;

// 公共 API 导出
pub use message::{
    ChatMessage, TextMessage, TypingIndicator, MessageAck,
    ChatError, CHAT_PROTOCOL,
};
pub use traits::{ChatExtension, ChatEvent};
pub use manager::{ChatManager, ChatSession};
pub use codec::{ChatCodec, ChatProtocol, ChatRequest, ChatResponse};

// 当实现完成后，导出这些类型
// pub use behaviour::ChatSession;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chat_protocol_const() {
        assert_eq!(CHAT_PROTOCOL, "/localp2p/chat/1.0.0");
        assert_eq!(ChatProtocol.as_ref(), "/localp2p/chat/1.0.0");
    }

    #[test]
    fn test_chat_message_factory() {
        let msg = ChatMessage::text("Hello".to_string());
        assert!(matches!(msg, ChatMessage::Text(_)));
    }

    #[test]
    fn test_chat_error_display() {
        let err = ChatError::NotEnabled;
        assert_eq!(err.to_string(), "聊天功能未启用");

        let err = ChatError::NodeNotVerified("peer123".to_string());
        assert!(err.to_string().contains("peer123"));
    }
}
