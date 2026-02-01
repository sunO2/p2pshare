//! 数据库管理器
//!
//! 定义聊天数据库的 trait 和 SQLite 实现。

use super::models::{DbConversation, DbMessage, DbFile, Conversation, Message, FileMetadata};
use super::schema::{MessageStatus, TransferStatus};
use crate::chat::message::MessageType;
use crate::chat::ChatError;
use sqlx::{sqlite::SqlitePool, Row};
use std::path::Path;

/// 聊天数据库 trait
#[async_trait::async_trait]
pub trait ChatDatabase: Send + Sync {
    /// 初始化数据库
    async fn initialize(&self) -> Result<(), ChatError>;

    /// 会话管理
    async fn get_or_create_conversation(&self, peer_id: &str, peer_name: Option<String>) -> Result<Conversation, ChatError>;
    async fn get_conversation_by_peer(&self, peer_id: &str) -> Result<Option<Conversation>, ChatError>;
    async fn get_all_conversations(&self) -> Result<Vec<Conversation>, ChatError>;
    async fn update_conversation(
        &self,
        conversation_id: &str,
        last_message: Option<String>,
        last_message_type: Option<MessageType>,
        last_message_time: Option<i64>,
        increment_unread: bool,
    ) -> Result<(), ChatError>;
    async fn mark_conversation_read(&self, conversation_id: &str) -> Result<(), ChatError>;
    async fn delete_conversation(&self, conversation_id: &str) -> Result<(), ChatError>;
    async fn clear_conversation_messages(&self, conversation_id: &str) -> Result<(), ChatError>;

    /// 消息管理
    async fn insert_message(&self, message: DbMessage) -> Result<String, ChatError>;
    async fn get_messages(
        &self,
        conversation_id: &str,
        limit: i32,
        before_timestamp: Option<i64>,
    ) -> Result<Vec<Message>, ChatError>;
    async fn get_message(&self, message_id: &str) -> Result<Option<Message>, ChatError>;
    async fn update_message_status(&self, message_id: &str, status: MessageStatus) -> Result<(), ChatError>;
    async fn mark_messages_read(&self, conversation_id: &str, message_ids: Vec<String>) -> Result<(), ChatError>;
    async fn delete_message(&self, message_id: &str) -> Result<(), ChatError>;
    async fn revoke_message(&self, message_id: &str) -> Result<(), ChatError>;

    /// 文件管理
    async fn insert_file(&self, file: DbFile) -> Result<String, ChatError>;
    async fn get_file(&self, file_id: &str) -> Result<Option<FileMetadata>, ChatError>;
    async fn get_file_by_message(&self, message_id: &str) -> Result<Option<FileMetadata>, ChatError>;
    async fn update_file_transfer(
        &self,
        file_id: &str,
        status: TransferStatus,
        progress: i32,
    ) -> Result<(), ChatError>;
}

/// SQLite 聊天数据库实现
pub struct SqliteChatDatabase {
    pool: SqlitePool,
}

impl SqliteChatDatabase {
    /// 创建新的 SQLite 数据库实例
    pub async fn new(db_path: &Path) -> Result<Self, ChatError> {
        // 确保目录存在
        if let Some(parent) = db_path.parent() {
            tokio::fs::create_dir_all(parent).await
                .map_err(|e| ChatError::Serialization(format!("Failed to create directory: {}", e)))?;
        }

        // 创建数据库连接池（使用 file: URI 模式，Android 兼容性更好）
        let connection_string = format!("sqlite:file:{}?mode=rwc", db_path.display());
        crate::send_log("INFO", "database", format!("连接数据库: {}", connection_string));
        let pool = SqlitePool::connect(&connection_string)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to connect to database: {}", e)))?;

        let db = Self { pool };

        // 初始化数据库表
        db.initialize().await?;

        Ok(db)
    }

    /// 从连接池创建（用于测试）
    pub fn from_pool(pool: SqlitePool) -> Self {
        Self { pool }
    }

    /// 获取连接池
    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    /// 执行初始化 SQL
    async fn execute_schema(&self) -> Result<(), ChatError> {
        use super::schema::SCHEMA_SQL;

        // 分割 SQL 语句并逐个执行
        let statements: Vec<&str> = SCHEMA_SQL
            .split(';')
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .collect();

        for stmt in statements {
            sqlx::query(stmt)
                .execute(&self.pool)
                .await
                .map_err(|e| ChatError::Serialization(format!("Failed to execute schema: {}", e)))?;
        }

        Ok(())
    }
}

#[async_trait::async_trait]
impl ChatDatabase for SqliteChatDatabase {
    async fn initialize(&self) -> Result<(), ChatError> {
        self.execute_schema().await
    }

    async fn get_or_create_conversation(&self, peer_id: &str, peer_name: Option<String>) -> Result<Conversation, ChatError> {
        // 首先尝试获取现有会话
        if let Some(conv) = self.get_conversation_by_peer(peer_id).await? {
            return Ok(conv);
        }

        // 创建新会话
        let now = chrono::Utc::now().timestamp_millis();
        let id = uuid::Uuid::new_v4().to_string();

        sqlx::query(
            "INSERT INTO conversations (id, peer_id, peer_name, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5)"
        )
        .bind(&id)
        .bind(peer_id)
        .bind(&peer_name)
        .bind(now)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to create conversation: {}", e)))?;

        Ok(Conversation {
            id,
            peer_id: peer_id.to_string(),
            peer_name,
            peer_avatar: None,
            last_message: None,
            last_message_type: MessageType::Unknown as i32,
            last_message_time: None,
            unread_count: 0,
            is_pinned: false,
            is_muted: false,
        })
    }

    async fn get_conversation_by_peer(&self, peer_id: &str) -> Result<Option<Conversation>, ChatError> {
        let row = sqlx::query(
            "SELECT id, peer_id, peer_name, peer_avatar, last_message, last_message_type,
                    last_message_time, unread_count, is_pinned, is_muted
             FROM conversations
             WHERE peer_id = ?1 AND is_deleted = 0"
        )
        .bind(peer_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to get conversation: {}", e)))?;

        if let Some(row) = row {
            Ok(Some(Conversation {
                id: row.get("id"),
                peer_id: row.get("peer_id"),
                peer_name: row.try_get("peer_name").ok(),
                peer_avatar: row.try_get("peer_avatar").ok(),
                last_message: row.try_get("last_message").ok(),
                last_message_type: row.try_get("last_message_type").unwrap_or(MessageType::Unknown as i32),
                last_message_time: row.try_get("last_message_time").ok(),
                unread_count: row.get("unread_count"),
                is_pinned: row.get::<i32, _>("is_pinned") != 0,
                is_muted: row.get::<i32, _>("is_muted") != 0,
            }))
        } else {
            Ok(None)
        }
    }

    async fn get_all_conversations(&self) -> Result<Vec<Conversation>, ChatError> {
        let rows = sqlx::query(
            "SELECT id, peer_id, peer_name, peer_avatar, last_message, last_message_type,
                    last_message_time, unread_count, is_pinned, is_muted
             FROM conversations
             WHERE is_deleted = 0
             ORDER BY updated_at DESC"
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to get conversations: {}", e)))?;

        Ok(rows.into_iter().map(|row| Conversation {
            id: row.get("id"),
            peer_id: row.get("peer_id"),
            peer_name: row.try_get("peer_name").ok(),
            peer_avatar: row.try_get("peer_avatar").ok(),
            last_message: row.try_get("last_message").ok(),
            last_message_type: row.try_get("last_message_type").unwrap_or(MessageType::Unknown as i32),
            last_message_time: row.try_get("last_message_time").ok(),
            unread_count: row.get("unread_count"),
            is_pinned: row.get::<i32, _>("is_pinned") != 0,
            is_muted: row.get::<i32, _>("is_muted") != 0,
        }).collect())
    }

    async fn update_conversation(
        &self,
        conversation_id: &str,
        last_message: Option<String>,
        last_message_type: Option<MessageType>,
        last_message_time: Option<i64>,
        increment_unread: bool,
    ) -> Result<(), ChatError> {
        let now = chrono::Utc::now().timestamp_millis();

        let mut query = String::from("UPDATE conversations SET updated_at = ?1");
        let mut param_index = 2;

        if last_message.is_some() {
            query.push_str(&format!(", last_message = ?{}", param_index));
            param_index += 1;
        }
        if last_message_type.is_some() {
            query.push_str(&format!(", last_message_type = ?{}", param_index));
            param_index += 1;
        }
        if last_message_time.is_some() {
            query.push_str(&format!(", last_message_time = ?{}", param_index));
            param_index += 1;
        }
        if increment_unread {
            query.push_str(&format!(", unread_count = unread_count + 1"));
        }

        query.push_str(&format!(" WHERE id = ?{}", param_index));

        let mut q = sqlx::query(&query).bind(now);

        if let Some(msg) = last_message {
            q = q.bind(msg);
        }
        if let Some(mt) = last_message_type {
            q = q.bind(mt as i32);
        }
        if let Some(mt) = last_message_time {
            q = q.bind(mt);
        }
        q = q.bind(conversation_id);

        q.execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to update conversation: {}", e)))?;

        Ok(())
    }

    async fn mark_conversation_read(&self, conversation_id: &str) -> Result<(), ChatError> {
        sqlx::query("UPDATE conversations SET unread_count = 0 WHERE id = ?1")
            .bind(conversation_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to mark conversation read: {}", e)))?;
        Ok(())
    }

    async fn delete_conversation(&self, conversation_id: &str) -> Result<(), ChatError> {
        sqlx::query("UPDATE conversations SET is_deleted = 1 WHERE id = ?1")
            .bind(conversation_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to delete conversation: {}", e)))?;
        Ok(())
    }

    async fn clear_conversation_messages(&self, conversation_id: &str) -> Result<(), ChatError> {
        sqlx::query("DELETE FROM messages WHERE conversation_id = ?1")
            .bind(conversation_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to clear messages: {}", e)))?;
        Ok(())
    }

    async fn insert_message(&self, message: DbMessage) -> Result<String, ChatError> {
        let message_id = message.id.clone();

        sqlx::query(
            "INSERT INTO messages (id, conversation_id, sender_peer_id, message_type, content,
                                  timestamp, reply_to_id, status, is_deleted, is_revoked, extra)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"
        )
        .bind(&message.id)
        .bind(&message.conversation_id)
        .bind(&message.sender_peer_id)
        .bind(message.message_type as i32)
        .bind(&message.content)
        .bind(message.timestamp.timestamp_millis())
        .bind(&message.reply_to_id)
        .bind(message.status as i32)
        .bind(message.is_deleted as i32)
        .bind(message.is_revoked as i32)
        .bind(&message.extra)
        .execute(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to insert message: {}", e)))?;

        Ok(message_id)
    }

    async fn get_messages(
        &self,
        conversation_id: &str,
        limit: i32,
        before_timestamp: Option<i64>,
    ) -> Result<Vec<Message>, ChatError> {
        let rows = if let Some(before_ts) = before_timestamp {
            sqlx::query(
                "SELECT id, conversation_id, sender_peer_id, message_type, content,
                        timestamp, reply_to_id, status, is_deleted, is_revoked
                 FROM messages
                 WHERE conversation_id = ?1 AND timestamp < ?2 AND is_deleted = 0
                 ORDER BY timestamp DESC
                 LIMIT ?3"
            )
            .bind(conversation_id)
            .bind(before_ts)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
        } else {
            sqlx::query(
                "SELECT id, conversation_id, sender_peer_id, message_type, content,
                        timestamp, reply_to_id, status, is_deleted, is_revoked
                 FROM messages
                 WHERE conversation_id = ?1 AND is_deleted = 0
                 ORDER BY timestamp DESC
                 LIMIT ?2"
            )
            .bind(conversation_id)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
        };

        let rows = rows.map_err(|e| ChatError::Serialization(format!("Failed to get messages: {}", e)))?;

        Ok(rows.into_iter().map(|row| Message {
            id: row.get("id"),
            conversation_id: row.get("conversation_id"),
            sender_peer_id: row.get("sender_peer_id"),
            message_type: row.get("message_type"),
            content: row.get("content"),
            timestamp: row.get("timestamp"),
            reply_to_id: row.try_get("reply_to_id").ok(),
            status: row.get::<i32, _>("status"),
            is_deleted: row.get::<i32, _>("is_deleted") != 0,
            is_revoked: row.get::<i32, _>("is_revoked") != 0,
        }).collect())
    }

    async fn get_message(&self, message_id: &str) -> Result<Option<Message>, ChatError> {
        let row = sqlx::query(
            "SELECT id, conversation_id, sender_peer_id, message_type, content,
                    timestamp, reply_to_id, status, is_deleted, is_revoked
             FROM messages
             WHERE id = ?1"
        )
        .bind(message_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to get message: {}", e)))?;

        if let Some(row) = row {
            Ok(Some(Message {
                id: row.get("id"),
                conversation_id: row.get("conversation_id"),
                sender_peer_id: row.get("sender_peer_id"),
                message_type: row.get("message_type"),
                content: row.get("content"),
                timestamp: row.get("timestamp"),
                reply_to_id: row.try_get("reply_to_id").ok(),
                status: row.get("status"),
                is_deleted: row.get::<i32, _>("is_deleted") != 0,
                is_revoked: row.get::<i32, _>("is_revoked") != 0,
            }))
        } else {
            Ok(None)
        }
    }

    async fn update_message_status(&self, message_id: &str, status: MessageStatus) -> Result<(), ChatError> {
        sqlx::query("UPDATE messages SET status = ?1 WHERE id = ?2")
            .bind(status as i32)
            .bind(message_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to update message status: {}", e)))?;
        Ok(())
    }

    async fn mark_messages_read(&self, _conversation_id: &str, message_ids: Vec<String>) -> Result<(), ChatError> {
        for message_id in message_ids {
            sqlx::query("UPDATE messages SET status = ?1 WHERE id = ?2")
                .bind(MessageStatus::Read as i32)
                .bind(&message_id)
                .execute(&self.pool)
                .await
                .map_err(|e| ChatError::Serialization(format!("Failed to mark message read: {}", e)))?;
        }
        Ok(())
    }

    async fn delete_message(&self, message_id: &str) -> Result<(), ChatError> {
        sqlx::query("UPDATE messages SET is_deleted = 1 WHERE id = ?1")
            .bind(message_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to delete message: {}", e)))?;
        Ok(())
    }

    async fn revoke_message(&self, message_id: &str) -> Result<(), ChatError> {
        sqlx::query("UPDATE messages SET is_revoked = 1 WHERE id = ?1")
            .bind(message_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to revoke message: {}", e)))?;
        Ok(())
    }

    async fn insert_file(&self, file: DbFile) -> Result<String, ChatError> {
        let file_id = file.id.clone();

        sqlx::query(
            "INSERT INTO files (id, message_id, file_name, file_size, mime_type,
                              local_path, thumbnail_path, duration, width, height,
                              transfer_status, transfer_progress)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)"
        )
        .bind(&file.id)
        .bind(&file.message_id)
        .bind(&file.file_name)
        .bind(file.file_size)
        .bind(&file.mime_type)
        .bind(&file.local_path)
        .bind(&file.thumbnail_path)
        .bind(&file.duration)
        .bind(&file.width)
        .bind(&file.height)
        .bind(file.transfer_status as i32)
        .bind(file.transfer_progress)
        .execute(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to insert file: {}", e)))?;

        Ok(file_id)
    }

    async fn get_file(&self, file_id: &str) -> Result<Option<FileMetadata>, ChatError> {
        let row = sqlx::query(
            "SELECT id, message_id, file_name, file_size, mime_type,
                    local_path, thumbnail_path, duration, width, height,
                    transfer_status, transfer_progress
             FROM files
             WHERE id = ?1"
        )
        .bind(file_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to get file: {}", e)))?;

        if let Some(row) = row {
            Ok(Some(FileMetadata {
                id: row.get("id"),
                message_id: row.get("message_id"),
                file_name: row.get("file_name"),
                file_size: row.get("file_size"),
                mime_type: row.get("mime_type"),
                local_path: row.try_get("local_path").ok(),
                thumbnail_path: row.try_get("thumbnail_path").ok(),
                duration: row.try_get("duration").ok(),
                width: row.try_get("width").ok(),
                height: row.try_get("height").ok(),
                transfer_status: row.get::<i32, _>("transfer_status"),
                transfer_progress: row.get::<i32, _>("transfer_progress"),
            }))
        } else {
            Ok(None)
        }
    }

    async fn get_file_by_message(&self, message_id: &str) -> Result<Option<FileMetadata>, ChatError> {
        let row = sqlx::query(
            "SELECT id, message_id, file_name, file_size, mime_type,
                    local_path, thumbnail_path, duration, width, height,
                    transfer_status, transfer_progress
             FROM files
             WHERE message_id = ?1"
        )
        .bind(message_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| ChatError::Serialization(format!("Failed to get file: {}", e)))?;

        if let Some(row) = row {
            Ok(Some(FileMetadata {
                id: row.get("id"),
                message_id: row.get("message_id"),
                file_name: row.get("file_name"),
                file_size: row.get("file_size"),
                mime_type: row.get("mime_type"),
                local_path: row.try_get("local_path").ok(),
                thumbnail_path: row.try_get("thumbnail_path").ok(),
                duration: row.try_get("duration").ok(),
                width: row.try_get("width").ok(),
                height: row.try_get("height").ok(),
                transfer_status: row.get::<i32, _>("transfer_status"),
                transfer_progress: row.get::<i32, _>("transfer_progress"),
            }))
        } else {
            Ok(None)
        }
    }

    async fn update_file_transfer(
        &self,
        file_id: &str,
        status: TransferStatus,
        progress: i32,
    ) -> Result<(), ChatError> {
        sqlx::query("UPDATE files SET transfer_status = ?1, transfer_progress = ?2 WHERE id = ?3")
            .bind(status as i32)
            .bind(progress)
            .bind(file_id)
            .execute(&self.pool)
            .await
            .map_err(|e| ChatError::Serialization(format!("Failed to update file transfer: {}", e)))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_sqlite_database_creation() {
        // 使用内存数据库进行测试
        let pool = SqlitePool::connect(":memory:")
            .await
            .unwrap();

        let db = SqliteChatDatabase::from_pool(pool);
        db.initialize().await.unwrap();

        // 测试会话创建
        let conv = db.get_or_create_conversation("peer123", Some("Alice".to_string())).await.unwrap();
        assert_eq!(conv.peer_id, "peer123");
        assert_eq!(conv.peer_name, Some("Alice".to_string()));

        // 测试获取会话
        let found_conv = db.get_conversation_by_peer("peer123").await.unwrap();
        assert!(found_conv.is_some());
        assert_eq!(found_conv.unwrap().peer_id, "peer123");

        // 测试获取所有会话
        let all_convs = db.get_all_conversations().await.unwrap();
        assert_eq!(all_convs.len(), 1);
    }

    #[tokio::test]
    async fn test_message_operations() {
        let pool = SqlitePool::connect(":memory:")
            .await
            .unwrap();

        let db = SqliteChatDatabase::from_pool(pool);
        db.initialize().await.unwrap();

        // 创建会话
        let conv = db.get_or_create_conversation("peer456", Some("Bob".to_string())).await.unwrap();

        // 插入消息
        let msg = DbMessage::new(
            conv.id.clone(),
            "peer789".to_string(),
            MessageType::Text,
            "Hello World".to_string(),
        );

        let msg_id = db.insert_message(msg).await.unwrap();
        assert!(!msg_id.is_empty());

        // 获取消息
        let found_msg = db.get_message(&msg_id).await.unwrap();
        assert!(found_msg.is_some());

        // 获取会话的消息
        let messages = db.get_messages(&conv.id, 10, None).await.unwrap();
        assert_eq!(messages.len(), 1);
    }
}
