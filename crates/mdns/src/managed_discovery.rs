//! 管理式服务发现模块
//!
//! 集成 mDNS 发现、identify 验证和 ping 心跳，自动管理验证通过的节点。

use super::{node::{NodeManager, VerifiedNode}, MdnsError};
use futures::StreamExt;
use libp2p::{
    identify, mdns, ping, Swarm, SwarmBuilder, identity::Keypair, Multiaddr, PeerId,
};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

/// 健康状态
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HealthStatus {
    /// 未知（尚未检查）
    Unknown,
    /// 健康（最近有心跳响应）
    Healthy,
    /// 不健康（连续多次失败）
    Unhealthy,
}

/// 节点健康信息
#[derive(Debug, Clone)]
pub struct NodeHealth {
    /// 连续失败次数
    pub consecutive_failures: u32,
    /// 最后成功心跳时间
    pub last_success: Option<Instant>,
    /// 最后失败心跳时间
    pub last_failure: Option<Instant>,
    /// 平均往返时间 (RTT)
    pub average_rtt: Option<Duration>,
    /// 当前健康状态
    pub status: HealthStatus,
}

impl NodeHealth {
    /// 创建新的健康信息
    pub fn new() -> Self {
        Self {
            consecutive_failures: 0,
            last_success: None,
            last_failure: None,
            average_rtt: None,
            status: HealthStatus::Unknown,
        }
    }

    /// 记录心跳成功
    pub fn record_success(&mut self, rtt: Duration) {
        self.consecutive_failures = 0;
        self.last_success = Some(Instant::now());
        self.last_failure = None;
        self.status = HealthStatus::Healthy;

        // 简单的移动平均
        if let Some(avg) = self.average_rtt {
            self.average_rtt = Some((avg + rtt) / 2);
        } else {
            self.average_rtt = Some(rtt);
        }
    }

    /// 记录心跳失败
    pub fn record_failure(&mut self, max_failures: u32) {
        self.consecutive_failures += 1;
        self.last_failure = Some(Instant::now());

        if self.consecutive_failures >= max_failures {
            self.status = HealthStatus::Unhealthy;
        }
    }

    /// 检查是否离线
    pub fn is_offline(&self) -> bool {
        self.status == HealthStatus::Unhealthy
    }
}

/// 健康检查配置
#[derive(Debug, Clone)]
pub struct HealthCheckConfig {
    /// 心跳间隔
    pub heartbeat_interval: Duration,
    /// 连续失败次数阈值
    pub max_failures: u32,
}

impl Default for HealthCheckConfig {
    fn default() -> Self {
        Self {
            heartbeat_interval: Duration::from_secs(10),
            max_failures: 3,
        }
    }
}

/// 管理式服务发现器
///
/// 通过 mDNS 发现节点，使用 identify 协议验证，验证通过后添加到节点管理器。
///
/// ## 组合 Behaviour 说明
///
/// libp2p 0.56 使用 `#[derive(NetworkBehaviour)]` 宏组合多个 behaviour。
/// 这里我们组合了：
/// - `mdns`: 用于局域网内节点发现
/// - `identify`: 用于节点身份验证和信息交换
/// - `ping`: 用于心跳检测（自动发送）
pub struct ManagedDiscovery {
    swarm: Swarm<ManagedBehaviour>,
    node_manager: Arc<NodeManager>,
    protocol_version: String,
    agent_version: String,
    health_status: HashMap<PeerId, NodeHealth>,
    health_config: HealthCheckConfig,
    /// 跟踪每个节点的活跃连接数
    active_connections: HashMap<PeerId, u32>,
}

/// 组合的 Behaviour，包含 mDNS、identify 和 ping
///
/// 使用 libp2p 的 `#[derive(NetworkBehaviour)]` 宏组合多个 behaviour
#[derive(libp2p::swarm::NetworkBehaviour)]
struct ManagedBehaviour {
    mdns: mdns::tokio::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
}

impl ManagedDiscovery {
    /// 创建新的管理式服务发现器
    pub async fn new(
        node_manager: Arc<NodeManager>,
        listen_addresses: Vec<Multiaddr>,
        health_config: HealthCheckConfig,
    ) -> std::result::Result<Self, MdnsError> {
        let local_key = Keypair::generate_ed25519();

        let config = node_manager.config();
        let protocol_version = config.expected_protocol_version.clone();
        let agent_version = config.build_agent_version();

        // 创建组合 behaviour
        let mut swarm = SwarmBuilder::with_existing_identity(local_key)
            .with_tokio()
            .with_tcp(
                libp2p::tcp::Config::default(),
                libp2p::noise::Config::new,
                libp2p::yamux::Config::default,
            )
            .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?
            .with_behaviour(|_key| {
                let mdns = mdns::tokio::Behaviour::new(
                    mdns::Config::default(),
                    _key.public().into()
                ).expect("mdns behaviour creation failed");

                let identify = identify::Behaviour::new(
                    identify::Config::new(protocol_version.clone(), _key.public())
                        .with_agent_version(agent_version.clone())
                        .with_interval(Duration::from_secs(30))
                );

                let ping = ping::Behaviour::new(ping::Config::default());

                Ok(ManagedBehaviour { mdns, identify, ping })
            })
            .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?
            .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
            .build();

        for addr in listen_addresses {
            swarm.listen_on(addr)
                .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?;
        }

        Ok(Self {
            swarm,
            node_manager,
            protocol_version,
            agent_version,
            health_status: HashMap::new(),
            health_config,
            active_connections: HashMap::new(),
        })
    }

    /// 运行发现服务
    ///
    /// 这个方法会持续运行，处理 mDNS 发现事件和 identify 验证事件。
    /// 验证通过的节点会被自动添加到节点管理器中。
    ///
    /// 注意：libp2p 的 ping behaviour 会自动对所有已连接的节点发送周期性心跳。
    pub async fn run(&mut self) -> std::result::Result<DiscoveryEvent, MdnsError> {
        loop {
            match self.swarm.select_next_some().await {
                libp2p::swarm::SwarmEvent::Behaviour(ManagedBehaviourEvent::Mdns(event)) => {
                    match event {
                        mdns::Event::Discovered(list) => {
                            for (peer_id, addr) in list {
                                tracing::info!("通过 mDNS 发现节点: {} at {}", peer_id, addr);

                                // 尝试主动连接该节点以触发 identify 验证
                                if let Err(e) = self.swarm.dial(addr.clone()) {
                                    tracing::debug!("无法主动连接节点 {}: {}", peer_id, e);
                                }

                                return Ok(DiscoveryEvent::Discovered(peer_id, addr));
                            }
                        }
                        mdns::Event::Expired(list) => {
                            for (peer_id, _addr) in list {
                                tracing::info!("节点 mDNS 记录过期: {}", peer_id);
                                return Ok(DiscoveryEvent::Expired(peer_id));
                            }
                        }
                    }
                }
                libp2p::swarm::SwarmEvent::Behaviour(ManagedBehaviourEvent::Identify(event)) => {
                    match event {
                        identify::Event::Received { peer_id, info, .. } => {
                            tracing::info!("收到来自 {} 的 identify 信息", peer_id);
                            tracing::debug!("  协议版本: {}", info.protocol_version);
                            tracing::debug!("  代理版本: {}", info.agent_version);

                            // 验证节点信息
                            match self.node_manager.verify_node_info(
                                &info.protocol_version,
                                &info.agent_version,
                            ) {
                                Ok(()) => {
                                    // 检查是否是自己的 Peer ID
                                    if peer_id == self.local_peer_id() {
                                        tracing::debug!("跳过自己: {}", peer_id);
                                        continue;
                                    }

                                    // 检查是否已经验证过（避免重复返回事件）
                                    let is_already_verified = self.node_manager.is_node_verified(&peer_id).await;

                                    // 验证通过，添加到节点管理器
                                    let addresses = info
                                        .listen_addrs
                                        .iter()
                                        .cloned()
                                        .collect();

                                    let node = VerifiedNode::new(
                                        peer_id,
                                        addresses,
                                        info.protocol_version.clone(),
                                        info.agent_version.clone(),
                                    );

                                    self.node_manager.add_or_update_node(node).await;

                                    if is_already_verified {
                                        // 已验证过，只更新不返回事件
                                        tracing::debug!("更新已验证节点: {}", peer_id);
                                    } else {
                                        // 首次验证，返回事件
                                        tracing::info!("✓ 节点 {} 验证通过，已添加到管理器", peer_id);
                                        return Ok(DiscoveryEvent::Verified(peer_id));
                                    }
                                }
                                Err(e) => {
                                    tracing::warn!("✗ 节点 {} 验证失败: {}", peer_id, e);
                                    return Ok(DiscoveryEvent::VerificationFailed(
                                        peer_id,
                                        e.to_string(),
                                    ));
                                }
                            }
                        }
                        identify::Event::Sent { .. } => {
                            tracing::debug!("已发送 identify 信息");
                        }
                        identify::Event::Error { error, .. } => {
                            tracing::error!("identify 错误: {}", error);
                        }
                        _ => {}
                    }
                }
                libp2p::swarm::SwarmEvent::Behaviour(ManagedBehaviourEvent::Ping(event)) => {
                    let ping::Event { peer, connection: _, result } = event;
                    match result {
                        Ok(rtt) => {
                            tracing::debug!("收到 {} 的 pong，RTT: {:?}", peer, rtt);

                            let health = self.health_status
                                .entry(peer)
                                .or_insert_with(|| NodeHealth::new());

                            let was_offline = health.is_offline();
                            health.record_success(rtt);

                            if was_offline {
                                tracing::info!("💚 节点 {} 恢复健康", peer);
                                return Ok(DiscoveryEvent::NodeRecovered(peer, rtt));
                            }
                        }
                        Err(_e) => {
                            tracing::warn!("❤️ 节点 {} ping 失败", peer);

                            let health = self.health_status
                                .entry(peer)
                                .or_insert_with(|| NodeHealth::new());

                            let was_healthy = health.status == HealthStatus::Healthy;
                            health.record_failure(self.health_config.max_failures);

                            if health.is_offline() && was_healthy {
                                tracing::warn!("💔 节点 {} 被判定为离线", peer);

                                // 从节点管理器中移除离线节点
                                if self.node_manager.remove_node(&peer).await.is_some() {
                                    tracing::info!("已从管理器中移除离线节点 {}", peer);
                                }

                                return Ok(DiscoveryEvent::NodeOffline(peer));
                            }
                        }
                    }
                }
                libp2p::swarm::SwarmEvent::NewListenAddr { address, .. } => {
                    tracing::info!("开始监听: {}", address);
                }
                libp2p::swarm::SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                    tracing::debug!("与 {} 建立连接", peer_id);
                    *self.active_connections.entry(peer_id).or_insert(0) += 1;
                }
                libp2p::swarm::SwarmEvent::ConnectionClosed { peer_id, .. } => {
                    tracing::debug!("与 {} 的连接关闭", peer_id);
                    let conn_count = self.active_connections.entry(peer_id).or_insert(0);
                    if *conn_count > 0 {
                        *conn_count -= 1;
                    }

                    // 如果该节点没有活跃连接了，标记为离线
                    if *conn_count == 0 {
                        tracing::warn!("💔 节点 {} 的所有连接已关闭，判定为离线", peer_id);

                        // 从节点管理器中移除离线节点
                        if self.node_manager.remove_node(&peer_id).await.is_some() {
                            tracing::info!("已从管理器中移除离线节点 {}", peer_id);
                        }

                        return Ok(DiscoveryEvent::NodeOffline(peer_id));
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

    /// 获取节点管理器
    pub fn node_manager(&self) -> Arc<NodeManager> {
        self.node_manager.clone()
    }

    /// 获取协议版本
    pub fn protocol_version(&self) -> &str {
        &self.protocol_version
    }

    /// 获取代理版本
    pub fn agent_version(&self) -> &str {
        &self.agent_version
    }

    /// 获取节点的健康信息
    pub fn get_health(&self, peer_id: &PeerId) -> Option<&NodeHealth> {
        self.health_status.get(peer_id)
    }

    /// 移除节点的健康信息
    pub fn remove_health(&mut self, peer_id: &PeerId) {
        self.health_status.remove(peer_id);
    }

    /// 获取健康检查配置
    pub fn health_config(&self) -> &HealthCheckConfig {
        &self.health_config
    }
}

/// 发现事件
#[derive(Debug, Clone)]
pub enum DiscoveryEvent {
    /// 通过 mDNS 发现节点
    Discovered(PeerId, Multiaddr),

    /// 节点 mDNS 记录过期
    Expired(PeerId),

    /// 节点验证通过
    Verified(PeerId),

    /// 节点验证失败
    VerificationFailed(PeerId, String),

    /// 节点恢复健康
    NodeRecovered(PeerId, Duration),

    /// 节点离线
    NodeOffline(PeerId),
}
