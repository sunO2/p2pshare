//! mDNS 服务发布模块

use super::{MdnsConfig, ServiceInfo, Result, MdnsError};
use libp2p::{
    mdns,
    Swarm,
    SwarmBuilder,
    identity::Keypair,
    PeerId,
};
use futures::StreamExt;
use std::time::Duration;

/// mDNS 服务发布器
pub struct MdnsPublisher {
    swarm: Swarm<mdns::tokio::Behaviour>,
    service_info: Option<ServiceInfo>,
}

impl MdnsPublisher {
    /// 创建新的服务发布器
    pub async fn new(config: MdnsConfig) -> Result<Self> {
        let local_key = Keypair::generate_ed25519();

        // 使用 libp2p 0.56 的 SwarmBuilder API 构建 Swarm
        let mut swarm = SwarmBuilder::with_existing_identity(local_key)
            .with_tokio()
            .with_tcp(
                libp2p::tcp::Config::default(),
                libp2p::noise::Config::new,
                libp2p::yamux::Config::default,
            )
            .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?
            .with_behaviour(|_key| {
                mdns::tokio::Behaviour::new(mdns::Config::default(), _key.public().into())
                    .expect("mdns behaviour creation failed")
            })
            .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?
            .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
            .build();

        for addr in config.listen_addresses {
            swarm.listen_on(addr)
                .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?;
        }

        Ok(Self {
            swarm,
            service_info: config.service_info,
        })
    }

    /// 启动服务发布
    pub async fn run(&mut self) -> Result<()> {
        if let Some(ref info) = self.service_info {
            tracing::info!(
                "发布服务: {} ({}) on port {}",
                info.name,
                info.service_type,
                info.port
            );
        }

        loop {
            match self.swarm.select_next_some().await {
                libp2p::swarm::SwarmEvent::Behaviour(mdns::Event::Discovered(list)) => {
                    for (peer_id, addr) in list {
                        tracing::debug!("发现对等节点: {} at {}", peer_id, addr);
                    }
                }
                libp2p::swarm::SwarmEvent::Behaviour(mdns::Event::Expired(list)) => {
                    for (peer_id, addr) in list {
                        tracing::debug!("对等节点过期: {} at {}", peer_id, addr);
                    }
                }
                _ => {}
            }
        }
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> PeerId {
        *self.swarm.local_peer_id()
    }

    /// 获取服务信息
    pub fn service_info(&self) -> Option<&ServiceInfo> {
        self.service_info.as_ref()
    }
}
