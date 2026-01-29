//! 连接管理服务（独立运行）
//!
//! 负责与已发现的节点建立连接、验证身份、维护心跳等功能。

use super::{
    node::{NodeManager, NodeManagerConfig},
    user_info, MdnsError, events::DiscoveryEvent,
    chat::{ChatManager, ChatMessage},
};
use futures::StreamExt;
use libp2p::{
    identify, ping, request_response, Swarm, SwarmBuilder,
    identity::{Keypair, PeerId},
    Multiaddr, swarm::{NetworkBehaviour, ConnectionHandler},
};
use std::sync::Arc;
use std::collections::HashMap;
use tokio::sync::mpsc;

/// 全局聊天事件回调（可选）
/// 由 FFI 层设置，用于将聊天事件发送到 Flutter
static mut CHAT_EVENT_CALLBACK: Option<fn(from: String, content: String)> = None;

/// 设置聊天事件回调
///
/// # Safety
/// 此函数应在初始化时调用一次
pub unsafe fn set_chat_event_callback(callback: fn(from: String, content: String)) {
    CHAT_EVENT_CALLBACK = Some(callback);
}

/// 连接服务配置
#[derive(Debug, Clone)]
pub struct ConnectionServiceConfig {
    /// 监听地址列表
    pub listen_addresses: Vec<Multiaddr>,

    /// Identify 更新间隔
    pub identify_interval: std::time::Duration,

    /// 空闲连接超时
    pub idle_connection_timeout: std::time::Duration,
}

impl Default for ConnectionServiceConfig {
    fn default() -> Self {
        Self {
            listen_addresses: vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()],
            identify_interval: std::time::Duration::from_secs(30),
            idle_connection_timeout: std::time::Duration::from_secs(60),
        }
    }
}

/// 连接 Behaviour（不包含 mDNS）
#[derive(NetworkBehaviour)]
struct ConnectionBehaviour {
    identify: identify::Behaviour,
    ping: ping::Behaviour,
    request_response: request_response::Behaviour<user_info::UserInfoCodec>,
    /// 聊天协议（使用 request_response 模式）
    chat: request_response::Behaviour<crate::chat::ChatCodec>,
}

/// 连接管理服务（独立运行）
pub struct ConnectionService {
    /// Swarm（不包含 mDNS）
    swarm: Swarm<ConnectionBehaviour>,

    /// 节点管理器（共享）
    node_manager: Arc<NodeManager>,

    /// 发现事件接收器
    discovery_rx: mpsc::UnboundedReceiver<DiscoveryEvent>,

    /// 本地用户信息
    local_user_info: user_info::UserInfo,

    /// 协议版本
    protocol_version: String,

    /// 代理版本
    agent_version: String,

    /// 跟踪每个节点的活跃连接数
    active_connections: HashMap<PeerId, u32>,

    /// 已收到的用户信息
    peer_user_info: HashMap<PeerId, user_info::UserInfo>,

    /// 聊天管理器
    chat_manager: Option<ChatManager>,

    /// 聊天事件接收器
    chat_event_rx: Option<mpsc::UnboundedReceiver<super::chat::ChatEvent>>,

    /// 本地 Peer ID
    local_peer_id: PeerId,
}

impl ConnectionService {
    /// 创建新的连接服务
    ///
    /// ⚠️ 重要：接受共享的 NodeManager 引用，而不是创建新的！
    /// 这确保 ConnectionService 添加的节点可以被 P2PManager 和 FFI 层访问。
    pub async fn new(
        identity: Keypair,
        node_manager: Arc<NodeManager>,  // 改为接受共享的 NodeManager
        local_user_info: user_info::UserInfo,
        discovery_rx: mpsc::UnboundedReceiver<DiscoveryEvent>,
        config: ConnectionServiceConfig,
    ) -> Result<Self, MdnsError> {
        tracing::info!("正在初始化连接服务...");

        let local_peer_id = identity.public().to_peer_id();
        let protocol_version = node_manager.config().expected_protocol_version.clone();
        let agent_version = node_manager.config().build_agent_version();

        // 创建聊天管理器（使用共享的 NodeManager）
        let (chat_manager, chat_event_rx) = ChatManager::new(node_manager.clone(), local_peer_id);
        tracing::info!("✓ 聊天管理器已创建");

        // ⚠️ 关键：使用同一个 identity 创建 Swarm（不包含 mDNS）
        let mut swarm = SwarmBuilder::with_existing_identity(identity)
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
            .with_behaviour(|key| {
                let identify = identify::Behaviour::new(
                    identify::Config::new(
                        node_manager.config().expected_protocol_version.clone(),
                        key.public()
                    )
                    .with_agent_version(node_manager.config().build_agent_version())
                    .with_interval(std::time::Duration::from_secs(30))
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

                Ok(ConnectionBehaviour { identify, ping, request_response, chat })
            })
            .map_err(|e| {
                tracing::error!("Behaviour build failed: {:?}", e);
                MdnsError::SwarmBuild(format!("Behaviour: {}", e))
            })?
            .with_swarm_config(|c| c.with_idle_connection_timeout(std::time::Duration::from_secs(60)))
            .build();

        // 开始监听
        for addr in config.listen_addresses {
            swarm.listen_on(addr)
                .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?;
        }

        tracing::info!("✓ 连接服务初始化成功，Peer ID: {}", local_peer_id);

        Ok(Self {
            swarm,
            node_manager,
            discovery_rx,
            local_user_info,
            protocol_version,
            agent_version,
            active_connections: HashMap::new(),
            peer_user_info: HashMap::new(),
            chat_manager: Some(chat_manager),
            chat_event_rx: Some(chat_event_rx),
            local_peer_id,
        })
    }

    /// 连接到指定的节点
    pub async fn connect(&mut self, peer_id: PeerId, addr: Multiaddr) {
        tracing::info!("正在连接到 {} at {}", peer_id, addr);

        if let Err(e) = self.swarm.dial(addr.clone()) {
            tracing::warn!("无法连接到 {} at {}: {}", peer_id, addr, e);
        }
    }

    /// 获取节点管理器
    pub fn node_manager(&self) -> Arc<NodeManager> {
        self.node_manager.clone()
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> PeerId {
        self.local_peer_id
    }

    /// 获取聊天管理器（用于发送消息）
    pub fn chat_manager(&self) -> Option<&ChatManager> {
        self.chat_manager.as_ref()
    }

    /// 发送聊天消息
    pub async fn send_chat_message(&self, target: PeerId, message: ChatMessage) -> Result<(), MdnsError> {
        if let Some(ref chat_manager) = self.chat_manager {
            chat_manager.send(target, message).await
                .map_err(|e| MdnsError::SwarmBuild(format!("发送消息失败: {}", e)))?;
            Ok(())
        } else {
            Err(MdnsError::SwarmBuild("聊天管理器未初始化".to_string()))
        }
    }

    /// 单次运行迭代
    ///
    /// 执行一次事件循环迭代，返回是否应该继续运行。
    /// - Ok(true): 继续运行
    /// - Ok(false): 应该退出（通道关闭）
    /// - Err: 发生错误
    pub async fn run_once(&mut self) -> Result<bool, MdnsError> {
        tokio::select! {
            // 处理 mDNS 发现事件
            event = self.discovery_rx.recv() => {
                match event {
                    Some(DiscoveryEvent::Discovered { peer_id, addr }) => {
                        self.connect(peer_id, addr).await;
                    }
                    Some(DiscoveryEvent::Expired { peer_id }) => {
                        tracing::debug!("设备 {} mDNS 记录过期", peer_id);
                    }
                    None => {
                        tracing::warn!("发现事件通道已关闭");
                        return Ok(false); // 通道关闭，退出
                    }
                }
            }

            // 处理聊天事件
            Some(event) = async {
                if let Some(ref mut rx) = self.chat_event_rx {
                    rx.recv().await
                } else {
                    std::future::pending().await
                }
            } => {
                match event {
                    super::chat::ChatEvent::MessageReceived { from, message } => {
                        if let super::chat::ChatMessage::Text(text) = message {
                            let from_str = from.to_string();
                            let content_str = text.content.clone();
                            tracing::info!("💬 收到来自 {} 的消息: {}", from, content_str);

                            // 调用全局回调函数（如果已设置）
                            unsafe {
                                if let Some(callback) = CHAT_EVENT_CALLBACK {
                                    callback(from_str, content_str);
                                }
                            }
                        }
                    }
                    super::chat::ChatEvent::PeerTyping { from, is_typing } => {
                        tracing::info!("⌨️ 节点 {} {}", from, if is_typing { "正在输入" } else { "停止输入" });
                    }
                    super::chat::ChatEvent::MessageAcknowledged { from, message_id } => {
                        tracing::debug!("✓ 节点 {} 确认收到消息 {}", from, message_id);
                    }
                    super::chat::ChatEvent::SessionClosed { peer_id } => {
                        tracing::info!("💬 与 {} 的聊天会话已关闭", peer_id);
                    }
                    _ => {
                        // 其他事件类型暂不处理
                        tracing::trace!("收到其他聊天事件: {:?}", event);
                    }
                }
            }

            // 处理 Swarm 事件
            event = self.swarm.select_next_some() => {
                self.handle_swarm_event(event).await?;
            }
        }
        Ok(true)
    }

    /// 运行连接服务
    pub async fn run(&mut self) -> Result<(), MdnsError> {
        loop {
            if !self.run_once().await? {
                break;
            }
        }
        Ok(())
    }

    /// 启动服务（返回任务句柄，消费 self）
    ///
    /// 在后台任务中运行连接服务，类似 MdnsDiscoveryService::spawn()。
    /// 返回 JoinHandle 可用于任务控制（如 abort）。
    pub fn spawn(mut self) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            tracing::info!("🔗 连接服务已启动");
            loop {
                match self.run_once().await {
                    Ok(true) => continue,
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
        })
    }

    /// 处理 Swarm 事件
    async fn handle_swarm_event(
        &mut self,
        event: libp2p::swarm::SwarmEvent<ConnectionBehaviourEvent>,
    ) -> Result<(), MdnsError> {
        match event {
            // 连接建立
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
                }
            }

            // 连接关闭
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
                }
            }

            // 新监听地址
            libp2p::swarm::SwarmEvent::NewListenAddr { address, .. } => {
                tracing::info!("开始监听: {}", address);
            }

            // Identify 事件
            libp2p::swarm::SwarmEvent::Behaviour(ConnectionBehaviourEvent::Identify(event)) => {
                match event {
                    identify::Event::Received { peer_id, info, .. } => {
                        // 验证节点信息
                        match self.node_manager.verify_node_info(
                            &info.protocol_version,
                            &info.agent_version,
                        ) {
                            Ok(()) => {
                                // 跳过自己
                                if peer_id == self.local_peer_id() {
                                    tracing::debug!("跳过自己: {}", peer_id);
                                } else {
                                    tracing::info!("✓ 节点 {} 验证通过", peer_id);

                                    // 添加到节点管理器
                                    let addresses = info.listen_addrs.iter().cloned().collect();
                                    let node = super::VerifiedNode::new(
                                        peer_id,
                                        addresses,
                                        info.protocol_version.clone(),
                                        info.agent_version.clone(),
                                    );

                                    self.node_manager.add_or_update_node(node).await;

                                    // 标记节点为在线
                                    self.node_manager.mark_node_online(&peer_id).await;

                                    // 如果还未收到用户信息，请求用户信息
                                    if !self.peer_user_info.contains_key(&peer_id) {
                                        let _ = self.swarm.behaviour_mut().request_response.send_request(
                                            &peer_id,
                                            user_info::UserInfoRequest,
                                        );
                                    }
                                }
                            }
                            Err(e) => {
                                tracing::warn!("节点 {} 验证失败: {}", peer_id, e);
                            }
                        }
                    }
                    _ => {}
                }
            }

            // Ping 事件
            libp2p::swarm::SwarmEvent::Behaviour(ConnectionBehaviourEvent::Ping(event)) => {
                let ping::Event { peer, result, .. } = event;
                match result {
                    Ok(rtt) => {
                        tracing::debug!("收到 {} 的 pong，RTT: {:?}", peer, rtt);
                    }
                    Err(_e) => {
                        tracing::warn!("❤️ 节点 {} ping 失败", peer);
                    }
                }
            }

            // RequestResponse 事件（用户信息）
            libp2p::swarm::SwarmEvent::Behaviour(ConnectionBehaviourEvent::RequestResponse(event)) => {
                match event {
                    request_response::Event::Message { peer, connection_id: _, message } => {
                        match message {
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
                                tracing::info!("✓ 收到来自 {} 的用户信息: {:?}", peer, response.device_name);
                                // 保存用户信息
                                self.peer_user_info.insert(peer, user_info::UserInfo {
                                    device_name: response.device_name,
                                    nickname: response.nickname,
                                    avatar_url: response.avatar_url,
                                    status: response.status,
                                    custom_data: response.custom_data,
                                });
                            }
                        }
                    }
                    _ => {}
                }
            }

            // Chat 事件（使用 ChatManager 处理）
            libp2p::swarm::SwarmEvent::Behaviour(ConnectionBehaviourEvent::Chat(event)) => {
                match event {
                    request_response::Event::Message { peer, connection_id: _, message } => {
                        match message {
                            request_response::Message::Request {
                                request_id: _,
                                channel,
                                request,
                            } => {
                                tracing::info!("📨 收到来自 {} 的聊天消息: {:?}", peer, request);

                                // 使用 ChatManager 处理收到的消息
                                // ChatRequest 就是 ChatMessage 的类型别名，直接使用
                                if let Some(ref chat_manager) = self.chat_manager {
                                    chat_manager.handle_received_message(peer, request.clone()).await;
                                } else {
                                    // 如果没有 ChatManager，只记录日志
                                    tracing::warn!("聊天管理器未初始化，无法处理消息");
                                }

                                // 发送确认响应
                                let response = crate::chat::ChatResponse::received();
                                let _ = self.swarm.behaviour_mut().chat.send_response(
                                    channel,
                                    response,
                                );
                            }
                            request_response::Message::Response { .. } => {
                                tracing::debug!("收到聊天消息确认");
                            }
                        }
                    }
                    _ => {}
                }
            }

            _ => {}
        }
        Ok(())
    }
}
