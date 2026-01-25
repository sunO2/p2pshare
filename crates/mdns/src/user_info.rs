//! 用户信息交换协议
//!
//! 自定义协议，用于在节点之间交换用户信息（设备名称、用户名、头像等）。

use async_trait::async_trait;
use futures::{AsyncRead, AsyncWrite, AsyncReadExt, AsyncWriteExt};
use libp2p::request_response;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 用户信息协议名称
pub const USER_INFO_PROTOCOL: &str = "/localp2p/user-info/1.0.0";

/// 用户信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserInfo {
    /// 设备名称（如："我的电脑"、"客厅电视"）
    pub device_name: String,

    /// 用户昵称（可选）
    pub nickname: Option<String>,

    /// 头像 URL（可选）
    pub avatar_url: Option<String>,

    /// 用户状态（如："在线"、"忙碌"）
    pub status: Option<String>,

    /// 自定义扩展数据
    #[serde(flatten)]
    pub custom_data: HashMap<String, String>,
}

impl UserInfo {
    /// 创建新的用户信息
    pub fn new(device_name: String) -> Self {
        Self {
            device_name,
            nickname: None,
            avatar_url: None,
            status: None,
            custom_data: HashMap::new(),
        }
    }

    /// 设置昵称
    pub fn with_nickname(mut self, nickname: String) -> Self {
        self.nickname = Some(nickname);
        self
    }

    /// 设置头像 URL
    pub fn with_avatar_url(mut self, url: String) -> Self {
        self.avatar_url = Some(url);
        self
    }

    /// 设置状态
    pub fn with_status(mut self, status: String) -> Self {
        self.status = Some(status);
        self
    }

    /// 添加自定义数据
    pub fn with_custom_data(mut self, key: String, value: String) -> Self {
        self.custom_data.insert(key, value);
        self
    }

    /// 获取显示名称（优先使用昵称，否则使用设备名）
    pub fn display_name(&self) -> String {
        self.nickname
            .as_ref()
            .unwrap_or(&self.device_name)
            .clone()
    }
}

/// 用户信息协议（标记类型）
#[derive(Debug, Clone, Default)]
pub struct UserInfoProtocol;

impl AsRef<str> for UserInfoProtocol {
    fn as_ref(&self) -> &str {
        USER_INFO_PROTOCOL
    }
}

/// 用户信息请求（空）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserInfoRequest;

/// 用户信息响应
pub type UserInfoResponse = UserInfo;

/// 用户信息 Codec
///
/// 使用 JSON 序列化，带长度前缀的分帧协议。
#[derive(Debug, Clone, Default)]
pub struct UserInfoCodec;

#[async_trait]
impl request_response::Codec for UserInfoCodec {
    type Protocol = UserInfoProtocol;
    type Request = UserInfoRequest;
    type Response = UserInfoResponse;

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

        // 读取 JSON 数据
        let mut buffer = vec![0u8; len];
        io.read_exact(&mut buffer).await?;

        // 解析 JSON（UserInfoRequest 是空结构体，任何 JSON 都可以解析）
        serde_json::from_slice::<UserInfoRequest>(&buffer)
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

        // 读取 JSON 数据
        let mut buffer = vec![0u8; len];
        io.read_exact(&mut buffer).await?;

        // 解析 JSON
        serde_json::from_slice::<UserInfo>(&buffer)
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
    fn test_user_info_creation() {
        let info = UserInfo::new("我的电脑".to_string())
            .with_nickname("开发者".to_string())
            .with_status("在线".to_string());

        assert_eq!(info.device_name, "我的电脑");
        assert_eq!(info.nickname, Some("开发者".to_string()));
        assert_eq!(info.status, Some("在线".to_string()));
    }

    #[test]
    fn test_display_name() {
        let info1 = UserInfo::new("设备".to_string())
            .with_nickname("昵称".to_string());
        assert_eq!(info1.display_name(), "昵称");

        let info2 = UserInfo::new("设备".to_string());
        assert_eq!(info2.display_name(), "设备");
    }

    #[test]
    fn test_user_info_serialization() {
        let info = UserInfo::new("我的电脑".to_string())
            .with_nickname("开发者".to_string())
            .with_status("在线".to_string());

        // 测试序列化和反序列化
        let json = serde_json::to_string(&info).unwrap();
        let deserialized: UserInfo = serde_json::from_str(&json).unwrap();

        assert_eq!(info.device_name, deserialized.device_name);
        assert_eq!(info.nickname, deserialized.nickname);
        assert_eq!(info.status, deserialized.status);
    }
}
