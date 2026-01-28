//! 密钥对持久化模块
//!
//! 提供密钥对的保存和加载功能，用于持久化 Peer ID

use libp2p::identity::Keypair;
use std::fs;
use std::io::{Read, Write};
use std::path::Path;

/// 密钥对持久化管理器
pub struct IdentityManager;

impl IdentityManager {
    /// 从文件加载密钥对
    ///
    /// 如果文件存在，加载密钥对；如果文件不存在或加载失败，返回 None
    ///
    /// # Arguments
    /// * `path` - 密钥文件路径
    ///
    /// # Returns
    /// * `Ok(Some(Keypair))` - 成功加载密钥对
    /// * `Ok(None)` - 文件不存在（首次运行）
    /// * `Err(String)` - 加载失败
    pub fn load_or_none(path: &Path) -> Result<Option<Keypair>, String> {
        // 检查文件是否存在
        if !path.exists() {
            tracing::info!("密钥文件不存在，将生成新密钥: {}", path.display());
            return Ok(None);
        }

        // 读取文件内容
        let mut file = match fs::File::open(path) {
            Ok(f) => f,
            Err(e) => {
                let msg = format!("无法打开密钥文件: {} - {}", path.display(), e);
                tracing::error!("{}", msg);
                return Err(msg);
            }
        };

        let mut buffer = Vec::new();
        if let Err(e) = file.read_to_end(&mut buffer) {
            let msg = format!("读取密钥文件失败: {} - {}", path.display(), e);
            tracing::error!("{}", msg);
            return Err(msg);
        }

        // 解析密钥对
        match Self::decode_keypair(&buffer) {
            Ok(keypair) => {
                tracing::info!("成功加载密钥对: {}", path.display());
                Ok(Some(keypair))
            }
            Err(e) => {
                let msg = format!("解析密钥对失败: {}", e);
                tracing::error!("{}", msg);
                Err(msg)
            }
        }
    }

    /// 生成并保存新的密钥对
    ///
    /// # Arguments
    /// * `path` - 密钥保存路径
    ///
    /// # Returns
    /// * `Ok(Keypair)` - 成功生成并保存密钥对
    /// * `Err(String)` - 操作失败
    pub fn generate_and_save(path: &Path) -> Result<Keypair, String> {
        // 生成新的 ed25519 密钥对
        let keypair = Keypair::generate_ed25519();

        // 序列化密钥对
        let encoded = Self::encode_keypair(&keypair)?;

        // 确保父目录存在
        if let Some(parent) = path.parent() {
            if let Err(e) = fs::create_dir_all(parent) {
                let msg = format!("创建目录失败: {} - {}", parent.display(), e);
                tracing::error!("{}", msg);
                return Err(msg);
            }
        }

        // 写入文件
        let mut file = match fs::File::create(path) {
            Ok(f) => f,
            Err(e) => {
                let msg = format!("创建密钥文件失败: {} - {}", path.display(), e);
                tracing::error!("{}", msg);
                return Err(msg);
            }
        };

        if let Err(e) = file.write_all(&encoded) {
            let msg = format!("写入密钥文件失败: {} - {}", path.display(), e);
            tracing::error!("{}", msg);
            return Err(msg);
        }

        // 设置文件权限为仅所有者可读写 (0600)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Err(e) = fs::set_permissions(path, fs::Permissions::from_mode(0o600)) {
                tracing::warn!("设置密钥文件权限失败: {} - {}", path.display(), e);
            }
        }

        tracing::info!("成功生成并保存密钥对: {}", path.display());
        Ok(keypair)
    }

    /// 加载或生成密钥对
    ///
    /// 如果文件存在则加载，否则生成新的并保存
    ///
    /// # Arguments
    /// * `path` - 密钥文件路径
    ///
    /// # Returns
    /// * `Ok(Keypair)` - 密钥对
    /// * `Err(String)` - 操作失败
    pub fn load_or_generate(path: &Path) -> Result<Keypair, String> {
        match Self::load_or_none(path)? {
            Some(keypair) => Ok(keypair),
            None => Self::generate_and_save(path),
        }
    }

    /// 编码密钥对为字节数组
    ///
    /// 使用 libp2p 的 Protobuf 编码格式
    fn encode_keypair(keypair: &Keypair) -> Result<Vec<u8>, String> {
        // 使用 libp2p 提供的 protobuf 编码
        match keypair.to_protobuf_encoding() {
            Ok(bytes) => Ok(bytes),
            Err(e) => Err(format!("密钥编码失败: {:?}", e)),
        }
    }

    /// 从字节数组解码密钥对
    ///
    /// # Arguments
    /// * `bytes` - 编码的密钥对字节数组
    ///
    /// # Returns
    /// * `Ok(Keypair)` - 解码的密钥对
    /// * `Err(String)` - 解码失败
    fn decode_keypair(bytes: &[u8]) -> Result<Keypair, String> {
        // 使用 libp2p 提供的 protobuf 解码
        match Keypair::from_protobuf_encoding(bytes) {
            Ok(keypair) => Ok(keypair),
            Err(e) => Err(format!("密钥解码失败: {:?}", e)),
        }
    }

    /// 删除密钥文件
    ///
    /// # Arguments
    /// * `path` - 密钥文件路径
    ///
    /// # Returns
    /// * `Ok(())` - 成功删除或文件不存在
    /// * `Err(String)` - 删除失败
    pub fn delete(path: &Path) -> Result<(), String> {
        if path.exists() {
            fs::remove_file(path)
                .map_err(|e| format!("删除密钥文件失败: {} - {}", path.display(), e))?;
            tracing::info!("已删除密钥文件: {}", path.display());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[tokio::test]
    async fn test_generate_and_save() {
        let temp_file = NamedTempFile::new().unwrap();
        let path = temp_file.path();

        // 生成并保存密钥对
        let keypair1 = IdentityManager::generate_and_save(path).unwrap();
        let peer_id1 = keypair1.public().to_peer_id();

        // 再次加载应该返回相同的密钥对
        let keypair2 = IdentityManager::load_or_generate(path).unwrap();
        let peer_id2 = keypair2.public().to_peer_id();

        // Peer ID 应该相同
        assert_eq!(peer_id1, peer_id2);
    }

    #[tokio::test]
    async fn test_load_or_generate() {
        let temp_file = NamedTempFile::new().unwrap();
        let path = temp_file.path();

        // 删除文件以确保不存在
        let _ = std::fs::remove_file(path);

        // 首次调用应该生成新密钥
        let keypair1 = IdentityManager::load_or_generate(path).unwrap();
        let peer_id1 = keypair1.public().to_peer_id();

        // 第二次调用应该加载相同的密钥
        let keypair2 = IdentityManager::load_or_generate(path).unwrap();
        let peer_id2 = keypair2.public().to_peer_id();

        // Peer ID 应该相同
        assert_eq!(peer_id1, peer_id2);
    }

    #[tokio::test]
    async fn test_delete() {
        let temp_file = NamedTempFile::new().unwrap();
        let path = temp_file.path();

        // 生成密钥
        IdentityManager::generate_and_save(path).unwrap();
        assert!(path.exists());

        // 删除密钥
        IdentityManager::delete(path).unwrap();
        assert!(!path.exists());

        // 删除不存在的文件应该成功
        IdentityManager::delete(path).unwrap();
    }
}
