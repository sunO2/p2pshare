//! FFI 错误类型
//!
//! 注意：旧 C ABI 的错误类型已被移除，现在使用 FRB API
//! 错误通过 Result 类型直接返回

/// FFI 错误（仅供内部使用）
#[derive(Debug)]
pub enum FFIError {
    /// 未初始化
    NotInitialized,
    /// 无效参数
    InvalidArgument(String),
    /// 发送失败
    SendFailed(String),
    /// 节点未验证
    NodeNotVerified(String),
    /// 内存不足
    OutOfMemory,
    /// 其他错误
    Other(String),
}

impl std::fmt::Display for FFIError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotInitialized => write!(f, "P2P not initialized"),
            Self::InvalidArgument(s) => write!(f, "Invalid argument: {}", s),
            Self::SendFailed(s) => write!(f, "Send failed: {}", s),
            Self::NodeNotVerified(s) => write!(f, "Node not verified: {}", s),
            Self::OutOfMemory => write!(f, "Out of memory"),
            Self::Other(s) => write!(f, "Error: {}", s),
        }
    }
}

impl std::error::Error for FFIError {}
