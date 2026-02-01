//! 管理式服务发现模块
//!
//! 集成 identify 验证、用户信息交换和 ping 心跳，自动管理验证通过的节点。
//!
//! ⚠️ 注意：此模块不再包含 mDNS 发现功能。
//! mDNS 功能已迁移到 `mdns_discovery` 模块（基于 libmdns）。

use super::{node::{NodeManager, VerifiedNode}, user_info, MdnsError};
use super::chat::{ChatExtension, ChatManager, ChatMessage, ChatError, manager::ChatDatabaseConfig};
use futures::StreamExt;
use libp2p::{
    identify, ping, request_response, Swarm, SwarmBuilder, identity::Keypair, Multiaddr, PeerId,
};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

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
/// 使用 identify 协议验证，交换用户信息，验证通过后添加到节点管理器。
///
/// ⚠️ 注意：mDNS 发现功能已迁移到 `mdns_discovery` 模块。
/// 此模块负责连接、验证、心跳和用户信息交换。
///
/// ## 组合 Behaviour 说明
///
/// libp2p 0.56 使用 `#[derive(NetworkBehaviour)]` 宏组合多个 behaviour。
/// 这里我们组合了：
/// - `identify`: 用于节点身份验证和信息交换
/// - `request_response`: 用于用户信息交换（自定义协议）
/// - `ping`: 用于心跳检测（自动发送）
pub struct ManagedDiscovery {
    swarm: Swarm<ManagedBehaviour>,
    node_manager: Arc<NodeManager>,
    local_user_info: user_info::UserInfo,
    protocol_version: String,
    agent_version: String,
    health_status: HashMap<PeerId, NodeHealth>,
    health_config: HealthCheckConfig,
    /// 跟踪每个节点的活跃连接数
    active_connections: HashMap<PeerId, u32>,
    /// 已收到的用户信息
    peer_user_info: HashMap<PeerId, user_info::UserInfo>,
    /// 可选的聊天管理器
    chat_manager: Option<Arc<ChatManager>>,
    /// 聊天事件接收器（用于处理聊天消息）
    chat_event_rx: Option<mpsc::UnboundedReceiver<super::chat::ChatEvent>>,
    /// 聊天数据库路径（可选）
    chat_db_path: Option<PathBuf>,
}

/// 组合的 Behaviour，包含 identify、ping 和 request_response
///
/// 使用 libp2p 的 `#[derive(NetworkBehaviour)]` 宏组合多个 behaviour
#[derive(libp2p::swarm::NetworkBehaviour)]
struct ManagedBehaviour {
    identify: identify::Behaviour,
    ping: ping::Behaviour,
    request_response: request_response::Behaviour<user_info::UserInfoCodec>,
    /// 聊天协议（使用 request_response 模式）
    chat: request_response::Behaviour<crate::chat::ChatCodec>,
}

impl ManagedDiscovery {
    /// 创建新的管理式服务发现器
    ///
    /// # Arguments
    /// * `node_manager` - 节点管理器
    /// * `listen_addresses` - 监听地址列表
    /// * `health_config` - 健康检查配置
    /// * `local_user_info` - 本地用户信息
    /// * `identity` - 可选的密钥对，如果为 None 则生成新的
    pub async fn new(
        node_manager: Arc<NodeManager>,
        listen_addresses: Vec<Multiaddr>,
        health_config: HealthCheckConfig,
        local_user_info: user_info::UserInfo,
        identity: Option<Keypair>,
    ) -> std::result::Result<Self, MdnsError> {
        // 使用提供的密钥对，或生成新的
        let local_key = identity.unwrap_or_else(|| {
            tracing::info!("生成新的 ed25519 密钥对");
            Keypair::generate_ed25519()
        });

        let peer_id = local_key.public().to_peer_id();
        tracing::info!("使用密钥对生成 Peer ID: {}", peer_id);

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
            .map_err(|e| {
                tracing::error!("TCP transport build failed: {:?}", e);
                MdnsError::SwarmBuild(format!("TCP: {}", e))
            })?
            .with_behaviour(|_key| {
                let identify = identify::Behaviour::new(
                    identify::Config::new(protocol_version.clone(), _key.public())
                        .with_agent_version(agent_version.clone())
                        .with_interval(Duration::from_secs(30))
                );

                let ping = ping::Behaviour::new(ping::Config::default());

                // 创建 request_response Behaviour 用于用户信息交换
                let request_response = request_response::Behaviour::new(
                    [(user_info::UserInfoProtocol, request_response::ProtocolSupport::Full)],
                    request_response::Config::default(),
                );

                // 创建 request_response Behaviour 用于聊天
                let chat = request_response::Behaviour::new(
                    [(crate::chat::ChatProtocol, request_response::ProtocolSupport::Full)],
                    request_response::Config::default(),
                );

                Ok(ManagedBehaviour { identify, ping, request_response, chat })
            })
            .map_err(|e| {
                tracing::error!("Behaviour build failed: {:?}", e);
                MdnsError::SwarmBuild(format!("Behaviour: {}", e))
            })?
            .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
            .build();

        for addr in listen_addresses {
            swarm.listen_on(addr)
                .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?;
        }

        Ok(Self {
            swarm,
            node_manager,
            local_user_info,
            protocol_version,
            agent_version,
            health_status: HashMap::new(),
            health_config,
            active_connections: HashMap::new(),
            peer_user_info: HashMap::new(),
            chat_manager: None,
            chat_event_rx: None,
            chat_db_path: None,
        })
    }

    /// 设置聊天数据库路径
    ///
    /// 必须在 enable_chat 之前调用，否则数据库将使用默认路径
    pub fn set_chat_db_path(&mut self, path: PathBuf) {
        self.chat_db_path = Some(path);
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
                libp2p::swarm::SwarmEvent::Behaviour(ManagedBehaviourEvent::Identify(event)) => {
                    match event {
                        identify::Event::Received { peer_id, info, .. } => {
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

                                    // ⭐ 标记为在线（如果之前是离线状态）
                                    self.node_manager.mark_node_online(&peer_id).await;

                                    if is_already_verified {
                                        // 已验证过，只更新不返回事件（静默更新）
                                        tracing::debug!("更新已验证节点: {}", peer_id);
                                    } else {
                                        // 首次验证，记录日志并返回事件
                                        tracing::info!("收到来自 {} 的 identify 信息", peer_id);
                                        tracing::debug!("  协议版本: {}", info.protocol_version);
                                        tracing::debug!("  代理版本: {}", info.agent_version);
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
                    let ping::Event { peer, result, .. } = event;
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

                                // 标记节点为离线（而不是移除）
                                if self.node_manager.mark_node_offline(&peer, "Ping 失败").await {
                                    tracing::info!("已标记节点为离线: {}", peer);
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
                    tracing::info!("✓ 与 {} 建立新连接", peer_id);
                    let conn_count = self.active_connections.entry(peer_id).or_insert(0);
                    let is_first_connection = *conn_count == 0;
                    *conn_count += 1;

                    if is_first_connection {
                        tracing::info!("与 {} 建立首个连接，请求用户信息", peer_id);
                        // 仅在首个连接建立时请求用户信息
                        let _ = self.swarm.behaviour_mut().request_response.send_request(
                            &peer_id,
                            user_info::UserInfoRequest,
                        );
                    } else {
                        tracing::info!("与 {} 建立额外连接 (当前连接数: {})", peer_id, *conn_count);
                    }
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

                        // 标记节点为离线（而不是移除）
                        if self.node_manager.mark_node_offline(&peer_id, "连接关闭").await {
                            tracing::info!("已标记节点为离线: {}", peer_id);
                        }

                        return Ok(DiscoveryEvent::NodeOffline(peer_id));
                    }
                }
                libp2p::swarm::SwarmEvent::Behaviour(ManagedBehaviourEvent::RequestResponse(event)) => {
                    match event {
                        request_response::Event::Message { peer, connection_id: _, message } => match message {
                            request_response::Message::Request {
                                request_id: _,
                                channel,
                                request: _,
                            } => {
                                tracing::debug!("收到来自 {} 的用户信息请求", peer);

                                // 响应用户信息请求
                                let response = user_info::UserInfoResponse {
                                    device_name: self.local_user_info.device_name.clone(),
                                    nickname: self.local_user_info.nickname.clone(),
                                    avatar_url: self.local_user_info.avatar_url.clone(),
                                    status: self.local_user_info.status.clone(),
                                    custom_data: self.local_user_info.custom_data.clone(),
                                };

                                let _ = self.swarm.behaviour_mut().request_response.send_response(
                                    channel,
                                    response,
                                );
                            }
                            request_response::Message::Response {
                                request_id: _,
                                response,
                            } => {
                                // 检查是否已经收到过该节点的用户信息
                                let is_new_info = !self.peer_user_info.contains_key(&peer);

                                // 存储或更新用户信息
                                self.peer_user_info.insert(peer, response.clone());

                                if is_new_info {
                                    // 首次收到用户信息，记录日志并返回事件
                                    tracing::info!("📝 收到来自 {} 的用户信息: {}", peer, response.display_name());
                                    return Ok(DiscoveryEvent::UserInfoReceived(peer, response));
                                } else {
                                    // 已收到过，只更新不返回事件（静默更新）
                                    tracing::debug!("更新来自 {} 的用户信息: {}", peer, response.display_name());
                                }
                            }
                        },
                        _ => {
                            // 忽略其他事件类型
                            tracing::debug!("其他 request_response 事件");
                        }
                    }
                }
                libp2p::swarm::SwarmEvent::Behaviour(ManagedBehaviourEvent::Chat(event)) => {
                    tracing::info!("收到聊天事件: {:?}", std::mem::discriminant(&event));
                    match event {
                        request_response::Event::Message { peer, connection_id: _, message } => match message {
                            request_response::Message::Request {
                                request_id: _,
                                channel,
                                request,
                            } => {
                                tracing::info!("📨 收到来自 {} 的聊天消息: {:?}", peer, request);

                                // 处理收到的聊天消息
                                if let Some(ref chat_manager) = self.chat_manager {
                                    chat_manager.handle_received_message(peer, request.clone()).await;
                                } else {
                                    tracing::warn!("聊天管理器未初始化，无法处理消息");
                                }

                                // 发送确认响应
                                let response = crate::chat::ChatResponse::received();
                                tracing::info!("发送确认响应给 {}", peer);
                                let _ = self.swarm.behaviour_mut().chat.send_response(
                                    channel,
                                    response,
                                );
                            }
                            request_response::Message::Response {
                                request_id: _,
                                response: _,
                            } => {
                                tracing::info!("✓ 收到来自 {} 的聊天消息确认", peer);
                                // 可以在这里更新消息发送状态
                            }
                        },
                        _ => {
                            // 忽略其他事件类型
                            tracing::debug!("其他聊天事件");
                        }
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

    /// 获取节点的用户信息
    pub fn get_user_info(&self, peer_id: &PeerId) -> Option<&user_info::UserInfo> {
        self.peer_user_info.get(peer_id)
    }

    /// 获取所有用户信息
    pub fn list_user_info(&self) -> HashMap<PeerId, user_info::UserInfo> {
        self.peer_user_info.clone()
    }

    /// 获取本地用户信息
    pub fn local_user_info(&self) -> &user_info::UserInfo {
        &self.local_user_info
    }

    /// 获取聊天事件接收器
    ///
    /// 这是一个 consuming 操作，调用后 `chat_event_rx` 将被移除。
    pub fn take_chat_events(&mut self) -> Option<mpsc::UnboundedReceiver<super::chat::ChatEvent>> {
        self.chat_event_rx.take()
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

    /// 收到用户信息
    UserInfoReceived(PeerId, user_info::UserInfo),
}

/// 为 ManagedDiscovery 实现 ChatExtension trait
///
/// 提供可选的聊天功能扩展。
#[async_trait::async_trait]
impl ChatExtension for ManagedDiscovery {
    /// 启用聊天功能
    async fn enable_chat(&mut self) -> Result<(), ChatError> {
        // 检查是否已经启用
        if self.chat_manager.is_some() {
            return Err(ChatError::SendFailed("聊天功能已经启用".to_string()));
        }

        // 创建数据库配置
        let db_config = if let Some(ref db_path) = self.chat_db_path {
            ChatDatabaseConfig {
                db_path: db_path.clone(),
                enabled: true,
            }
        } else {
            ChatDatabaseConfig::default()
        };

        // 创建 ChatManager（使用数据库配置）
        let (chat_manager, event_rx) = ChatManager::with_db_config(
            self.node_manager.clone(),
            self.local_peer_id(),
            db_config,
        );

        // 保存管理器和事件接收器
        self.chat_manager = Some(Arc::new(chat_manager));
        self.chat_event_rx = Some(event_rx);

        tracing::info!("✓ 聊天功能已启用");
        Ok(())
    }

    /// 发送消息给指定节点
    async fn send_message(&mut self, target: PeerId, message: ChatMessage) -> Result<(), ChatError> {
        if let Some(ref chat_manager) = self.chat_manager {
            // 1. 先通过 ChatManager 验证和设置消息元数据
            chat_manager.send(target, message.clone()).await?;

            // 2. 实际通过 Swarm 的 chat behaviour 发送消息
            let _request_id = self.swarm.behaviour_mut().chat.send_request(&target, message);

            Ok(())
        } else {
            Err(ChatError::NotEnabled)
        }
    }

    /// 广播消息给多个节点（一对多）
    async fn broadcast_message(&mut self, targets: Vec<PeerId>, message: ChatMessage) -> Result<(), ChatError> {
        if let Some(ref chat_manager) = self.chat_manager {
            // 1. 先通过 ChatManager 验证和设置消息元数据
            chat_manager.broadcast(targets.clone(), message.clone()).await?;

            // 2. 为每个目标实际发送消息
            for target in targets {
                tracing::info!("尝试向 {} 发送聊天消息", target);

                // 检查连接状态
                let has_connection = self.swarm.is_connected(&target);
                tracing::info!("与 {} 的连接状态: {}", target, if has_connection { "已连接" } else { "未连接" });

                if !has_connection {
                    tracing::warn!("没有与 {} 的活跃连接，尝试拨号...", target);
                    // 尝试从已知的地址拨号
                    if let Some(node) = self.node_manager.get_node(&target).await {
                        for addr in &node.addresses {
                            tracing::info!("正在向 {} 拨号: {}", target, addr);
                            match self.swarm.dial(addr.clone()) {
                                Ok(_) => tracing::info!("拨号请求已发送"),
                                Err(e) => tracing::error!("拨号失败: {:?}", e),
                            }
                        }
                        // 等待连接建立
                        tokio::time::sleep(Duration::from_millis(200)).await;

                        // 再次检查连接状态
                        let still_not_connected = !self.swarm.is_connected(&target);
                        if still_not_connected {
                            tracing::error!("拨号后仍未与 {} 建立连接", target);
                            continue;
                        }
                    } else {
                        tracing::error!("找不到节点 {} 的地址信息", target);
                        continue;
                    }
                }

                // 发送请求
                let request_id = self.swarm.behaviour_mut().chat.send_request(&target, message.clone());
                tracing::info!("消息发送请求已接受，ID: {:?}", request_id);
            }

            Ok(())
        } else {
            Err(ChatError::NotEnabled)
        }
    }

    /// 获取聊天管理器
    fn chat_manager(&self) -> Option<Arc<ChatManager>> {
        self.chat_manager.clone()
    }
}
