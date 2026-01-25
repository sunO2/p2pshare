//! FFI 类型定义
//!
//! 定义与 C ABI 兼容的类型

use libc::{c_char, size_t};

/// P2P 不透明句柄
///
/// 用于标识 P2P 实例
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct P2PHandle {
    pub _private: i32,
}

/// P2P 错误代码
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum P2PErrorCode {
    /// 成功
    Success = 0,
    /// 未初始化
    NotInitialized = -1,
    /// 无效参数
    InvalidArgument = -2,
    /// 发送失败
    SendFailed = -3,
    /// 节点未验证
    NodeNotVerified = -4,
    /// 内存不足
    OutOfMemory = -5,
    /// 其他错误
    Unknown = -99,
}

/// 节点信息
#[repr(C)]
#[derive(Debug)]
pub struct NodeInfo {
    /// Peer ID（UTF-8 字符串，调用者负责释放）
    pub peer_id: *mut c_char,
    /// 显示名称（UTF-8 字符串，调用者负责释放）
    pub display_name: *mut c_char,
    /// 设备名称（UTF-8 字符串，调用者负责释放）
    pub device_name: *mut c_char,
    /// 地址数量
    pub address_count: size_t,
    /// 地址数组（简化实现，暂时为 null）
    pub addresses: *mut *mut c_char,
}

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

/// P2P 事件类型（用于回调）
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum P2PEventType {
    /// 节点发现
    NodeDiscovered = 1,
    /// 节点过期
    NodeExpired = 2,
    /// 节点验证
    NodeVerified = 3,
    /// 节点离线
    NodeOffline = 4,
    /// 收到用户信息
    UserInfoReceived = 5,
    /// 收到消息
    MessageReceived = 6,
    /// 消息已发送
    MessageSent = 7,
    /// 正在输入
    PeerTyping = 8,
}

/// P2P 事件数据
#[repr(C)]
#[derive(Debug)]
pub struct P2PEventData {
    /// 事件类型
    pub event_type: P2PEventType,
    /// Peer ID（事件相关的节点 ID）
    pub peer_id: *const c_char,
    /// 显示名称（对于 NodeVerified 事件）
    pub display_name: *const c_char,
    /// 消息内容（对于 MessageReceived 事件）
    pub message: *const c_char,
    /// 消息 ID（对于 MessageSent 事件）
    pub message_id: *const c_char,
    /// 是否正在输入（对于 PeerTyping 事件）
    pub is_typing: bool,
    /// 时间戳（对于消息事件）
    pub timestamp: i64,
}

impl Default for P2PEventData {
    fn default() -> Self {
        Self {
            event_type: P2PEventType::NodeDiscovered,
            peer_id: std::ptr::null(),
            display_name: std::ptr::null(),
            message: std::ptr::null(),
            message_id: std::ptr::null(),
            is_typing: false,
            timestamp: 0,
        }
    }
}

// ============================================================================
// C 兼容的字符串辅助类型
// ============================================================================

/// C 字符串视图（只读，不拥有内存）
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CStrView {
    pub ptr: *const c_char,
    pub len: size_t,
}

impl CStrView {
    /// 从 Rust 字符串创建
    pub fn from_str(s: &str) -> Self {
        Self {
            ptr: s.as_ptr() as *const c_char,
            len: s.len(),
        }
    }

    /// 转换为 Rust 字符串切片（unsafe）
    ///
    /// # Safety
    /// 调用者必须确保原始字符串仍然有效
    pub unsafe fn as_str(&self) -> &str {
        if self.ptr.is_null() || self.len == 0 {
            return "";
        }
        let bytes = std::slice::from_raw_parts(self.ptr as *const u8, self.len);
        std::str::from_utf8(bytes).unwrap_or("")
    }
}
