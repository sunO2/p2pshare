//! 聊天消息协议
//!
//! 定义聊天功能使用的消息类型和序列化格式。

use serde::{Deserialize, Serialize};
use num_derive::{FromPrimitive, ToPrimitive};

/// 聊天协议名称（v2.0.0 - 支持扩展消息类型）
pub const CHAT_PROTOCOL: &str = "/localp2p/chat/2.0.0";
/// 旧版本协议（保持向后兼容）
pub const CHAT_PROTOCOL_V1: &str = "/localp2p/chat/1.0.0";

/// 消息类型枚举
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, FromPrimitive, ToPrimitive)]
#[repr(i32)]
pub enum MessageType {
    /// 未知类型
    Unknown = 0,
    /// 文本消息
    Text = 1,
    /// 图片
    Image = 2,
    /// 视频
    Video = 3,
    /// 文件
    File = 4,
    /// 音频
    Audio = 5,
    /// 红包
    RedPacket = 6,
    /// 系统消息
    System = 7,
    /// 自定义类型（可扩展）
    Custom = 99,
}

impl MessageType {
    /// 从 i32 转换
    pub fn from_i32(value: i32) -> Self {
        num_traits::FromPrimitive::from_i32(value).unwrap_or(Self::Unknown)
    }

    /// 转换为 i32
    pub fn to_i32(self) -> i32 {
        self as i32
    }
}

/// 通用消息内容（JSON 序列化）
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MessageContent {
    /// 消息类型
    pub msg_type: MessageType,
    /// 文本内容
    pub text: Option<String>,
    /// 文件信息
    pub file_info: Option<FileInfo>,
    /// 红包信息
    pub red_packet: Option<RedPacketInfo>,
    /// 扩展字段（JSON）
    pub extra: Option<serde_json::Value>,
}

impl MessageContent {
    /// 创建文本消息
    pub fn text(text: String) -> Self {
        Self {
            msg_type: MessageType::Text,
            text: Some(text),
            file_info: None,
            red_packet: None,
            extra: None,
        }
    }

    /// 创建图片消息
    pub fn image(file_info: FileInfo) -> Self {
        Self {
            msg_type: MessageType::Image,
            text: None,
            file_info: Some(file_info),
            red_packet: None,
            extra: None,
        }
    }

    /// 创建视频消息
    pub fn video(file_info: FileInfo) -> Self {
        Self {
            msg_type: MessageType::Video,
            text: None,
            file_info: Some(file_info),
            red_packet: None,
            extra: None,
        }
    }

    /// 创建文件消息
    pub fn file(file_info: FileInfo) -> Self {
        Self {
            msg_type: MessageType::File,
            text: None,
            file_info: Some(file_info),
            red_packet: None,
            extra: None,
        }
    }

    /// 创建音频消息
    pub fn audio(file_info: FileInfo) -> Self {
        Self {
            msg_type: MessageType::Audio,
            text: None,
            file_info: Some(file_info),
            red_packet: None,
            extra: None,
        }
    }

    /// 创建红包消息
    pub fn red_packet(red_packet: RedPacketInfo) -> Self {
        Self {
            msg_type: MessageType::RedPacket,
            text: None,
            file_info: None,
            red_packet: Some(red_packet),
            extra: None,
        }
    }

    /// 创建系统消息
    pub fn system(text: String) -> Self {
        Self {
            msg_type: MessageType::System,
            text: Some(text),
            file_info: None,
            red_packet: None,
            extra: None,
        }
    }
}

/// 文件元数据
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FileInfo {
    /// 文件唯一 ID
    pub file_id: String,
    /// 文件名
    pub file_name: String,
    /// 文件大小（字节）
    pub file_size: i64,
    /// MIME 类型
    pub mime_type: String,
    /// 缩略图路径（本地）
    pub thumbnail: Option<String>,
    /// 时长（音视频，秒）
    pub duration: Option<i32>,
    /// 宽度（图片/视频）
    pub width: Option<i32>,
    /// 高度（图片/视频）
    pub height: Option<i32>,
}

impl FileInfo {
    /// 创建新的文件信息
    pub fn new(file_id: String, file_name: String, file_size: i64, mime_type: String) -> Self {
        Self {
            file_id,
            file_name,
            file_size,
            mime_type,
            thumbnail: None,
            duration: None,
            width: None,
            height: None,
        }
    }

    /// 设置缩略图
    pub fn with_thumbnail(mut self, thumbnail: String) -> Self {
        self.thumbnail = Some(thumbnail);
        self
    }

    /// 设置时长（音视频）
    pub fn with_duration(mut self, duration: i32) -> Self {
        self.duration = Some(duration);
        self
    }

    /// 设置尺寸（图片/视频）
    pub fn with_size(mut self, width: i32, height: i32) -> Self {
        self.width = Some(width);
        self.height = Some(height);
        self
    }
}

/// 红包信息
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RedPacketInfo {
    /// 红包 ID
    pub packet_id: String,
    /// 金额（分）
    pub amount: i64,
    /// 个数
    pub count: i32,
    /// 祝福语
    pub greeting: Option<String>,
    /// 类型: 1=随机 2=固定
    pub packet_type: i32,
}

impl RedPacketInfo {
    /// 创建新的红包信息
    pub fn new(packet_id: String, amount: i64, count: i32, packet_type: i32) -> Self {
        Self {
            packet_id,
            amount,
            count,
            greeting: None,
            packet_type,
        }
    }

    /// 设置祝福语
    pub fn with_greeting(mut self, greeting: String) -> Self {
        self.greeting = Some(greeting);
        self
    }
}

/// 聊天消息类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ChatMessage {
    /// 通用消息（包含所有类型）
    Message(GeneralMessage),
    /// 正在输入提示
    TypingIndicator(TypingIndicator),
    /// 消息确认
    Ack(MessageAck),
    /// 旧版文本消息（保持向后兼容）
    Text(TextMessage),
}

impl ChatMessage {
    /// 创建文本消息（新版，使用 GeneralMessage）
    pub fn text(content: String) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(), // 需要在发送时设置
            content: MessageContent::text(content),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 创建图片消息
    pub fn image(file_info: FileInfo) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(),
            content: MessageContent::image(file_info),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 创建视频消息
    pub fn video(file_info: FileInfo) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(),
            content: MessageContent::video(file_info),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 创建文件消息
    pub fn file(file_info: FileInfo) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(),
            content: MessageContent::file(file_info),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 创建音频消息
    pub fn audio(file_info: FileInfo) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(),
            content: MessageContent::audio(file_info),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 创建红包消息
    pub fn red_packet(red_packet: RedPacketInfo) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(),
            content: MessageContent::red_packet(red_packet),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 创建系统消息
    pub fn system(text: String) -> Self {
        Self::Message(GeneralMessage {
            id: uuid::Uuid::new_v4().to_string(),
            sender_peer_id: String::new(),
            content: MessageContent::system(text),
            timestamp: chrono::Utc::now().timestamp_millis(),
            reply_to: None,
        })
    }

    /// 获取消息 ID
    pub fn id(&self) -> Option<&str> {
        match self {
            Self::Message(m) => Some(&m.id),
            Self::Text(t) => Some(&t.id),
            Self::Ack(a) => Some(&a.message_id),
            Self::TypingIndicator(_) => None,
        }
    }

    /// 获取发送者 Peer ID
    pub fn sender_peer_id(&self) -> Option<&str> {
        match self {
            Self::Message(m) => Some(&m.sender_peer_id),
            Self::Text(t) => Some(&t.sender_peer_id),
            Self::TypingIndicator(t) => Some(&t.sender_peer_id),
            Self::Ack(_) => None,
        }
    }

    /// 获取消息内容（如果存在）
    pub fn content(&self) -> Option<&MessageContent> {
        match self {
            Self::Message(m) => Some(&m.content),
            _ => None,
        }
    }

    /// 获取消息类型
    pub fn message_type(&self) -> MessageType {
        match self {
            Self::Message(m) => m.content.msg_type,
            Self::Text(_) => MessageType::Text,
            _ => MessageType::Unknown,
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

/// 通用消息结构
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GeneralMessage {
    /// 消息唯一 ID（UUID）
    pub id: String,
    /// 发送者的 Peer ID
    pub sender_peer_id: String,
    /// 消息内容
    pub content: MessageContent,
    /// Unix 时间戳（毫秒）
    pub timestamp: i64,
    /// 回复的消息 ID（可选）
    pub reply_to: Option<String>,
}

impl GeneralMessage {
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
