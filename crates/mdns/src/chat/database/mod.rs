//! 聊天数据库模块
//!
//! 提供 SQLite 数据库支持，用于持久化聊天消息和会话信息。

pub mod schema;
pub mod models;
pub mod manager;

// 公共 API 导出
pub use manager::{ChatDatabase, SqliteChatDatabase};
pub use models::{Conversation, Message, DbMessage, DbConversation, DbDevice, Device};
pub use schema::{DB_VERSION, SCHEMA_SQL};
