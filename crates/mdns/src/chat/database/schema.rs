//! 数据库表结构定义
//!
//! 定义 SQLite 数据库的表结构和 SQL 初始化脚本。

use serde::{Serialize, Deserialize};
use num_derive::{FromPrimitive, ToPrimitive};

/// 数据库版本号
pub const DB_VERSION: i32 = 1;

/// 数据库初始化 SQL
pub const SCHEMA_SQL: &str = r#"
-- 创建会话表
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    peer_id TEXT NOT NULL UNIQUE,
    peer_name TEXT,
    peer_avatar TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_message TEXT,
    last_message_type INTEGER,
    last_message_time INTEGER,
    unread_count INTEGER DEFAULT 0,
    is_pinned INTEGER DEFAULT 0,
    is_muted INTEGER DEFAULT 0,
    is_deleted INTEGER DEFAULT 0
);

-- 创建会话表索引
CREATE INDEX IF NOT EXISTS idx_conversations_peer_id ON conversations(peer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at ON conversations(updated_at DESC);

-- 创建消息表
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    sender_peer_id TEXT NOT NULL,
    message_type INTEGER NOT NULL,
    content TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    reply_to_id TEXT,
    status INTEGER DEFAULT 0,
    is_deleted INTEGER DEFAULT 0,
    is_revoked INTEGER DEFAULT 0,
    extra TEXT,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

-- 创建消息表索引
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_peer_id);

-- 创建文件元数据表
CREATE TABLE IF NOT EXISTS files (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    local_path TEXT,
    thumbnail_path TEXT,
    duration INTEGER,
    width INTEGER,
    height INTEGER,
    transfer_status INTEGER DEFAULT 0,
    transfer_progress INTEGER DEFAULT 0,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- 创建文件表索引
CREATE INDEX IF NOT EXISTS idx_files_message_id ON files(message_id);

-- 创建元数据表（用于数据库版本管理）
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- 插入当前数据库版本
INSERT OR REPLACE INTO metadata (key, value) VALUES ('db_version', '1');
"#;

/// 消息发送状态
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, FromPrimitive, ToPrimitive)]
#[repr(i32)]
pub enum MessageStatus {
    /// 发送中
    Sending = 0,
    /// 已发送
    Sent = 1,
    /// 已送达
    Delivered = 2,
    /// 已读
    Read = 3,
    /// 失败
    Failed = 4,
}

impl MessageStatus {
    /// 从 i32 转换
    pub fn from_i32(value: i32) -> Self {
        num_traits::FromPrimitive::from_i32(value).unwrap_or(Self::Sending)
    }

    /// 转换为 i32
    pub fn to_i32(self) -> i32 {
        self as i32
    }
}

/// 文件传输状态
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, FromPrimitive, ToPrimitive)]
#[repr(i32)]
pub enum TransferStatus {
    /// 待传输
    Pending = 0,
    /// 传输中
    Transferring = 1,
    /// 完成
    Completed = 2,
    /// 失败
    Failed = 3,
}

impl TransferStatus {
    /// 从 i32 转换
    pub fn from_i32(value: i32) -> Self {
        num_traits::FromPrimitive::from_i32(value).unwrap_or(Self::Pending)
    }

    /// 转换为 i32
    pub fn to_i32(self) -> i32 {
        self as i32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_status_conversion() {
        assert_eq!(MessageStatus::from_i32(0), MessageStatus::Sending);
        assert_eq!(MessageStatus::from_i32(1), MessageStatus::Sent);
        assert_eq!(MessageStatus::from_i32(2), MessageStatus::Delivered);
        assert_eq!(MessageStatus::from_i32(3), MessageStatus::Read);
        assert_eq!(MessageStatus::from_i32(4), MessageStatus::Failed);
        // 未知值默认为 Sending
        assert_eq!(MessageStatus::from_i32(999), MessageStatus::Sending);
    }

    #[test]
    fn test_message_status_to_i32() {
        assert_eq!(MessageStatus::Sending.to_i32(), 0);
        assert_eq!(MessageStatus::Sent.to_i32(), 1);
        assert_eq!(MessageStatus::Delivered.to_i32(), 2);
        assert_eq!(MessageStatus::Read.to_i32(), 3);
        assert_eq!(MessageStatus::Failed.to_i32(), 4);
    }

    #[test]
    fn test_transfer_status_conversion() {
        assert_eq!(TransferStatus::from_i32(0), TransferStatus::Pending);
        assert_eq!(TransferStatus::from_i32(1), TransferStatus::Transferring);
        assert_eq!(TransferStatus::from_i32(2), TransferStatus::Completed);
        assert_eq!(TransferStatus::from_i32(3), TransferStatus::Failed);
        // 未知值默认为 Pending
        assert_eq!(TransferStatus::from_i32(999), TransferStatus::Pending);
    }

    #[test]
    fn test_db_version() {
        assert_eq!(DB_VERSION, 1);
    }
}
