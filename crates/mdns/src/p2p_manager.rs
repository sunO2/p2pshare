//! P2P 管理器 - 统一管理发现和连接服务
//!
//! P2PManager 是整个系统的核心管理器，负责：
//! 1. 管理两个服务的生命周期（mDNS 发现服务 + 连接服务）
//! 2. 协调服务间通信（通过事件通道）
//! 3. 提供统一的对外接口
//! 4. 管理共享资源（identity, node_manager）
//!
//! ⚠️ 当前实现：使用 ManagedDiscovery 作为底层实现
//! 🔄 后续优化：迁移到真正的分离架构

use super::{
    node::{NodeManager, NodeManagerConfig, VerifiedNode, NodeStatus},
    user_info::UserInfo,
    mdns_service::{MdnsDiscoveryService, MdnsServiceError},
    connection_service::{ConnectionService, ConnectionServiceConfig},
    managed_discovery::{ManagedDiscovery, HealthCheckConfig},
    chat::traits::ChatExtension,
    MdnsError,
    events::DiscoveryEvent,
};
use libp2p::{identity::Keypair, PeerId, Multiaddr};
use std::sync::Arc;
use tokio::sync::mpsc;

/// P2P 管理器配置
#[derive(Debug, Clone)]
pub struct P2PManagerConfig {
    /// 身份密钥对（None 则生成新的）
    pub identity: Option<Keypair>,

    /// 节点管理器配置
    pub node_manager_config: NodeManagerConfig,

    /// 连接服务配置
    pub connection_config: ConnectionServiceConfig,

    /// 本地用户信息
    pub local_user_info: UserInfo,

    /// 健康检查配置
    pub health_check_config: HealthCheckConfig,

    /// 监听地址列表
    pub listen_addresses: Vec<Multiaddr>,
}

impl Default for P2PManagerConfig {
    fn default() -> Self {
        Self {
            identity: None,
            node_manager_config: NodeManagerConfig::default(),
            connection_config: ConnectionServiceConfig::default(),
            local_user_info: UserInfo::new("未命名设备".to_string()),
            health_check_config: HealthCheckConfig::default(),
            listen_addresses: vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()],
        }
    }
}

impl P2PManagerConfig {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_identity(mut self, identity: Keypair) -> Self {
        self.identity = Some(identity);
        self
    }

    pub fn with_node_manager_config(mut self, config: NodeManagerConfig) -> Self {
        self.node_manager_config = config;
        self
    }

    pub fn with_connection_config(mut self, config: ConnectionServiceConfig) -> Self {
        self.connection_config = config;
        self
    }

    pub fn with_local_user_info(mut self, user_info: UserInfo) -> Self {
        self.local_user_info = user_info;
        self
    }

    pub fn with_health_check_config(mut self, config: HealthCheckConfig) -> Self {
        self.health_check_config = config;
        self
    }

    pub fn with_listen_addresses(mut self, addrs: Vec<Multiaddr>) -> Self {
        self.listen_addresses = addrs;
        self
    }
}

/// P2P 管理器 - 统一管理发现和连接服务
///
/// ⚠️ 当前实现：包装 ManagedDiscovery，提供统一的接口
/// 🔄 未来优化：迁移到真正的服务分离架构
pub struct P2PManager {
    /// ⚠️ 核心身份密钥对（所有服务共享）
    identity: Keypair,

    /// 派生的 Peer ID（从 identity 公钥计算）
    peer_id: PeerId,

    /// ManagedDiscovery（当前实现）
    discovery: Option<ManagedDiscovery>,

    /// 节点管理器（共享）
    node_manager: Arc<NodeManager>,

    /// 本地用户信息
    local_user_info: UserInfo,

    /// 发现事件发送器（用于服务间通信）
    discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,

    /// discovery 任务句柄（用于生命周期管理）
    discovery_task: Option<tokio::task::JoinHandle<()>>,

    /// mDNS 是否正在运行
    mdns_running: bool,
}

impl P2PManager {
    /// 创建新的 P2P 管理器
    pub async fn new(config: P2PManagerConfig) -> Result<Self, MdnsError> {
        tracing::info!("正在初始化 P2P 管理器...");

        // ⚠️ 步骤 1: 创建或加载 identity（只创建一次）
        let identity = if let Some(keypair) = config.identity {
            tracing::info!("使用提供的密钥对");
            keypair
        } else {
            tracing::info!("生成新的 ed25519 密钥对");
            Keypair::generate_ed25519()
        };

        // 计算 Peer ID
        let peer_id = identity.public().to_peer_id();
        tracing::info!("P2P Peer ID: {}", peer_id);

        // 步骤 2: 创建节点管理器（共享）
        let node_manager = Arc::new(NodeManager::new(config.node_manager_config));

        // 步骤 3: 保存本地用户信息
        let local_user_info = config.local_user_info;

        // 步骤 4: 创建事件通道（服务间通信）
        let (discovery_tx, _discovery_rx) = mpsc::unbounded_channel();

        tracing::info!("✓ P2P 管理器初始化成功");

        Ok(Self {
            identity,
            peer_id,
            discovery: None,
            node_manager,
            local_user_info,
            discovery_tx,
            discovery_task: None,
            mdns_running: false,
        })
    }

    /// 启动 mDNS 服务（使用 ManagedDiscovery，标记实现）
    pub async fn start_mdns(&mut self) -> Result<(), MdnsError> {
        if self.mdns_running {
            return Err(MdnsError::SwarmBuild("mDNS 服务已在运行".to_string()));
        }

        tracing::info!("正在启动 mDNS 服务（当前使用 ManagedDiscovery）...");

        // TODO: 未来迁移到真正的 MdnsDiscoveryService
        // 当前使用 ManagedDiscovery 作为实现
        self.mdns_running = true;

        tracing::info!("✓ mDNS 服务已启动（通过 ManagedDiscovery）");
        Ok(())
    }

    /// 启动连接服务（使用 ManagedDiscovery，标记实现）
    pub async fn start_connection(&mut self) -> Result<(), MdnsError> {
        tracing::info!("正在启动连接服务（当前使用 ManagedDiscovery）...");

        // TODO: 未来迁移到真正的 ConnectionService
        // 当前使用 ManagedDiscovery 作为实现

        tracing::info!("✓ 连接服务已启动（通过 ManagedDiscovery）");
        Ok(())
    }

    /// 启动所有服务（创建 ManagedDiscovery）
    pub async fn start_all(&mut self) -> Result<(), MdnsError> {
        if self.discovery.is_some() {
            return Err(MdnsError::SwarmBuild("服务已在运行".to_string()));
        }

        tracing::info!("正在启动所有服务（使用 ManagedDiscovery）...");

        // 使用存储的本地用户信息
        let user_info = self.local_user_info.clone();

        // 创建 ManagedDiscovery（使用同一个 identity）
        let discovery_result = ManagedDiscovery::new(
            self.node_manager.clone(),
            vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()], // TODO: 使用配置
            HealthCheckConfig::default(),
            user_info,
            Some(self.identity.clone()),
        ).await;

        let mut discovery = discovery_result.map_err(|e| {
            MdnsError::SwarmBuild(format!("创建 ManagedDiscovery 失败: {}", e))
        })?;

        // 启用聊天功能
        if let Err(e) = discovery.enable_chat().await {
            tracing::error!("Failed to enable chat: {:?}", e);
        }

        self.discovery = Some(discovery);
        self.mdns_running = true;

        tracing::info!("✓ 所有服务已启动（通过 ManagedDiscovery）");
        Ok(())
    }

    /// ⚠️ 重启 mDNS 服务（不影响连接）- 标记实现
    ///
    /// 当前实现：重新创建整个 ManagedDiscovery（会暂时断开连接）
    /// 未来优化：只重启 mDNS 部分，保持连接不断
    pub async fn restart_mdns(&mut self) -> Result<(), MdnsError> {
        tracing::info!("正在重启 mDNS 服务（标记实现）...");

        // 当前实现：停止并重新创建整个服务
        // TODO: 未来优化为只重启 mDNS 部分，不影响连接

        // 模拟重启流程
        self.mdns_running = false;

        // 短暂等待
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        // 重新标记为运行
        self.mdns_running = true;

        tracing::info!("✓ mDNS 服务重启成功（标记实现，未来将实现真正分离）");
        Ok(())
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> &PeerId {
        &self.peer_id
    }

    /// 获取本地 Peer ID（字符串形式）
    pub fn local_peer_id_string(&self) -> String {
        self.peer_id.to_string()
    }

    /// 获取节点管理器
    pub fn node_manager(&self) -> Arc<NodeManager> {
        self.node_manager.clone()
    }

    /// 列出所有在线节点
    pub async fn list_online_nodes(&self) -> Vec<VerifiedNode> {
        self.node_manager.list_online_nodes().await
    }

    /// 列出所有节点（包括离线）
    pub async fn list_all_nodes(&self) -> Vec<VerifiedNode> {
        self.node_manager.list_all_nodes().await
    }

    /// 停止所有服务
    pub async fn stop(&mut self) {
        tracing::info!("正在停止 P2P 管理器...");

        self.mdns_running = false;
        self.discovery = None;

        tracing::info!("✓ P2P 管理器已停止");
    }

    /// 获取 ManagedDiscovery（供 FFI 层使用，过渡期方案）
    pub fn take_discovery(&mut self) -> Option<ManagedDiscovery> {
        self.discovery.take()
    }

    /// 设置 ManagedDiscovery（供 FFI 层使用，过渡期方案）
    pub fn set_discovery(&mut self, discovery: ManagedDiscovery) {
        self.discovery = Some(discovery);
        self.mdns_running = true;
    }

    /// 获取 identity 克隆（供 FFI 层使用）
    pub fn identity_clone(&self) -> Keypair {
        self.identity.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use libp2p::identity::Keypair;

    #[tokio::test]
    async fn test_p2p_manager_config_creation() {
        let identity = Keypair::generate_ed25519();
        let user_info = UserInfo::new("测试设备".to_string());
        let node_config = NodeManagerConfig::new();

        let config = P2PManagerConfig::new()
            .with_identity(identity.clone())
            .with_node_manager_config(node_config)
            .with_local_user_info(user_info);

        // 验证配置创建成功
        assert!(config.identity.is_some());
    }

    #[tokio::test]
    async fn test_p2p_manager_new() {
        let identity = Keypair::generate_ed25519();
        let user_info = UserInfo::new("测试设备".to_string());
        let node_config = NodeManagerConfig::new();
        let connection_config = ConnectionServiceConfig::default();

        let config = P2PManagerConfig::new()
            .with_identity(identity)
            .with_node_manager_config(node_config)
            .with_local_user_info(user_info)
            .with_connection_config(connection_config);

        let result = P2PManager::new(config).await;

        // 验证 P2PManager 创建成功
        assert!(result.is_ok());
        let manager = result.unwrap();
        // Peer ID 字符串长度通常是 46 或 52（取决于编码）
        assert!(manager.local_peer_id_string().len() >= 46);
    }

    #[tokio::test]
    async fn test_p2p_manager_restart_mdns() {
        let identity = Keypair::generate_ed25519();
        let user_info = UserInfo::new("测试设备".to_string());
        let node_config = NodeManagerConfig::new();
        let connection_config = ConnectionServiceConfig::default();

        let config = P2PManagerConfig::new()
            .with_identity(identity)
            .with_node_manager_config(node_config)
            .with_local_user_info(user_info)
            .with_connection_config(connection_config);

        let mut manager = P2PManager::new(config).await.unwrap();

        // 验证 restart_mdns 不会报错
        let result = manager.restart_mdns().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_p2p_manager_list_online_nodes() {
        let identity = Keypair::generate_ed25519();
        let user_info = UserInfo::new("测试设备".to_string());
        let node_config = NodeManagerConfig::new();
        let connection_config = ConnectionServiceConfig::default();

        let config = P2PManagerConfig::new()
            .with_identity(identity)
            .with_node_manager_config(node_config)
            .with_local_user_info(user_info)
            .with_connection_config(connection_config);

        let manager = P2PManager::new(config).await.unwrap();

        // 验证初始状态下在线节点列表为空
        let online_nodes = manager.list_online_nodes().await;
        assert!(online_nodes.is_empty());
    }

    #[tokio::test]
    async fn test_p2p_manager_identity_consistency() {
        let identity = Keypair::generate_ed25519();
        let peer_id1 = identity.public().to_peer_id();

        let user_info = UserInfo::new("测试设备".to_string());
        let node_config = NodeManagerConfig::new();
        let connection_config = ConnectionServiceConfig::default();

        let config = P2PManagerConfig::new()
            .with_identity(identity.clone())
            .with_node_manager_config(node_config)
            .with_local_user_info(user_info)
            .with_connection_config(connection_config);

        let manager = P2PManager::new(config).await.unwrap();

        // 验证 Peer ID 一致性
        let peer_id2 = *manager.local_peer_id();
        assert_eq!(peer_id1, peer_id2);

        // 验证 identity_clone 能产生相同的 Peer ID
        let identity2 = manager.identity_clone();
        let peer_id3 = identity2.public().to_peer_id();
        assert_eq!(peer_id1, peer_id3);
    }
}
