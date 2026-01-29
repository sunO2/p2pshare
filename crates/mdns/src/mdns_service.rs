//! mDNS 发现服务（独立运行）
//!
//! 提供 mDNS 服务发现功能，通过事件通道将发现的节点发送给连接服务。

use futures::StreamExt;
use libp2p::{
    mdns, identity::Keypair, PeerId, swarm::{Swarm, SwarmEvent}, SwarmBuilder,
    tcp, noise, yamux,
};
use tokio::sync::mpsc;
use crate::events::DiscoveryEvent;

/// mDNS 发现服务
///
/// 独立运行 mDNS 服务，将发现的设备通过事件通道发送给连接服务。
pub struct MdnsDiscoveryService {
    /// Swarm（只包含 mDNS behaviour）
    swarm: Swarm<mdns::tokio::Behaviour>,

    /// 发现事件发送器
    discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,

    /// 本地 Peer ID（从 identity 派生）
    local_peer_id: PeerId,
}

impl MdnsDiscoveryService {
    /// 创建新的 mDNS 发现服务
    pub fn new(
        identity: Keypair,
        discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,
    ) -> Result<Self, MdnsServiceError> {
        tracing::info!("正在初始化 mDNS 发现服务...");

        // 计算 Peer ID
        let local_peer_id = identity.public().to_peer_id();
        tracing::info!("mDNS 服务 Peer ID: {}", local_peer_id);

        // 创建 mDNS behaviour（在创建之前以避免 Result 嵌套问题）
        let config = mdns::Config::default();
        let peer: libp2p::PeerId = local_peer_id.into();
        let mdns_behaviour = mdns::tokio::Behaviour::new(config, peer)
            .map_err(|e| MdnsServiceError::InitializationFailed(e.to_string()))?;

        // 创建 mDNS Swarm（使用 TCP transport）
        let swarm = SwarmBuilder::with_existing_identity(identity)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )
            .map_err(|e| MdnsServiceError::InitializationFailed(format!("构建 TCP transport 失败: {}", e)))?
            .with_behaviour(|_key| mdns_behaviour)
            .map_err(|e| MdnsServiceError::InitializationFailed(format!("构建 behaviour 失败: {}", e)))?
            .with_swarm_config(|c| c)
            .build();

        tracing::info!("✓ mDNS 发现服务初始化成功");

        Ok(Self {
            swarm,
            discovery_tx,
            local_peer_id,
        })
    }

    /// 启动服务（返回任务句柄，消费 self）
    pub fn spawn(self) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            tracing::info!("🔍 mDNS 发现服务已启动");
            self.run().await;
        })
    }

    /// 运行 mDNS 事件循环（消费 self）
    async fn run(mut self) {
        loop {
            match self.swarm.select_next_some().await {
                SwarmEvent::Behaviour(event) => {
                    if let Err(e) = self.handle_mdns_event(event).await {
                        tracing::error!("处理 mDNS 事件失败: {}", e);
                    }
                }
                SwarmEvent::NewListenAddr { address, .. } => {
                    tracing::debug!("mDNS 服务监听地址: {}", address);
                }
                _ => {
                    tracing::trace!("mDNS 服务收到其他 Swarm 事件");
                }
            }
        }
    }

    /// 处理 mDNS 事件
    async fn handle_mdns_event(
        &mut self,
        event: mdns::Event,
    ) -> Result<(), MdnsServiceError> {
        match event {
            mdns::Event::Discovered(list) => {
                for (peer_id, addr) in list {
                    tracing::info!("🔍 mDNS 发现设备: {} at {}", peer_id, addr);
                    let _ = self.discovery_tx.send(DiscoveryEvent::Discovered { peer_id, addr });
                }
            }
            mdns::Event::Expired(list) => {
                for (peer_id, _addr) in list {
                    tracing::debug!("🔍 mDNS 设备过期: {}", peer_id);
                    let _ = self.discovery_tx.send(DiscoveryEvent::Expired { peer_id });
                }
            }
        }
        Ok(())
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> &PeerId {
        &self.local_peer_id
    }
}

/// mDNS 服务错误
#[derive(Debug, thiserror::Error)]
pub enum MdnsServiceError {
    #[error("初始化失败: {0}")]
    InitializationFailed(String),

    #[error("发送事件失败: {0}")]
    SendFailed(String),
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::mpsc;

    #[tokio::test]
    async fn test_mdns_service_creation() {
        // 创建测试用 identity 和事件通道
        let identity = Keypair::generate_ed25519();
        let (discovery_tx, _discovery_rx) = mpsc::unbounded_channel();

        // 创建 mDNS 服务
        let result = MdnsDiscoveryService::new(identity, discovery_tx);

        // 验证创建成功
        assert!(result.is_ok(), "mDNS 服务创建应该成功");

        let service = result.unwrap();
        let peer_id = service.local_peer_id();

        // 验证 Peer ID 有效
        assert!(!peer_id.to_string().is_empty(), "Peer ID 不应为空");

        println!("✓ mDNS 服务创建测试通过，Peer ID: {}", peer_id);
    }

    #[tokio::test]
    async fn test_mdns_service_spawn() {
        // 创建测试用 identity 和事件通道
        let identity = Keypair::generate_ed25519();
        let (discovery_tx, _discovery_rx) = mpsc::unbounded_channel();

        // 创建 mDNS 服务
        let service = MdnsDiscoveryService::new(identity, discovery_tx).unwrap();

        // 启动服务（返回任务句柄）
        let task = service.spawn();

        // 验证任务已创建
        assert!(!task.is_finished(), "任务应该正在运行");

        // 清理：中止任务
        task.abort();

        println!("✓ mDNS 服务启动测试通过");
    }
}
