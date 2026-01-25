//! 聊天扩展 trait
//!
//! 定义扩展 ManagedDiscovery 的接口，使其支持聊天功能。

use super::message::{ChatMessage, ChatError};
use super::manager::ChatManager;
use libp2p::PeerId;
use std::sync::Arc;

/// 聊天扩展 trait
///
/// 为 ManagedDiscovery 提供可选的聊天能力扩展。
///
/// # 示例
///
/// ```no_run
/// use mdns::{ManagedDiscovery, ChatExtension};
///
/// # async fn example(mut discovery: ManagedDiscovery) -> Result<(), Box<dyn std::error::Error>> {
/// // 启用聊天功能
/// discovery.enable_chat().await?;
///
/// // 发送消息
/// let peer_id = "12D3KooW...".parse()?;
/// let message = ChatMessage::text("Hello!".to_string());
/// discovery.send_message(peer_id, message).await?;
///
/// // 广播消息（一对多）
/// let targets = vec![peer_id];
/// discovery.broadcast_message(targets, message).await?;
/// # Ok(())
/// # }
/// ```
#[async_trait::async_trait]
pub trait ChatExtension {
    /// 启用聊天功能
    ///
    /// 初始化 ChatManager 并准备接收聊天消息。
    ///
    /// # 错误
    ///
    /// 返回错误如果聊天功能已经启用或初始化失败。
    async fn enable_chat(&mut self) -> Result<(), ChatError>;

    /// 发送消息给指定节点
    ///
    /// # 参数
    ///
    /// * `target` - 目标节点的 Peer ID
    /// * `message` - 要发送的消息
    ///
    /// # 错误
    ///
    /// - `ChatError::NotEnabled` - 聊天功能未启用
    /// - `ChatError::NodeNotVerified` - 目标节点未验证
    /// - `ChatError::SendFailed` - 发送失败
    async fn send_message(&mut self, target: PeerId, message: ChatMessage) -> Result<(), ChatError>;

    /// 广播消息给多个节点（一对多）
    ///
    /// 并发发送消息给所有目标节点。
    ///
    /// # 参数
    ///
    /// * `targets` - 目标节点的 Peer ID 列表
    /// * `message` - 要发送的消息
    ///
    /// # 错误
    ///
    /// - `ChatError::NotEnabled` - 聊天功能未启用
    /// - `ChatError::PartialFailure` - 部分目标发送失败
    async fn broadcast_message(&mut self, targets: Vec<PeerId>, message: ChatMessage) -> Result<(), ChatError>;

    /// 获取聊天管理器
    ///
    /// 返回 ChatManager 的引用，如果聊天功能已启用。
    fn chat_manager(&self) -> Option<Arc<ChatManager>>;

    /// 检查聊天功能是否已启用
    fn is_chat_enabled(&self) -> bool {
        self.chat_manager().is_some()
    }
}

/// 聊天事件
///
/// 由 ChatManager 产生，通知上层应用聊天相关事件。
#[derive(Debug, Clone)]
pub enum ChatEvent {
    /// 收到消息
    MessageReceived {
        /// 发送者的 Peer ID
        from: PeerId,
        /// 收到的消息
        message: ChatMessage,
    },

    /// 消息发送成功
    MessageSent {
        /// 目标节点的 Peer ID
        to: PeerId,
        /// 消息 ID
        message_id: String,
    },

    /// 消息已确认
    MessageAcknowledged {
        /// 确认者的 Peer ID
        from: PeerId,
        /// 被确认的消息 ID
        message_id: String,
    },

    /// 对方正在输入
    PeerTyping {
        /// 对方的 Peer ID
        from: PeerId,
        /// 是否正在输入
        is_typing: bool,
    },

    /// 消息发送失败
    MessageFailed {
        /// 目标节点的 Peer ID
        to: PeerId,
        /// 消息 ID
        message_id: String,
        /// 错误原因
        error: String,
    },

    /// 会话已建立
    SessionEstablished {
        /// 对方的 Peer ID
        peer_id: PeerId,
    },

    /// 会话已关闭
    SessionClosed {
        /// 对方的 Peer ID
        peer_id: PeerId,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chat_event_message_received() {
        let event = ChatEvent::MessageReceived {
            from: "12D3KooWABCDEFGHIJKLMNOPQRSTUVWXYZ".parse().unwrap(),
            message: ChatMessage::text("Hello".to_string()),
        };

        match event {
            ChatEvent::MessageReceived { from, message } => {
                assert!(from.to_string().starts_with("12D3"));
                assert_eq!(message, ChatMessage::text("Hello".to_string()));
            }
            _ => panic!("Expected MessageReceived event"),
        }
    }

    #[test]
    fn test_chat_event_peer_typing() {
        let event = ChatEvent::PeerTyping {
            from: "12D3KooWABCDEFGHIJKLMNOPQRSTUVWXYZ".parse().unwrap(),
            is_typing: true,
        };

        match event {
            ChatEvent::PeerTyping { from, is_typing } => {
                assert!(is_typing);
                assert!(from.to_string().starts_with("12D3"));
            }
            _ => panic!("Expected PeerTyping event"),
        }
    }
}
