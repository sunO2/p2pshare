//! mDNS 服务发现模块

use super::{MdnsConfig, Result, MdnsError};
use libp2p::{
    mdns,
    Swarm,
    SwarmBuilder,
    identity::Keypair,
    Multiaddr,
    PeerId,
};
use futures::StreamExt;
use std::collections::HashMap;

/// 发现的对等节点信息
#[derive(Debug, Clone)]
pub struct DiscoveredPeer {
    /// 对等节点 ID
    pub peer_id: PeerId,

    /// 对等节点地址列表
    pub addresses: Vec<Multiaddr>,
}

/// mDNS 服务发现器
pub struct MdnsDiscovery {
    swarm: Swarm<mdns::tokio::Behaviour>,
    discovered_peers: HashMap<PeerId, Vec<Multiaddr>>,
}

impl MdnsDiscovery {
    /// 创建新的服务发现器
    pub async fn new(config: MdnsConfig) -> Result<Self> {
        let local_key = Keypair::generate_ed25519();

        // 使用 libp2p 0.56 的 SwarmBuilder API 构建 Swarm
        // 对于 mDNS，我们需要一个基础的 transport，即使我们不直接使用它
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
            .with_swarm_config(|c| c.with_idle_connection_timeout(std::time::Duration::from_secs(60)))
            .build();

        for addr in config.listen_addresses {
            swarm.listen_on(addr)
                .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?;
        }

        Ok(Self {
            swarm,
            discovered_peers: HashMap::new(),
        })
    }

    /// 启动发现服务
    pub async fn run(&mut self) -> Result<DiscoveredEvent> {
        loop {
            match self.swarm.select_next_some().await {
                libp2p::swarm::SwarmEvent::Behaviour(mdns::Event::Discovered(list)) => {
                    for (peer_id, addr) in list {
                        tracing::info!("发现对等节点: {} at {}", peer_id, addr);
                        self.discovered_peers
                            .entry(peer_id)
                            .or_insert_with(Vec::new)
                            .push(addr);
                        return Ok(DiscoveredEvent::PeerFound(DiscoveredPeer {
                            peer_id,
                            addresses: self.discovered_peers.get(&peer_id).cloned().unwrap_or_default(),
                        }));
                    }
                }
                libp2p::swarm::SwarmEvent::Behaviour(mdns::Event::Expired(list)) => {
                    for (peer_id, addr) in list {
                        tracing::info!("对等节点过期: {} at {}", peer_id, addr);
                        if let Some(addrs) = self.discovered_peers.get_mut(&peer_id) {
                            addrs.retain(|a| a != &addr);
                            if addrs.is_empty() {
                                self.discovered_peers.remove(&peer_id);
                                return Ok(DiscoveredEvent::PeerExpired(peer_id));
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }

    /// 获取所有已发现的节点
    pub fn discovered_peers(&self) -> HashMap<PeerId, Vec<Multiaddr>> {
        self.discovered_peers.clone()
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> PeerId {
        *self.swarm.local_peer_id()
    }
}

/// 发现事件
#[derive(Debug, Clone)]
pub enum DiscoveredEvent {
    /// 发现新的对等节点
    PeerFound(DiscoveredPeer),

    /// 对等节点过期
    PeerExpired(PeerId),
}
