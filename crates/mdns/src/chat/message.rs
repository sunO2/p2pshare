//! 聊天消息协议
//!
//! 定义聊天功能使用的消息类型和序列化格式。

use serde::{Deserialize, Serialize};

/// 聊天协议名称
pub const CHAT_PROTOCOL: &str = "/localp2p/chat/1.0.0";

/// 聊天消息类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ChatMessage {
    /// 文本消息
    Text(TextMessage),
    /// 正在输入提示
    TypingIndicator(TypingIndicator),
    /// 消息确认
    Ack(MessageAck),
}

impl ChatMessage {
    /// 创建文本消息
    pub fn text(content: String) -> Self {
        Self::Text(TextMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(), // 需要在发送时设置
            content,
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 获取消息 ID
    pub fn id(&self) -> Option<&str> {
        match self {
            Self::Text(t) => Some(&t.id),
            Self::Ack(a) => Some(&a.message_id),
            Self::TypingIndicator(_) => None,
        }
    }

    /// 获取发送者 Peer ID
    pub fn sender_peer_id(&self) -> Option<&str> {
        match self {
            Self::Text(t) => Some(&t.sender_peer_id),
            Self::TypingIndicator(t) => Some(&t.sender_peer_id),
            Self::Ack(_) => None,
        }
    }

    /// 序列化消息为字节数组
    pub fn encode(&self) -> Result<Vec<u8>, ChatError> {
        serde_json::to_vec(self)
            .map_err(|e| ChatError::Serialization(e.to_string()))
    }

    /// 从字节数组反序列化消息
    pub fn decode(data: &[u8]) -> Result<Self, ChatError> {
        serde_json::from_slice(data)
            .map_err(|e| ChatError::Deserialization(e.to_string()))
    }
}

/// 文本消息
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TextMessage {
    /// 消息唯一 ID（UUID）
    pub id: String,

    /// 发送者的 Peer ID
    pub sender_peer_id: String,

    /// 消息内容
    pub content: String,

    /// Unix 时间戳（毫秒）
    pub timestamp: i64,

    /// 回复的消息 ID（可选）
    pub reply_to: Option<String>,
}

impl TextMessage {
    /// 设置发送者 Peer ID
    pub fn with_sender(mut self, peer_id: String) -> Self {
        self.sender_peer_id = peer_id;
        self
    }

    /// 设置为回复消息
    pub fn with_reply_to(mut self, message_id: String) -> Self {
        self.reply_to = Some(message_id);
        self
    }
}

/// 正在输入提示
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TypingIndicator {
    /// 发送者的 Peer ID
    pub sender_peer_id: String,

    /// 是否正在输入
    pub is_typing: bool,
}

impl TypingIndicator {
    /// 创建新的输入指示器
    pub fn new(sender_peer_id: String, is_typing: bool) -> Self {
        Self {
            sender_peer_id,
            is_typing,
        }
    }
}

/// 消息确认
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MessageAck {
    /// 被确认的消息 ID
    pub message_id: String,

    /// 是否已接收
    pub received: bool,

    /// Unix 时间戳（毫秒）
    pub timestamp: i64,
}

impl MessageAck {
    /// 创建新的消息确认
    pub fn new(message_id: String, received: bool) -> Self {
        Self {
            message_id,
            received,
            timestamp: chrono::Utc::now().timestamp_millis(),
        }
    }
}

/// 聊天错误类型
#[derive(Debug, Clone, thiserror::Error)]
pub enum ChatError {
    /// 序列化错误
    #[error("序列化错误: {0}")]
    Serialization(String),

    /// 反序列化错误
    #[error("反序列化错误: {0}")]
    Deserialization(String),

    /// 聊天功能未启用
    #[error("聊天功能未启用")]
    NotEnabled,

    /// 节点未验证
    #[error("节点未验证: {0}")]
    NodeNotVerified(String),

    /// 发送失败
    #[error("发送失败: {0}")]
    SendFailed(String),

    /// 接收失败
    #[error("接收失败: {0}")]
    ReceiveFailed(String),

    /// 会话不存在
    #[error("会话不存在: {0}")]
    SessionNotFound(String),

    /// 部分失败（一对多广播时）
    #[error("部分失败: {0} 个目标失败")]
    PartialFailure(usize),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_text_message_creation() {
        let msg = ChatMessage::text("Hello, world!".to_string());

        match msg {
            ChatMessage::Text(t) => {
                assert!(!t.id.is_empty());
                assert_eq!(t.content, "Hello, world!");
                assert!(t.timestamp > 0);
                assert!(t.reply_to.is_none());
            }
            _ => panic!("Expected Text message"),
        }
    }

    #[test]
    fn test_message_serialization() {
        let original = ChatMessage::text("Test message".to_string());

        let encoded = original.encode().unwrap();
        let decoded = ChatMessage::decode(&encoded).unwrap();

        assert_eq!(original, decoded);
    }

    #[test]
    fn test_typing_indicator() {
        let indicator = TypingIndicator::new("peer123".to_string(), true);
        assert_eq!(indicator.sender_peer_id, "peer123");
        assert!(indicator.is_typing);
    }

    #[test]
    fn test_message_ack() {
        let ack = MessageAck::new("msg123".to_string(), true);
        assert_eq!(ack.message_id, "msg123");
        assert!(ack.received);
        assert!(ack.timestamp > 0);
    }

    #[test]
    fn test_text_message_with_sender() {
        let msg = TextMessage {
            id: "msg123".to_string(),
            sender_peer_id: String::new(),
            content: "Hello".to_string(),
            timestamp: 0,
            reply_to: None,
        };

        let with_sender = msg.with_sender("peer456".to_string());
        assert_eq!(with_sender.sender_peer_id, "peer456");
    }

    #[test]
    fn test_text_message_with_reply() {
        let msg = TextMessage {
            id: "msg123".to_string(),
            sender_peer_id: "peer456".to_string(),
            content: "Hello".to_string(),
            timestamp: 0,
            reply_to: None,
        };

        let with_reply = msg.with_reply_to("original_msg".to_string());
        assert_eq!(with_reply.reply_to, Some("original_msg".to_string()));
    }

    #[test]
    fn test_chat_message_id() {
        let msg = ChatMessage::text("Test".to_string());
        assert!(msg.id().is_some());

        let ack = MessageAck::new("msg123".to_string(), true);
        let ack_msg = ChatMessage::Ack(ack);
        assert_eq!(ack_msg.id(), Some("msg123"));

        let typing = TypingIndicator::new("peer".to_string(), true);
        let typing_msg = ChatMessage::TypingIndicator(typing);
        assert!(typing_msg.id().is_none());
    }

    #[test]
    fn test_chat_message_sender() {
        let msg = ChatMessage::text("Test".to_string());
        // 未设置发送者时应该返回 Some("")
        assert!(msg.sender_peer_id().is_some());

        let typing = TypingIndicator::new("peer123".to_string(), true);
        let typing_msg = ChatMessage::TypingIndicator(typing);
        assert_eq!(typing_msg.sender_peer_id(), Some("peer123"));

        let ack = MessageAck::new("msg".to_string(), true);
        let ack_msg = ChatMessage::Ack(ack);
        assert!(ack_msg.sender_peer_id().is_none());
    }
}
