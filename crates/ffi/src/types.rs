//! FFI 类型定义
//!
//! 定义内部使用的类型

use serde::{Serialize, Deserialize};

/// JSON 序列化的用户信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserInfoJson {
    pub device_name: String,
    pub nickname: Option<String>,
    pub avatar_url: Option<String>,
    pub status: Option<String>,
}

/// JSON 序列化的聊天消息（旧版，保持兼容）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessageJson {
    pub id: String,
    pub sender_peer_id: String,
    pub content: String,
    pub timestamp: i64,
}

// ============================================================================
// 新增：扩展聊天系统类型
// ============================================================================

/// 消息类型枚举
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum MessageTypeJson {
    Unknown = 0,
    Text = 1,
    Image = 2,
    Video = 3,
    File = 4,
    Audio = 5,
    RedPacket = 6,
    System = 7,
    Custom = 99,
}

impl From<i32> for MessageTypeJson {
    fn from(value: i32) -> Self {
        match value {
            1 => Self::Text,
            2 => Self::Image,
            3 => Self::Video,
            4 => Self::File,
            5 => Self::Audio,
            6 => Self::RedPacket,
            7 => Self::System,
            99 => Self::Custom,
            _ => Self::Unknown,
        }
    }
}

/// 会话信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationJson {
    pub id: String,
    pub peer_id: String,
    pub peer_name: Option<String>,
    pub peer_avatar: Option<String>,
    pub last_message: Option<String>,
    pub last_message_type: i32,
    pub last_message_time: Option<i64>,
    pub unread_count: i32,
    pub is_pinned: bool,
    pub is_muted: bool,
}

/// 扩展消息信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageJson {
    pub id: String,
    pub conversation_id: String,
    pub sender_peer_id: String,
    pub message_type: i32,
    pub content: String,  // JSON 字符串
    pub timestamp: i64,
    pub reply_to_id: Option<String>,
    pub status: i32,
    pub is_deleted: bool,
    pub is_revoked: bool,
}

/// 文件元数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfoJson {
    pub id: String,
    pub message_id: String,
    pub file_name: String,
    pub file_size: i64,
    pub mime_type: String,
    pub local_path: Option<String>,
    pub thumbnail_path: Option<String>,
    pub duration: Option<i32>,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub transfer_status: i32,
    pub transfer_progress: i32,
}

/// 红包信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RedPacketInfoJson {
    pub packet_id: String,
    pub amount: i64,
    pub count: i32,
    pub greeting: Option<String>,
    pub packet_type: i32,
}
