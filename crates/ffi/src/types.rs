//! FFI 类型定义
//!
//! 定义内部使用的类型

/// JSON 序列化的用户信息
#[derive(Debug, Clone)]
pub struct UserInfoJson {
    pub device_name: String,
    pub nickname: Option<String>,
    pub avatar_url: Option<String>,
    pub status: Option<String>,
}

/// JSON 序列化的聊天消息
#[derive(Debug, Clone)]
pub struct ChatMessageJson {
    pub id: String,
    pub sender_peer_id: String,
    pub content: String,
    pub timestamp: i64,
}
