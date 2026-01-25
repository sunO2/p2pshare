//! FFI 错误类型

use std::fmt;

/// FFI 错误
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

impl fmt::Display for FFIError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
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

/// 将 FFIError 转换为 P2PErrorCode
impl From<FFIError> for crate::types::P2PErrorCode {
    fn from(err: FFIError) -> Self {
        match err {
            FFIError::NotInitialized => Self::NotInitialized,
            FFIError::InvalidArgument(_) => Self::InvalidArgument,
            FFIError::SendFailed(_) => Self::SendFailed,
            FFIError::NodeNotVerified(_) => Self::NodeNotVerified,
            FFIError::OutOfMemory => Self::OutOfMemory,
            FFIError::Other(_) => Self::Unknown,
        }
    }
}
