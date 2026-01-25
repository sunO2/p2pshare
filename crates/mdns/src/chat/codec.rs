//! 聊天协议 Codec
//!
//! 使用 request_response 模式实现聊天消息的收发。

use async_trait::async_trait;
use futures::{AsyncRead, AsyncWrite, AsyncReadExt, AsyncWriteExt};
use libp2p::request_response;
use serde::{Deserialize, Serialize};

use super::{ChatMessage, CHAT_PROTOCOL};

/// 聊天协议（标记类型）
#[derive(Debug, Clone, Default)]
pub struct ChatProtocol;

impl AsRef<str> for ChatProtocol {
    fn as_ref(&self) -> &str {
        CHAT_PROTOCOL
    }
}

/// 聊天请求（消息）
pub type ChatRequest = ChatMessage;

/// 聊天响应（可选的确认）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatResponse {
    /// 是否已接收
    pub received: bool,
}

impl ChatResponse {
    /// 创建确认响应
    pub fn received() -> Self {
        Self { received: true }
    }
}

/// 聊天 Codec
///
/// 使用 JSON 序列化，带长度前缀的分帧协议。
#[derive(Debug, Clone, Default)]
pub struct ChatCodec;

#[async_trait]
impl request_response::Codec for ChatCodec {
    type Protocol = ChatProtocol;
    type Request = ChatRequest;
    type Response = ChatResponse;

    async fn read_request<T>(
        &mut self,
        _protocol: &Self::Protocol,
        io: &mut T,
    ) -> std::io::Result<Self::Request>
    where
        T: AsyncRead + Unpin + Send,
    {
        // 读取长度前缀（u32 big endian）
        let mut len_bytes = [0u8; 4];
        io.read_exact(&mut len_bytes).await?;
        let len = u32::from_be_bytes(len_bytes) as usize;

        // 限制最大消息大小（1MB）
        const MAX_MESSAGE_SIZE: usize = 1024 * 1024;
        if len > MAX_MESSAGE_SIZE {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("消息过大: {} 字节", len),
            ));
        }

        // 读取 JSON 数据
        let mut buffer = vec![0u8; len];
        io.read_exact(&mut buffer).await?;

        // 解析 JSON
        serde_json::from_slice::<ChatMessage>(&buffer)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
    }

    async fn read_response<T>(
        &mut self,
        _protocol: &Self::Protocol,
        io: &mut T,
    ) -> std::io::Result<Self::Response>
    where
        T: AsyncRead + Unpin + Send,
    {
        // 读取长度前缀（u32 big endian）
        let mut len_bytes = [0u8; 4];
        io.read_exact(&mut len_bytes).await?;
        let len = u32::from_be_bytes(len_bytes) as usize;

        // 限制最大消息大小
        const MAX_MESSAGE_SIZE: usize = 1024;
        if len > MAX_MESSAGE_SIZE {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("响应过大: {} 字节", len),
            ));
        }

        // 读取 JSON 数据
        let mut buffer = vec![0u8; len];
        io.read_exact(&mut buffer).await?;

        // 解析 JSON
        serde_json::from_slice::<ChatResponse>(&buffer)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
    }

    async fn write_request<T>(
        &mut self,
        _protocol: &Self::Protocol,
        io: &mut T,
        req: Self::Request,
    ) -> std::io::Result<()>
    where
        T: AsyncWrite + Unpin + Send,
    {
        // 序列化为 JSON
        let data = serde_json::to_vec(&req)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

        // 写入长度前缀（u32 big endian）
        let len = data.len() as u32;
        io.write_all(&len.to_be_bytes()).await?;

        // 写入数据
        io.write_all(&data).await?;
        io.flush().await
    }

    async fn write_response<T>(
        &mut self,
        _protocol: &Self::Protocol,
        io: &mut T,
        res: Self::Response,
    ) -> std::io::Result<()>
    where
        T: AsyncWrite + Unpin + Send,
    {
        // 序列化为 JSON
        let data = serde_json::to_vec(&res)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

        // 写入长度前缀（u32 big endian）
        let len = data.len() as u32;
        io.write_all(&len.to_be_bytes()).await?;

        // 写入数据
        io.write_all(&data).await?;
        io.flush().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chat_protocol() {
        assert_eq!(ChatProtocol.as_ref(), "/localp2p/chat/1.0.0");
    }

    #[test]
    fn test_chat_response() {
        let response = ChatResponse::received();
        assert!(response.received);
    }

    #[test]
    fn test_chat_codec_default() {
        let codec = ChatCodec::default();
        // 测试 Codec 可以创建
        assert_eq!(codec.protocol().as_ref(), CHAT_PROTOCOL);
    }
}

// 辅助函数，用于获取协议
impl ChatCodec {
    /// 获取协议
    pub fn protocol(&self) -> ChatProtocol {
        ChatProtocol
    }
}
