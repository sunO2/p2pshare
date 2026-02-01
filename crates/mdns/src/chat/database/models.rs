//! 数据库模型
//!
//! 定义与数据库表对应的 Rust 数据结构。

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use crate::chat::message::MessageType;
use super::schema::{MessageStatus, TransferStatus};

/// 会话数据模型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DbConversation {
    /// 会话 ID（UUID）
    pub id: String,
    /// 对方 Peer ID
    pub peer_id: String,
    /// 对方显示名称
    pub peer_name: Option<String>,
    /// 对方头像
    pub peer_avatar: Option<String>,
    /// 创建时间
    pub created_at: DateTime<Utc>,
    /// 更新时间
    pub updated_at: DateTime<Utc>,
    /// 最后一条消息内容
    pub last_message: Option<String>,
    /// 最后消息类型
    pub last_message_type: Option<i32>,
    /// 最后消息时间
    pub last_message_time: Option<DateTime<Utc>>,
    /// 未读消息数
    pub unread_count: i32,
    /// 是否置顶
    pub is_pinned: bool,
    /// 是否免打扰
    pub is_muted: bool,
    /// 是否已删除
    pub is_deleted: bool,
}

impl DbConversation {
    /// 创建新会话
    pub fn new(peer_id: String, peer_name: Option<String>) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            peer_id,
            peer_name,
            peer_avatar: None,
            created_at: now,
            updated_at: now,
            last_message: None,
            last_message_type: None,
            last_message_time: None,
            unread_count: 0,
            is_pinned: false,
            is_muted: false,
            is_deleted: false,
        }
    }
}

/// 会话的轻量级表示
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    /// 会话 ID
    pub id: String,
    /// 对方 Peer ID
    pub peer_id: String,
    /// 对方显示名称
    pub peer_name: Option<String>,
    /// 对方头像
    pub peer_avatar: Option<String>,
    /// 最后一条消息内容
    pub last_message: Option<String>,
    /// 最后消息类型
    pub last_message_type: i32,
    /// 最后消息时间
    pub last_message_time: Option<i64>,
    /// 未读消息数
    pub unread_count: i32,
    /// 是否置顶
    pub is_pinned: bool,
    /// 是否免打扰
    pub is_muted: bool,
}

impl From<DbConversation> for Conversation {
    fn from(db: DbConversation) -> Self {
        Self {
            id: db.id,
            peer_id: db.peer_id,
            peer_name: db.peer_name,
            peer_avatar: db.peer_avatar,
            last_message: db.last_message,
            last_message_type: db.last_message_type.unwrap_or(MessageType::Unknown as i32),
            last_message_time: db.last_message_time.map(|t| t.timestamp_millis()),
            unread_count: db.unread_count,
            is_pinned: db.is_pinned,
            is_muted: db.is_muted,
        }
    }
}

/// 消息数据模型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DbMessage {
    /// 消息 ID（UUID）
    pub id: String,
    /// 会话 ID
    pub conversation_id: String,
    /// 发送者 Peer ID
    pub sender_peer_id: String,
    /// 消息类型
    pub message_type: MessageType,
    /// 消息内容（JSON）
    pub content: String,
    /// 时间戳
    pub timestamp: DateTime<Utc>,
    /// 回复的消息 ID
    pub reply_to_id: Option<String>,
    /// 发送状态
    pub status: MessageStatus,
    /// 是否已删除
    pub is_deleted: bool,
    /// 是否已撤回
    pub is_revoked: bool,
    /// 额外数据（JSON）
    pub extra: Option<String>,
}

impl DbMessage {
    /// 创建新消息
    pub fn new(
        conversation_id: String,
        sender_peer_id: String,
        message_type: MessageType,
        content: String,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            conversation_id,
            sender_peer_id,
            message_type,
            content,
            timestamp: Utc::now(),
            reply_to_id: None,
            status: MessageStatus::Sending,
            is_deleted: false,
            is_revoked: false,
            extra: None,
        }
    }
}

/// 消息的轻量级表示
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// 消息 ID
    pub id: String,
    /// 会话 ID
    pub conversation_id: String,
    /// 发送者 Peer ID
    pub sender_peer_id: String,
    /// 消息类型
    pub message_type: i32,
    /// 消息内容（JSON）
    pub content: String,
    /// 时间戳（毫秒）
    pub timestamp: i64,
    /// 回复的消息 ID
    pub reply_to_id: Option<String>,
    /// 发送状态
    pub status: i32,
    /// 是否已删除
    pub is_deleted: bool,
    /// 是否已撤回
    pub is_revoked: bool,
}

impl From<DbMessage> for Message {
    fn from(db: DbMessage) -> Self {
        Self {
            id: db.id,
            conversation_id: db.conversation_id,
            sender_peer_id: db.sender_peer_id,
            message_type: db.message_type as i32,
            content: db.content,
            timestamp: db.timestamp.timestamp_millis(),
            reply_to_id: db.reply_to_id,
            status: db.status as i32,
            is_deleted: db.is_deleted,
            is_revoked: db.is_revoked,
        }
    }
}

/// 文件元数据模型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DbFile {
    /// 文件 ID
    pub id: String,
    /// 关联的消息 ID
    pub message_id: String,
    /// 文件名
    pub file_name: String,
    /// 文件大小
    pub file_size: i64,
    /// MIME 类型
    pub mime_type: String,
    /// 本地存储路径
    pub local_path: Option<String>,
    /// 缩略图路径
    pub thumbnail_path: Option<String>,
    /// 时长（音视频）
    pub duration: Option<i32>,
    /// 宽度
    pub width: Option<i32>,
    /// 高度
    pub height: Option<i32>,
    /// 传输状态
    pub transfer_status: TransferStatus,
    /// 传输进度（0-100）
    pub transfer_progress: i32,
}

impl DbFile {
    /// 创建新文件记录
    pub fn new(
        message_id: String,
        file_name: String,
        file_size: i64,
        mime_type: String,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            message_id,
            file_name,
            file_size,
            mime_type,
            local_path: None,
            thumbnail_path: None,
            duration: None,
            width: None,
            height: None,
            transfer_status: TransferStatus::Pending,
            transfer_progress: 0,
        }
    }
}

/// 用于 JSON 序列化的文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileMetadata {
    /// 文件 ID
    pub id: String,
    /// 消息 ID
    pub message_id: String,
    /// 文件名
    pub file_name: String,
    /// 文件大小
    pub file_size: i64,
    /// MIME 类型
    pub mime_type: String,
    /// 本地路径
    pub local_path: Option<String>,
    /// 缩略图路径
    pub thumbnail_path: Option<String>,
    /// 时长
    pub duration: Option<i32>,
    /// 宽度
    pub width: Option<i32>,
    /// 高度
    pub height: Option<i32>,
    /// 传输状态
    pub transfer_status: i32,
    /// 传输进度
    pub transfer_progress: i32,
}

impl From<DbFile> for FileMetadata {
    fn from(db: DbFile) -> Self {
        Self {
            id: db.id,
            message_id: db.message_id,
            file_name: db.file_name,
            file_size: db.file_size,
            mime_type: db.mime_type,
            local_path: db.local_path,
            thumbnail_path: db.thumbnail_path,
            duration: db.duration,
            width: db.width,
            height: db.height,
            transfer_status: db.transfer_status as i32,
            transfer_progress: db.transfer_progress,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_conversation_creation() {
        let conv = DbConversation::new("peer123".to_string(), Some("Alice".to_string()));
        assert_eq!(conv.peer_id, "peer123");
        assert_eq!(conv.peer_name, Some("Alice".to_string()));
        assert_eq!(conv.unread_count, 0);
        assert!(!conv.is_pinned);
        assert!(!conv.is_muted);
        assert!(!conv.is_deleted);
    }

    #[test]
    fn test_message_creation() {
        let msg = DbMessage::new(
            "conv123".to_string(),
            "peer456".to_string(),
            MessageType::Text,
            "Hello".to_string(),
        );
        assert_eq!(msg.conversation_id, "conv123");
        assert_eq!(msg.sender_peer_id, "peer456");
        assert_eq!(msg.message_type, MessageType::Text);
        assert_eq!(msg.status, MessageStatus::Sending);
    }

    #[test]
    fn test_file_creation() {
        let file = DbFile::new(
            "msg789".to_string(),
            "test.jpg".to_string(),
            1024,
            "image/jpeg".to_string(),
        );
        assert_eq!(file.message_id, "msg789");
        assert_eq!(file.file_name, "test.jpg");
        assert_eq!(file.file_size, 1024);
        assert_eq!(file.transfer_status, TransferStatus::Pending);
        assert_eq!(file.transfer_progress, 0);
    }

    #[test]
    fn test_conversation_to_light() {
        let db_conv = DbConversation {
            id: "conv123".to_string(),
            peer_id: "peer456".to_string(),
            peer_name: Some("Bob".to_string()),
            peer_avatar: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            last_message: Some("Hi".to_string()),
            last_message_type: Some(MessageType::Text as i32),
            last_message_time: Some(Utc::now()),
            unread_count: 2,
            is_pinned: true,
            is_muted: false,
            is_deleted: false,
        };
        let conv: Conversation = db_conv.into();
        assert_eq!(conv.id, "conv123");
        assert_eq!(conv.peer_id, "peer456");
        assert_eq!(conv.peer_name, Some("Bob".to_string()));
        assert_eq!(conv.last_message, Some("Hi".to_string()));
        assert_eq!(conv.unread_count, 2);
        assert!(conv.is_pinned);
    }
}
