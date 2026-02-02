//! 全局配置管理
//!
//! 统一管理所有服务配置，包括：
//! - 网络配置（监听地址、端口）
//! - mDNS 配置
//! - 设备信息（Peer ID、设备名称）
//! - 存储路径（数据库、日志、证书）

use crate::{
    connection_service::ConnectionServiceConfig,
    config::MdnsConfig,
    managed_discovery::HealthCheckConfig,
    node::NodeManagerConfig,
    user_info::UserInfo,
};
use libp2p::{identity::Keypair, Multiaddr, PeerId};
use std::path::PathBuf;

/// 🔥 全局配置
///
/// 统一管理所有服务的配置项，在初始化前准备好，运行期间只读
#[derive(Debug, Clone)]
pub struct GlobalConfig {
    /// 工作目录（所有数据的根目录）
    pub work_dir: PathBuf,

    /// 数据目录（数据库文件）
    pub data_dir: PathBuf,

    /// 日志目录
    pub logs_dir: PathBuf,

    /// 证书目录
    pub certs_dir: PathBuf,

    /// 本地 Peer ID（从证书派生）
    pub local_peer_id: PeerId,

    /// 设备名称（用户可修改）
    pub device_name: String,

    /// 身份密钥对
    pub identity: Keypair,

    /// 监听地址列表
    pub listen_addresses: Vec<Multiaddr>,

    /// mDNS 配置
    pub mdns_config: MdnsConfig,

    /// 健康检查配置
    pub health_check_config: HealthCheckConfig,

    /// 连接服务配置
    pub connection_config: ConnectionServiceConfig,

    /// 节点管理器配置
    pub node_manager_config: NodeManagerConfig,

    /// 本地用户信息
    pub local_user_info: UserInfo,
}

impl GlobalConfig {
    /// 🔥 创建新的全局配置
    ///
    /// # Arguments
    /// * `work_dir` - 工作目录（所有数据的根目录）
    /// * `device_name` - 设备名称
    ///
    /// # 自动创建的子目录
    /// - `{work_dir}/data/` - 数据库文件
    /// - `{work_dir}/logs/` - 日志文件
    /// - `{work_dir}/certs/` - 证书文件
    pub async fn new(work_dir: PathBuf, device_name: String) -> Result<Self, String> {
        use tokio::fs;

        // 1. 创建目录结构
        let data_dir = work_dir.join("data");
        let logs_dir = work_dir.join("logs");
        let certs_dir = work_dir.join("certs");

        for dir in [&work_dir, &data_dir, &logs_dir, &certs_dir] {
            fs::create_dir_all(dir)
                .await
                .map_err(|e| format!("Failed to create directory {:?}: {}", dir, e))?;
        }

        // 2. 加载或创建身份密钥对
        let identity_path = certs_dir.join("identity.key");
        let identity = Self::load_or_create_identity(&identity_path).await?;

        // 3. 派生 Peer ID
        let local_peer_id = PeerId::from(identity.public());

        // 4. 创建本地用户信息
        let local_user_info = UserInfo::new(device_name.clone());

        // 5. 默认配置
        let mdns_config = MdnsConfig::default();
        let health_check_config = HealthCheckConfig::default();
        let connection_config = ConnectionServiceConfig::default();
        let node_manager_config = NodeManagerConfig::default();

        // 6. 默认监听地址（所有接口，随机端口）
        let listen_addresses = vec![
            "/ip4/0.0.0.0/tcp/0".parse().unwrap(),
            "/ip6/::/tcp/0".parse().unwrap(),
        ];

        Ok(Self {
            work_dir,
            data_dir,
            logs_dir,
            certs_dir,
            local_peer_id,
            device_name,
            identity,
            listen_addresses,
            mdns_config,
            health_check_config,
            connection_config,
            node_manager_config,
            local_user_info,
        })
    }

    /// 🔥 加载或创建身份密钥对
    async fn load_or_create_identity(path: &PathBuf) -> Result<Keypair, String> {
        use tokio::fs;

        // 如果文件存在，加载它
        if path.exists() {
            tracing::info!("🔑 加载身份密钥: {:?}", path);
            let bytes = fs::read(path)
                .await
                .map_err(|e| format!("Failed to read identity file: {}", e))?;

            return Keypair::from_protobuf_encoding(&bytes)
                .map_err(|e| format!("Failed to parse identity: {}", e));
        }

        // 否则创建新的密钥对
        tracing::info!("🔑 生成新的身份密钥: {:?}", path);
        let identity = Keypair::generate_ed25519();

        // 保存到文件
        let bytes = identity.to_protobuf_encoding()
            .map_err(|e| format!("Failed to encode identity: {}", e))?;

        fs::write(path, bytes)
            .await
            .map_err(|e| format!("Failed to write identity file: {}", e))?;

        Ok(identity)
    }

    /// 🔥 获取聊天数据库路径
    pub fn chat_db_path(&self) -> PathBuf {
        self.data_dir.join("chat.db")
    }

    /// 🔥 获取设备数据库路径（如果使用分离的设备数据库）
    pub fn devices_db_path(&self) -> PathBuf {
        self.data_dir.join("devices.db")
    }

    /// 🔥 获取日志文件路径（按日期）
    pub fn log_file_path(&self, date: &str) -> PathBuf {
        self.logs_dir.join(format!("localp2p_{}.log", date))
    }

    // ===== Builder 模式方法 =====

    /// 设置监听地址
    pub fn with_listen_addresses(mut self, addresses: Vec<Multiaddr>) -> Self {
        self.listen_addresses = addresses;
        self
    }

    /// 设置 mDNS 配置
    pub fn with_mdns_config(mut self, config: MdnsConfig) -> Self {
        self.mdns_config = config;
        self
    }

    /// 设置健康检查配置
    pub fn with_health_check_config(mut self, config: HealthCheckConfig) -> Self {
        self.health_check_config = config;
        self
    }

    /// 设置连接服务配置
    pub fn with_connection_config(mut self, config: ConnectionServiceConfig) -> Self {
        self.connection_config = config;
        self
    }

    /// 设置节点管理器配置
    pub fn with_node_manager_config(mut self, config: NodeManagerConfig) -> Self {
        self.node_manager_config = config;
        self
    }

    /// 🔥 转换为 P2PManagerConfig（向后兼容）
    pub fn to_p2p_config(&self) -> super::p2p_manager::P2PManagerConfig {
        super::p2p_manager::P2PManagerConfig {
            identity: Some(self.identity.clone()),
            node_manager_config: self.node_manager_config.clone(),
            node_manager: None,
            connection_config: self.connection_config.clone(),
            local_user_info: self.local_user_info.clone(),
            health_check_config: self.health_check_config.clone(),
            listen_addresses: self.listen_addresses.clone(),
            chat_db_path: Some(self.chat_db_path()),
        }
    }

    /// 🔥 打印配置摘要（用于调试）
    pub fn log_summary(&self) {
        tracing::info!("========================================");
        tracing::info!("📋 全局配置摘要");
        tracing::info!("========================================");
        tracing::info!("工作目录: {:?}", self.work_dir);
        tracing::info!("数据目录: {:?}", self.data_dir);
        tracing::info!("日志目录: {:?}", self.logs_dir);
        tracing::info!("证书目录: {:?}", self.certs_dir);
        tracing::info!("设备名称: {}", self.device_name);
        tracing::info!("Peer ID: {}", self.local_peer_id);
        tracing::info!("监听地址: {:?}", self.listen_addresses);
        tracing::info!("mDNS 间隔: {}ms", self.mdns_config.query_interval.as_millis());
        tracing::info!("聊天数据库: {:?}", self.chat_db_path());
        tracing::info!("========================================");
    }
}

/// 🔥 全局配置的共享引用
pub type SharedGlobalConfig = std::sync::Arc<GlobalConfig>;
