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
    node::{NodeManager, NodeManagerConfig, VerifiedNode},
    user_info::UserInfo,
    mdns_service::MdnsDiscoveryService,
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

    /// 节点管理器配置（仅在 node_manager 为 None 时使用）
    pub node_manager_config: NodeManagerConfig,

    /// ⚠️ 共享的 NodeManager 实例（可选）
    /// 如果提供，则使用此实例而不是创建新的
    /// 这对于 FFI 层非常重要，确保监控线程和 ConnectionService 使用同一个实例
    pub node_manager: Option<Arc<NodeManager>>,

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
            node_manager: None,
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

    /// ⚠️ 设置共享的 NodeManager 实例
    /// 如果调用此方法，P2PManager 将使用提供的实例而不是创建新的
    /// 这对于 FFI 层非常重要，确保监控线程和 ConnectionService 使用同一个实例
    pub fn with_node_manager(mut self, node_manager: Arc<NodeManager>) -> Self {
        self.node_manager = Some(node_manager);
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
/// 🔄 服务分离架构：
/// - MdnsDiscoveryService: mDNS 发现服务（独立后台任务）
/// - ConnectionService: 连接管理服务（独立后台任务）
/// ⚠️ 过渡期：保留 ManagedDiscovery 兼容性
pub struct P2PManager {
    /// ⚠️ 核心身份密钥对（所有服务共享）
    identity: Keypair,

    /// 派生的 Peer ID（从 identity 公钥计算）
    peer_id: PeerId,

    /// 节点管理器（共享）
    node_manager: Arc<NodeManager>,

    /// 本地用户信息
    local_user_info: UserInfo,

    /// 发现事件发送器（用于服务间通信）
    discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,

    /// 发现事件接收器（转移给 ConnectionService，使用 Option 便于 take）
    discovery_rx: Option<mpsc::UnboundedReceiver<DiscoveryEvent>>,

    /// ⚠️ ConnectionService 共享引用（用于外部访问，如发送消息）
    /// 使用 Arc<Mutex<>> 包装，允许从多个地方访问
    connection_service: Option<Arc<tokio::sync::Mutex<ConnectionService>>>,

    /// ManagedDiscovery（过渡期兼容）
    discovery: Option<ManagedDiscovery>,

    // 任务句柄（用于停止/重启）
    mdns_task: Option<tokio::task::JoinHandle<()>>,
    connection_task: Option<tokio::task::JoinHandle<()>>,

    /// mDNS 是否正在运行
    mdns_running: bool,

    /// 连接服务是否正在运行
    connection_running: bool,
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

        // 步骤 2: 使用提供的节点管理器或创建新的（共享）
        let node_manager = if let Some(nm) = config.node_manager {
            tracing::info!("使用提供的共享 NodeManager 实例");
            nm
        } else {
            tracing::info!("创建新的 NodeManager 实例");
            Arc::new(NodeManager::new(config.node_manager_config))
        };

        // 步骤 3: 保存本地用户信息
        let local_user_info = config.local_user_info;

        // 步骤 4: 创建事件通道（服务间通信）
        let (discovery_tx, discovery_rx) = mpsc::unbounded_channel();

        tracing::info!("✓ P2P 管理器初始化成功");

        Ok(Self {
            identity,
            peer_id,
            node_manager,
            local_user_info,
            discovery_tx,
            discovery_rx: Some(discovery_rx),
            connection_service: None,
            discovery: None,
            mdns_task: None,
            connection_task: None,
            mdns_running: false,
            connection_running: false,
        })
    }

    /// 启动 mDNS 服务（服务分离架构）
    pub async fn start_mdns(&mut self) -> Result<(), MdnsError> {
        if self.mdns_running {
            return Err(MdnsError::SwarmBuild("mDNS 服务已在运行".to_string()));
        }

        tracing::info!("正在启动 mDNS 发现服务（服务分离架构）...");

        // 创建 MdnsDiscoveryService
        let mdns_service = MdnsDiscoveryService::new(
            self.identity.clone(),
            self.discovery_tx.clone(),
        ).map_err(|e| MdnsError::SwarmBuild(format!("创建 mDNS 服务失败: {}", e)))?;

        // 启动后台任务（spawn 消费 self）
        let task = mdns_service.spawn();

        self.mdns_task = Some(task);
        self.mdns_running = true;

        tracing::info!("✓ mDNS 发现服务已启动（服务分离架构）");
        Ok(())
    }

    /// 启动连接服务（服务分离架构）
    pub async fn start_connection(&mut self) -> Result<(), MdnsError> {
        if self.connection_running {
            return Err(MdnsError::SwarmBuild("连接服务已在运行".to_string()));
        }

        tracing::info!("正在启动连接服务（服务分离架构）...");

        // 转移 discovery_rx（使用 Option::take）
        let discovery_rx = self.discovery_rx.take().ok_or_else(|| {
            MdnsError::SwarmBuild("discovery_rx 已被使用".to_string())
        })?;

        // 创建 ConnectionService
        let connection_service = ConnectionService::new(
            self.identity.clone(),
            self.node_manager.clone(),  // 传递共享的 NodeManager
            self.local_user_info.clone(),
            discovery_rx,
            ConnectionServiceConfig::default(),
        ).await?;

        // ⚠️ 关键：使用 Arc<Mutex<>> 包装 ConnectionService，允许外部访问
        let connection_service_shared = Arc::new(tokio::sync::Mutex::new(connection_service));

        // 在后台任务中运行 ConnectionService 事件循环
        let connection_service_for_task = connection_service_shared.clone();
        let task = tokio::spawn(async move {
            tracing::info!("🔗 连接服务事件循环已启动");
            loop {
                let mut service = connection_service_for_task.lock().await;
                match service.run_once().await {
                    Ok(true) => continue,  // 继续运行
                    Ok(false) => {
                        tracing::info!("连接服务正常退出");
                        break;
                    }
                    Err(e) => {
                        tracing::error!("连接服务错误: {:?}", e);
                        break;
                    }
                }
            }
            tracing::info!("🔗 连接服务事件循环已结束");
        });

        // 保存 ConnectionService 的共享引用
        self.connection_service = Some(connection_service_shared);
        self.connection_task = Some(task);
        self.connection_running = true;

        tracing::info!("✓ 连接服务已启动（服务分离架构）");
        Ok(())
    }

    /// 启动所有服务（服务分离架构）
    pub async fn start_all(&mut self) -> Result<(), MdnsError> {
        if self.mdns_running || self.connection_running {
            return Err(MdnsError::SwarmBuild("服务已在运行".to_string()));
        }

        tracing::info!("正在启动所有服务（服务分离架构）...");

        // 先启动连接服务（接收者先就绪）
        self.start_connection().await?;

        // 再启动 mDNS 服务（发送者）
        self.start_mdns().await?;

        tracing::info!("✓ 所有服务已启动（服务分离架构）");
        Ok(())
    }

    /// 启动所有服务（兼容模式：使用 ManagedDiscovery）
    pub async fn start_all_legacy(&mut self) -> Result<(), MdnsError> {
        if self.discovery.is_some() {
            return Err(MdnsError::SwarmBuild("服务已在运行".to_string()));
        }

        tracing::info!("正在启动所有服务（兼容模式：使用 ManagedDiscovery）...");

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

        tracing::info!("✓ 所有服务已启动（兼容模式：使用 ManagedDiscovery）");
        Ok(())
    }

    /// 🔄 重启 mDNS 服务（不影响连接）- 真正的服务分离实现
    ///
    /// 真正实现：只重启 mDNS 部分，保持 TCP 连接不断
    pub async fn restart_mdns(&mut self) -> Result<(), MdnsError> {
        tracing::info!("正在重启 mDNS 服务（服务分离架构）...");

        // 停止旧的 mDNS 任务
        if let Some(task) = self.mdns_task.take() {
            task.abort();
            let _ = tokio::time::timeout(
                tokio::time::Duration::from_secs(2),
                task
            ).await;
        }

        self.mdns_running = false;

        // 短暂等待（确保资源释放）
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        // 重新启动 mDNS 服务
        self.start_mdns().await?;

        tracing::info!("✓ mDNS 服务重启成功（TCP 连接保持不变）");
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

    /// ⚠️ 获取 ConnectionService 的共享引用（用于发送消息等操作）
    pub fn connection_service(&self) -> Option<Arc<tokio::sync::Mutex<ConnectionService>>> {
        self.connection_service.clone()
    }

    /// 发送聊天消息
    pub async fn send_message(&self, target_peer_id: String, message: String) -> Result<(), MdnsError> {
        use libp2p::PeerId;

        if let Some(connection_service) = &self.connection_service {
            let peer_id = target_peer_id.parse::<PeerId>()
                .map_err(|e| MdnsError::SwarmBuild(format!("无效的 Peer ID: {}", e)))?;

            let service = connection_service.lock().await;
            // 使用 ChatManager 发送消息
            if let Some(chat_manager) = service.chat_manager() {
                use crate::chat::ChatMessage;
                let msg = ChatMessage::text(message);
                chat_manager.send(peer_id, msg).await
                    .map_err(|e| MdnsError::SwarmBuild(format!("发送消息失败: {}", e)))?;
                Ok(())
            } else {
                Err(MdnsError::SwarmBuild("聊天管理器未初始化".to_string()))
            }
        } else {
            Err(MdnsError::SwarmBuild("连接服务未运行".to_string()))
        }
    }

    /// 停止所有服务
    pub async fn stop(&mut self) {
        tracing::info!("正在停止 P2P 管理器...");

        // 停止 mDNS（发送者先停）
        if let Some(task) = self.mdns_task.take() {
            task.abort();
            self.mdns_running = false;
            tracing::info!("✓ mDNS 服务已停止");
        }

        // 停止连接服务（接收者后停）
        if let Some(task) = self.connection_task.take() {
            task.abort();
            self.connection_running = false;
            tracing::info!("✓ 连接服务已停止");
        }

        // 也停止兼容模式的 discovery
        self.mdns_running = false;
        self.discovery = None;

        tracing::info!("✓ P2P 管理器已停止");
    }

    /// 检查是否使用服务分离架构
    pub fn is_using_separated_services(&self) -> bool {
        self.mdns_running || self.connection_running
    }

    /// 获取 ManagedDiscovery（供 FFI 层使用，过渡期方案）
    pub fn take_discovery(&mut self) -> Option<ManagedDiscovery> {
        if self.is_using_separated_services() {
            tracing::warn!("服务分离架构已启用，不支持 take_discovery()");
            None
        } else {
            self.discovery.take()
        }
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
