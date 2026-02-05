//! 连接管理服务（独立运行）
//!
//! 负责与已发现的节点建立连接、验证身份、维护心跳等功能。

use super::{
    node::NodeManager,
    user_info, MdnsError, events::DiscoveryEvent,
    chat::{ChatManager, ChatMessage, manager::ChatDatabaseConfig},
    chat::database::manager::ChatDatabase,
};
use futures::StreamExt;
use libp2p::{
    identify, ping, request_response, Swarm, SwarmBuilder,
    identity::{Keypair, PeerId},
    Multiaddr, swarm::NetworkBehaviour,
};
use std::sync::Arc;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Instant;
use tokio::sync::mpsc;

/// 全局聊天事件回调（可选）
/// 由 FFI 层设置，用于将聊天事件发送到 Flutter
static mut CHAT_EVENT_CALLBACK: Option<Box<dyn Fn(String, String) + Send + Sync>> = None;
static mut CHAT_MESSAGE_CALLBACK: Option<Box<dyn Fn(String) + Send + Sync>> = None;

/// 设置聊天事件回调（简单版，仅传递文本）
///
/// # Safety
/// 此函数应在初始化时调用一次
pub unsafe fn set_chat_event_callback<F>(callback: F)
where
    F: Fn(String, String) + Send + Sync + 'static,
{
    CHAT_EVENT_CALLBACK = Some(Box::new(callback));
}

/// 设置聊天消息回调（扩展版，传递完整 JSON 消息）
///
/// # Arguments
/// * `callback` - 接收 JSON 字符串格式的完整消息
///
/// # Safety
/// 此函数应在初始化时调用一次
pub unsafe fn set_chat_message_callback<F>(callback: F)
where
    F: Fn(String) + Send + Sync + 'static,
{
    CHAT_MESSAGE_CALLBACK = Some(Box::new(callback));
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

    /// 聊天数据库路径（可选）
    pub chat_db_path: Option<PathBuf>,

    /// 🔥 自动重连配置
    /// 是否启用自动重连
    pub auto_reconnect: bool,
    /// 健康检查间隔
    pub health_check_interval: std::time::Duration,
    /// 重连最大尝试次数（0 = 无限重试）
    pub max_reconnect_attempts: u32,
    /// 重连之间的延迟
    pub reconnect_delay: std::time::Duration,
}

impl Default for ConnectionServiceConfig {
    fn default() -> Self {
        Self {
            listen_addresses: vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()],
            identify_interval: std::time::Duration::from_secs(30),
            idle_connection_timeout: std::time::Duration::from_secs(60),
            chat_db_path: None,
            auto_reconnect: true,
            health_check_interval: std::time::Duration::from_secs(15),
            max_reconnect_attempts: 0, // 无限重试
            reconnect_delay: std::time::Duration::from_secs(5),
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

    /// 发现事件接收器（使用 Option 包装，允许为 None）
    discovery_rx: Option<mpsc::UnboundedReceiver<DiscoveryEvent>>,

    /// 🔥 发现事件发送器（用于通知 P2PManager 节点变化）
    discovery_tx: Option<mpsc::UnboundedSender<DiscoveryEvent>>,

    /// 🔥 mDNS 服务是否仍在运行
    mdns_service_running: bool,

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
    chat_manager: Option<Arc<ChatManager>>,

    /// 聊天事件接收器
    chat_event_rx: Option<mpsc::UnboundedReceiver<super::chat::ChatEvent>>,

    /// 本地 Peer ID
    local_peer_id: PeerId,

    /// 🔥 健康检查和重连配置
    config: ConnectionServiceConfig,

    /// 🔥 上次健康检查时间
    last_health_check: Instant,

    /// 🔥 跟踪每个节点的重连尝试次数
    reconnect_attempts: HashMap<PeerId, u32>,

    /// 🔥 跟踪待处理的 dial 尝试 (addr_string -> peer_id)
    /// 用于处理 OutgoingConnectionError 中 peer_id = None 的情况
    pending_dials: HashMap<String, PeerId>,
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
        discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,
        config: ConnectionServiceConfig,
    ) -> Result<Self, MdnsError> {
        tracing::info!("正在初始化连接服务...");
        crate::send_log("INFO", "connection_service", "🔗 正在初始化连接服务...".to_string());

        let local_peer_id = identity.public().to_peer_id();
        let protocol_version = node_manager.config().expected_protocol_version.clone();
        let agent_version = node_manager.config().build_agent_version();

        // 创建数据库配置
        let db_config = if let Some(ref db_path) = config.chat_db_path {
            ChatDatabaseConfig {
                db_path: db_path.clone(),
                enabled: true,
            }
        } else {
            ChatDatabaseConfig::default()
        };

        // 创建聊天管理器（使用共享的 NodeManager 和数据库配置）
        crate::send_log("INFO", "connection_service", "🗄️ 正在创建聊天管理器...".to_string());
        crate::send_log("INFO", "connection_service", format!("🗄️ 数据库配置: enabled={}, db_path={:?}", db_config.enabled, db_config.db_path));
        let (chat_manager, chat_event_rx) = ChatManager::with_db_config(
            node_manager.clone(),
            local_peer_id,
            db_config,
        );
        crate::send_log("INFO", "connection_service", "✅ 聊天管理器已创建".to_string());

        // 初始化聊天数据库
        crate::send_log("INFO", "connection_service", "🗄️ 正在初始化聊天数据库...".to_string());
        if let Err(e) = chat_manager.initialize_database().await {
            crate::send_log("WARN", "connection_service", format!("⚠️ 聊天数据库初始化失败: {}", e));
        } else {
            crate::send_log("INFO", "connection_service", "✅ 聊天数据库初始化完成".to_string());
        }

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
        for addr in &config.listen_addresses {
            swarm.listen_on(addr.clone())
                .map_err(|e| MdnsError::SwarmBuild(e.to_string()))?;
        }

        tracing::info!("✓ 连接服务初始化成功，Peer ID: {}", local_peer_id);
        crate::send_log("INFO", "connection_service", format!("✅ 连接服务初始化成功，Peer ID: {}", local_peer_id));

        Ok(Self {
            swarm,
            node_manager,
            discovery_rx: Some(discovery_rx),  // 🔥 包装在 Option 中
            discovery_tx: Some(discovery_tx),  // 🔥 发送器用于通知 P2PManager
            mdns_service_running: true,  // 🔥 初始状态：mDNS 服务运行中
            local_user_info,
            protocol_version,
            agent_version,
            active_connections: HashMap::new(),
            peer_user_info: HashMap::new(),
            chat_manager: Some(Arc::new(chat_manager)),
            chat_event_rx: Some(chat_event_rx),
            local_peer_id,
            config,
            last_health_check: Instant::now(),
            reconnect_attempts: HashMap::new(),
            pending_dials: HashMap::new(),
        })
    }

    /// 连接到指定的节点（带重试机制）
    ///
    /// ⭐ 方案3: 添加重试机制，解决设备同时启动时的竞态条件
    ///
    /// 🔥 修复：跟踪 dial 尝试，以便在 OutgoingConnectionError 中恢复 peer_id
    pub async fn connect(&mut self, peer_id: PeerId, addr: Multiaddr) {
        const MAX_RETRIES: u32 = 3;
        let mut last_error = None;

        for attempt in 1..=MAX_RETRIES {
            tracing::info!("🔌 [尝试 {}/{}] 连接到 {} at {}", attempt, MAX_RETRIES, peer_id, addr);

            if attempt > 1 {
                crate::send_log("INFO", "connection_service", format!("🔄 重试连接 [{}/{}]: {} at {}", attempt, MAX_RETRIES, peer_id, addr));
            } else {
                crate::send_log("INFO", "connection_service", format!("🔌 正在连接到 {} at {}", peer_id, addr));
            }

            // 🔥 关键修复：在 dial 前记录地址到 peer_id 的映射
            // 这样即使 OutgoingConnectionError 中 peer_id = None，我们也能知道是哪个 peer
            let addr_str = addr.to_string();
            self.pending_dials.insert(addr_str.clone(), peer_id);

            match self.swarm.dial(addr.clone()) {
                Ok(_) => {
                    tracing::info!("✅ 已发送连接请求到 {}", peer_id);
                    crate::send_log("INFO", "connection_service", format!("✅ 已发送连接请求到 {}", peer_id));
                    return;
                }
                Err(e) => {
                    tracing::warn!("⚠️  连接失败 [尝试 {}/{}]: {} - {}", attempt, MAX_RETRIES, peer_id, e);
                    // 连接立即失败，清理 pending_dials
                    self.pending_dials.remove(&addr_str);
                    last_error = Some(e);

                    // 如果不是最后一次尝试，等待一段时间后重试
                    if attempt < MAX_RETRIES {
                        let delay_ms = 500 * attempt as u64; // 指数退避：500ms, 1000ms, 1500ms
                        tracing::debug!("⏱️  等待 {}ms 后重试...", delay_ms);
                        tokio::time::sleep(tokio::time::Duration::from_millis(delay_ms)).await;
                    }
                }
            }
        }

        // 所有重试都失败了
        let error = last_error.expect("last_error should be Some after all retries failed");
        tracing::error!("❌ 无法连接到 {} at {}: {} (已重试 {} 次)", peer_id, addr, error, MAX_RETRIES);
        crate::send_log("ERROR", "connection_service", format!("❌ 无法连接到 {} at {}: {} (已重试 {} 次)", peer_id, addr, error, MAX_RETRIES));
    }

    /// 获取节点管理器
    pub fn node_manager(&self) -> Arc<NodeManager> {
        self.node_manager.clone()
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> PeerId {
        self.local_peer_id
    }

    /// 获取当前监听的地址列表
    pub fn listeners(&self) -> Vec<Multiaddr> {
        self.swarm.listeners().cloned().collect()
    }

    /// 获取聊天管理器（用于发送消息）
    pub fn chat_manager(&self) -> Option<&ChatManager> {
        self.chat_manager.as_ref().map(|v| &**v)
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

    /// 🔥 执行健康检查和自动重连
    ///
    /// 定期检查所有已知的离线节点，尝试重新连接
    fn check_and_reconnect(&mut self) {
        // 如果未启用自动重连，跳过
        if !self.config.auto_reconnect {
            return;
        }

        let now = Instant::now();
        let should_check = now.duration_since(self.last_health_check) >= self.config.health_check_interval;

        if !should_check {
            return;
        }

        self.last_health_check = now;
        tracing::debug!("🔍 开始健康检查...");

        // 获取所有已知节点
        let known_nodes = match self.node_manager.try_get_all_nodes() {
            Some(nodes) => nodes,
            None => {
                tracing::warn!("无法获取节点列表（需要异步上下文）");
                return;
            }
        };

        let mut reconnect_count = 0;

        for node in known_nodes {
            let peer_id = node.peer_id;

            // 跳过自己
            if peer_id == self.local_peer_id {
                continue;
            }

            // 检查是否已连接
            let is_connected = self.swarm.is_connected(&peer_id);

            if is_connected {
                // 已连接，重置重连计数
                self.reconnect_attempts.remove(&peer_id);
                continue;
            }

            // 未连接，检查是否需要重连
            let attempts = self.reconnect_attempts.entry(peer_id).or_insert(0);

            // 检查是否超过最大重试次数
            if self.config.max_reconnect_attempts > 0 && *attempts >= self.config.max_reconnect_attempts {
                tracing::debug!("节点 {} 已达到最大重试次数 ({}), 跳过重连", peer_id, self.config.max_reconnect_attempts);
                continue;
            }

            // 尝试重连
            // 🔥 修复：跟踪 pending dial
            for addr in &node.addresses {
                let attempt_num = *attempts + 1;
                tracing::info!("🔄 自动重连到 {} at {} (尝试 {})", peer_id, addr, attempt_num);

                // 🔥 跟踪 pending dial
                let addr_str = addr.to_string();
                self.pending_dials.insert(addr_str.clone(), peer_id);

                match self.swarm.dial(addr.clone()) {
                    Ok(_) => {
                        tracing::info!("✅ 已发送重连请求到 {}", peer_id);
                        reconnect_count += 1;
                        crate::send_log("INFO", "connection_service",
                            format!("🔄 自动重连: {} (尝试 {})", peer_id, attempt_num));
                        break; // 成功发送一次即可，不需要尝试多个地址
                    }
                    Err(e) => {
                        tracing::warn!("重连失败 {}: {:?}", peer_id, e);
                        // 立即失败，清理 pending dial
                        self.pending_dials.remove(&addr_str);
                    }
                }
            }

            *attempts += 1;
        }

        if reconnect_count > 0 {
            tracing::info!("🔍 健康检查完成，触发 {} 次重连", reconnect_count);
        }
    }

    /// 单次运行迭代
    ///
    /// 执行一次事件循环迭代，返回是否应该继续运行。
    /// - Ok(true): 继续运行
    /// - Ok(false): 应该退出（通道关闭）
    /// - Err: 发生错误
    pub async fn run_once(&mut self) -> Result<bool, MdnsError> {
        // 先检查聊天事件（非阻塞）
        if let Some(ref mut rx) = self.chat_event_rx {
            if let Ok(event) = rx.try_recv() {
                match event {
                    super::chat::ChatEvent::MessageReceived { from, message } => {
                        let from_str = from.to_string();
                        let content_str = match &message {
                            super::chat::ChatMessage::Text(text) => {
                                text.content.clone()
                            }
                            super::chat::ChatMessage::Message(msg) => {
                                // 从 MessageContent 中提取文本内容
                                msg.content.text.clone().unwrap_or_else(|| {
                                    // 如果没有文本，根据类型生成描述
                                    match msg.content.msg_type {
                                        super::chat::MessageType::Image => "[图片]".to_string(),
                                        super::chat::MessageType::Video => "[视频]".to_string(),
                                        super::chat::MessageType::File => "[文件]".to_string(),
                                        super::chat::MessageType::Audio => "[音频]".to_string(),
                                        super::chat::MessageType::RedPacket => "[红包]".to_string(),
                                        super::chat::MessageType::System => "[系统消息]".to_string(),
                                        _ => "[未知消息]".to_string(),
                                    }
                                })
                            }
                            _ => "[未知消息类型]".to_string(),
                        };

                        tracing::info!("💬 收到来自 {} 的消息: {}", from, content_str);

                        // 调用全局回调函数（如果已设置）
                        unsafe {
                            if let Some(callback) = CHAT_EVENT_CALLBACK.as_ref() {
                                callback(from_str.clone(), content_str);
                            }

                            // 🔥 调用扩展消息回调，传递完整 JSON 消息
                            if let Some(msg_callback) = CHAT_MESSAGE_CALLBACK.as_ref() {
                                if let super::chat::ChatMessage::Message(ref msg) = message {
                                    // 直接构造 JSON 字符串（与 FFI 层的 MessageJson 格式一致）
                                    use serde_json::json;
                                    let extra_json = if msg.content.extra.is_empty() {
                                        serde_json::Value::Null
                                    } else {
                                        serde_json::Value::String(serde_json::to_string(&msg.content.extra).unwrap_or_default())
                                    };
                                    let id_str = msg.id.clone();
                                    let text_str = msg.content.text.clone().unwrap_or_default();
                                    let msg_json = json!({
                                        "id": id_str,
                                        "conversationId": "",
                                        "senderPeerId": from_str,
                                        "messageType": msg.content.msg_type as i32,
                                        "content": text_str,
                                        "timestamp": msg.timestamp,
                                        "replyToId": serde_json::Value::Null,
                                        "status": 0,
                                        "isDeleted": false,
                                        "isRevoked": false,
                                        "extra": extra_json,
                                    }).to_string();
                                    msg_callback(msg_json);
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
        }

        tokio::select! {
            // 🔥 处理 mDNS 发现事件（仅在 discovery_rx 存在时）
            event = async {
                if let Some(ref mut rx) = &mut self.discovery_rx {
                    rx.recv().await
                } else {
                    std::future::pending().await
                }
            } => {
                if let Some(event) = event {
                    match event {
                        DiscoveryEvent::Discovered { peer_id, addr } => {
                            crate::send_log("INFO", "connection_service", format!("📨 收到发现事件: {} at {}", peer_id, addr));
                            self.connect(peer_id, addr).await;
                        }
                        DiscoveryEvent::Expired { peer_id } => {
                            tracing::debug!("设备 {} mDNS 记录过期", peer_id);
                        }
                        DiscoveryEvent::Refresh => {
                            tracing::info!("🔄 [连接服务] 收到刷新事件");
                            crate::send_log("INFO", "connection_service", "🔄 收到刷新请求".to_string());

                            // 触发重新连接到所有已知节点
                            let known_nodes = self.node_manager.list_all_nodes().await;
                            tracing::info!("🔄 [连接服务] 尝试重新连接到 {} 个已知节点", known_nodes.len());

                            for node in known_nodes {
                                for addr in &node.addresses {
                                    tracing::debug!("🔄 [连接服务] 尝试重新连接到 {} at {}", node.peer_id, addr);
                                    self.connect(node.peer_id, addr.clone()).await;
                                }
                            }

                            tracing::info!("✓ [连接服务] 刷新完成");
                            crate::send_log("INFO", "connection_service", "✅ 刷新完成".to_string());
                        }
                        DiscoveryEvent::MdnsStarted { local_peer_id, port, service_type } => {
                            tracing::info!("🧪 [连接服务] mDNS 已启动: {}@{}", local_peer_id, port);
                            crate::send_log("INFO", "connection_service",
                                format!("🧪 mDNS 已启动\n📋 Peer ID: {}\n📋 端口: {}\n📋 服务类型: {}",
                                    local_peer_id, port, service_type));

                            // 标记 mDNS 服务正在运行
                            self.mdns_service_running = true;

                            // ⭐ 将 mDNS 启动事件转发到 Flutter（通过 FFI）
                            // Flutter 端会收到这个事件，然后启动自己的 mDNS 广播（测试）
                            if let Err(e) = crate::p2p_manager::send_mdns_started_event_to_flutter(
                                local_peer_id,
                                port,
                                service_type,
                            ) {
                                tracing::error!("发送 mDNS 启动事件到 Flutter 失败: {}", e);
                            }
                        }
                        DiscoveryEvent::ServiceStateChanged { service, status } => {
                            tracing::info!("🔔 [连接服务] 服务状态变化: {} - {:?}", service, status);
                            crate::send_log("INFO", "connection_service",
                                format!("🔔 服务状态: {} - 运行={} 健康={:?}",
                                    service, status.is_running, status.health));

                            // 更新 mDNS 服务运行状态
                            if service == "mDNS" {
                                self.mdns_service_running = status.is_running;
                            }

                            // 🔥 发送服务状态变化事件到 Flutter
                            let status_json = serde_json::json!({
                                "service": service,
                                "name": status.name,
                                "health": match status.health {
                                    crate::events::ServiceHealth::Healthy => "healthy",
                                    crate::events::ServiceHealth::Degraded => "degraded",
                                    crate::events::ServiceHealth::Unhealthy => "unhealthy",
                                },
                                "is_running": status.is_running,
                                "message": status.message,
                            });

                            // 通过 send_log 发送服务状态事件（使用特殊前缀）
                            crate::send_log("SERVICE_STATUS", "connection_service", status_json.to_string());
                        }
                        DiscoveryEvent::NodesUpdated => {
                            // 🔥 节点列表已更新，发送连接状态到 Flutter
                            self.send_connection_status_to_flutter();
                        }
                    }
                }
            }

            // 定时检查并发送待发送的聊天消息 + 健康检查和自动重连
            _ = tokio::time::sleep(tokio::time::Duration::from_millis(100)) => {
                self.process_pending_chat_messages().await?;
                // 🔥 执行健康检查和自动重连（内部会判断是否到了检查时间）
                self.check_and_reconnect();
            }

            // 处理 Swarm 事件
            event = self.swarm.select_next_some() => {
                self.handle_swarm_event(event).await?;
            }
        }
        Ok(true)
    }

    /// 处理待发送的聊天消息
    async fn process_pending_chat_messages(&mut self) -> Result<(), MdnsError> {
        if let Some(ref chat_manager) = self.chat_manager {
            // 获取所有有活跃连接的节点
            let connected_peers: Vec<_> = self.active_connections
                .keys()
                .cloned()
                .collect();

            for peer_id in connected_peers {
                // 检查是否有待发送的消息
                if let Some(chat_message) = chat_manager.get_pending_chat_message(&peer_id).await {
                    tracing::debug!("发送待发送消息给 {}", peer_id);

                    // 通过 Swarm 发送消息（ChatRequest 就是 ChatMessage）
                    let _ = self.swarm.behaviour_mut().chat.send_request(
                        &peer_id,
                        chat_message,
                    );
                }
            }
        }
        Ok(())
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
            libp2p::swarm::SwarmEvent::ConnectionEstablished { peer_id, endpoint, .. } => {
                tracing::info!("✓ 与 {} 建立新连接", peer_id);
                crate::send_log("INFO", "connection_service", format!("✓ 与 {} 建立新连接", peer_id));
                let conn_count = self.active_connections.entry(peer_id).or_insert(0);
                let is_first_connection = *conn_count == 0;
                *conn_count += 1;

                // 🔥 连接成功后，重置重连计数
                self.reconnect_attempts.remove(&peer_id);

                // 🔥 清理 pending_dials 中与该 peer 相关的条目
                // 通过 endpoint 获取地址，从 pending_dials 中移除
                let endpoint_addr = endpoint.get_remote_address();
                self.pending_dials.remove(&endpoint_addr.to_string());

                if is_first_connection {
                    // ⚠️ 关键修复：在连接建立时立即添加节点到 NodeManager
                    // 因为对方可能没有 Identify behaviour（如 MdnsDiscoveryService）
                    tracing::info!("与 {} 建立首个连接，立即添加节点", peer_id);
                    crate::send_log("INFO", "connection_service", format!("🆔 与 {} 建立首个连接，立即添加节点", peer_id));

                    // 从 Swarm 获取当前监听的地址列表
                    let addresses: Vec<Multiaddr> = self.swarm.listeners().cloned().collect();

                    // 创建节点（使用默认协议版本，因为还没有 Identify 信息）
                    let node = super::VerifiedNode::new(
                        peer_id,
                        addresses.clone(),
                        self.node_manager.config().expected_protocol_version.clone(),
                        "localp2p-unknown".to_string(),  // 未知 agent 版本
                    );

                    // 🔥 保存设备信息到数据库（异步，不阻塞当前流程）
                    // 首次连接时使用 peer_id 作为显示名称，稍后收到 Identify 信息时会更新
                    if let Some(chat_manager) = self.chat_manager.clone() {
                        let peer_id_save = peer_id;
                        let addresses_save = addresses.clone();
                        let protocol_version = self.node_manager.config().expected_protocol_version.clone();
                        tokio::spawn(async move {
                            // 将 Multiaddr 转换为字符串列表
                            let addr_strings: Vec<String> = addresses_save.iter()
                                .map(|addr| addr.to_string())
                                .collect();

                            // 创建 DbDevice 记录
                            let device = crate::chat::database::DbDevice::new(
                                peer_id_save.to_string(),
                                peer_id_save.to_string(),
                                peer_id_save.to_string(),
                                protocol_version,
                                Some(addr_strings),
                            );

                            // 保存到数据库
                            if let Some(db) = chat_manager.get_database().await {
                                if let Err(e) = db.upsert_device(device).await {
                                    tracing::error!("❌ 保存设备 {} 到数据库失败: {}", peer_id_save, e);
                                    crate::send_log("ERROR", "connection_service",
                                        format!("❌ 保存设备到数据库失败: {} - {}", peer_id_save, e));
                                } else {
                                    tracing::info!("✅ 设备 {} 已保存到数据库", peer_id_save);
                                    crate::send_log("INFO", "connection_service",
                                        format!("💾 设备 {} 已保存到数据库", peer_id_save));
                                }
                            }
                        });
                    }

                    self.node_manager.add_or_update_node(node).await;
                    crate::send_log("INFO", "connection_service", format!("✅ 节点 {} 已添加到 NodeManager", peer_id));

                    // 标记节点为在线
                    self.node_manager.mark_node_online(&peer_id).await;
                    crate::send_log("INFO", "connection_service", format!("✅ 节点 {} 已标记为在线", peer_id));

                    // 🔥 发送连接状态更新到 Flutter
                    self.send_connection_status_to_flutter();

                    // 请求用户信息（获取设备名称等）
                    crate::send_log("INFO", "connection_service", format!("📋 向 {} 请求用户信息", peer_id));
                    let _ = self.swarm.behaviour_mut().request_response.send_request(
                        &peer_id,
                        user_info::UserInfoRequest,
                    );
                } else {
                    // 🔥 非首次连接，也更新数据库中的地址信息（异步）
                    let addresses: Vec<Multiaddr> = self.swarm.listeners().cloned().collect();
                    if let Some(chat_manager) = self.chat_manager.clone() {
                        let peer_id_update = peer_id;
                        tokio::spawn(async move {
                            // 将 Multiaddr 转换为字符串列表
                            let addr_strings: Vec<String> = addresses.iter()
                                .map(|addr| addr.to_string())
                                .collect();

                            if let Some(db) = chat_manager.get_database().await {
                                // 尝试获取现有设备
                                match db.get_device(&peer_id_update.to_string()).await {
                                    Ok(Some(existing_device)) => {
                                        // 设备已存在，创建 DbDevice 更新在线状态
                                        let mut db_device = crate::chat::database::DbDevice::new(
                                            existing_device.peer_id.clone(),
                                            existing_device.display_name.clone(),
                                            existing_device.device_name.clone(),
                                            existing_device.protocol_version.clone(),
                                            Some(addr_strings.clone()),
                                        );
                                        // 保留原有的 first_seen、nickname、avatar_url 等信息
                                        db_device.first_seen = existing_device.first_seen;
                                        db_device.nickname = existing_device.nickname.clone();
                                        db_device.avatar_url = existing_device.avatar_url.clone();
                                        // 标记为上线
                                        db_device.mark_online(addr_strings);

                                        if let Err(e) = db.upsert_device(db_device).await {
                                            tracing::error!("❌ 更新设备 {} 在线状态失败: {}", peer_id_update, e);
                                        } else {
                                            tracing::info!("✅ 设备 {} 在线状态已更新到数据库", peer_id_update);
                                            crate::send_log("INFO", "connection_service",
                                                format!("🔄 设备 {} 在线状态已更新", peer_id_update));
                                        }
                                    }
                                    Ok(None) => {
                                        // 设备不存在，记录警告
                                        tracing::warn!("⚠️ 设备 {} 不存在于数据库中，无法更新在线状态", peer_id_update);
                                    }
                                    Err(e) => {
                                        tracing::error!("❌ 获取设备 {} 失败: {}", peer_id_update, e);
                                    }
                                }
                            }
                        });
                    }
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

                    // 🔥 发送连接状态更新到 Flutter（设备离线）
                    self.send_connection_status_to_flutter();
                }
            }

            // 🔥 出站连接错误 - 连接尝试失败
            libp2p::swarm::SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
                if let Some(pid) = peer_id {
                    tracing::warn!("❌ 连接到 {} 失败: {:?}", pid, error);
                    crate::send_log("WARN", "connection_service", format!("❌ 连接失败: {} - {}", pid, error));

                    // 增加重连计数
                    let attempts = self.reconnect_attempts.entry(pid).or_insert(0);
                    *attempts += 1;

                    // 如果重连次数过多，标记为离线
                    if *attempts >= 3 {
                        tracing::warn!("⚠️ 节点 {} 连接失败次数过多 ({}), 标记为离线", pid, attempts);
                        if self.node_manager.mark_node_offline(&pid, "连接失败").await {
                            tracing::info!("已标记节点为离线: {}", pid);
                        }
                        self.send_connection_status_to_flutter();
                    }
                } else {
                    // 🔥 peer_id = None 表示连接在握手前就失败了
                    // 无法确定具体是哪个 peer，清理所有 pending dials 作为安全措施
                    tracing::warn!("❌ 连接失败（无 peer_id）: {:?}，清理 {} 个待处理 dial", error, self.pending_dials.len());
                    crate::send_log("WARN", "connection_service", format!("❌ 连接失败（握手前）: {} | 清理 {} 个待处理 dial",
                        error, self.pending_dials.len()));

                    // 清理所有 pending dials（它们可能都失败了）
                    for (addr, pid) in &self.pending_dials {
                        tracing::debug!("清理待处理 dial: {} -> {}", addr, pid);

                        // 增加重连计数（因为 dial 失败了）
                        let attempts = self.reconnect_attempts.entry(*pid).or_insert(0);
                        *attempts += 1;
                    }

                    // 清空 pending dials
                    self.pending_dials.clear();
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
                        crate::send_log("INFO", "connection_service", format!("🔍 收到来自 {} 的 Identify 信息", peer_id));
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
                                    crate::send_log("INFO", "connection_service", format!("✓ 节点 {} 验证通过，添加到管理器", peer_id));

                                    // 添加到节点管理器
                                    let addresses = info.listen_addrs.iter().cloned().collect();
                                    let node = super::VerifiedNode::new(
                                        peer_id,
                                        addresses,
                                        info.protocol_version.clone(),
                                        info.agent_version.clone(),
                                    );

                                    self.node_manager.add_or_update_node(node).await;
                                    crate::send_log("INFO", "connection_service", format!("✅ 节点 {} 已添加到 NodeManager", peer_id));

                                    // 标记节点为在线
                                    self.node_manager.mark_node_online(&peer_id).await;
                                    crate::send_log("INFO", "connection_service", format!("✅ 节点 {} 已标记为在线", peer_id));

                                    // 🔥 发送连接状态更新到 Flutter
                                    self.send_connection_status_to_flutter();

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
                                crate::send_log("WARN", "connection_service", format!("⚠️ 节点 {} 验证失败: {}", peer_id, e));
                            }
                        }
                    }
                    identify::Event::Sent { .. } => {
                        crate::send_log("DEBUG", "connection_service", "📤 Identify 信息已发送".to_string());
                    }
                    identify::Event::Error { peer_id, error, .. } => {
                        // 添加详细的错误信息
                        let error_detail = format!("协议协商失败 - 原因：{}", error);
                        crate::send_log("ERROR", "connection_service", format!("❌ Identify 错误: peer={}, error={}", peer_id, error_detail));
                        tracing::error!("❌ Identify 错误: peer={}, error={:?}", peer_id, error);
                    }
                    _ => {
                        crate::send_log("TRACE", "connection_service", format!("🔄 其他 Identify 事件: {:?}", event));
                    }
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
                                crate::send_log("INFO", "connection_service", format!("📥 收到来自 {} 的用户信息请求", peer));

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
                                crate::send_log("INFO", "connection_service", format!("📤 已向 {} 发送用户信息响应", peer));
                            }
                            request_response::Message::Response {
                                request_id: _,
                                response,
                            } => {
                                tracing::info!("✓ 收到来自 {} 的用户信息: {:?}", peer, response.device_name);
                                crate::send_log("INFO", "connection_service", format!("✅ 收到来自 {} 的用户信息: {}", peer, response.device_name));
                                // 保存用户信息到本地 HashMap
                                let user_info = user_info::UserInfo {
                                    device_name: response.device_name.clone(),
                                    nickname: response.nickname.clone(),
                                    avatar_url: response.avatar_url.clone(),
                                    status: response.status.clone(),
                                    custom_data: response.custom_data.clone(),
                                };
                                self.peer_user_info.insert(peer, user_info.clone());

                                // ⭐ 同时保存到 NodeManager 的 attributes 中（供 FFI 层读取）
                                self.node_manager.update_node_user_info(&peer, &user_info).await;

                                // 🔥 更新数据库中的设备信息（异步）
                                if let Some(chat_manager) = self.chat_manager.clone() {
                                    let peer_id_update = peer;
                                    let device_name_clone = response.device_name.clone();
                                    let nickname_clone = response.nickname.clone();
                                    let avatar_url_clone = response.avatar_url.clone();
                                    tokio::spawn(async move {
                                        if let Some(db) = chat_manager.get_database().await {
                                            // 尝试获取现有设备
                                            match db.get_device(&peer_id_update.to_string()).await {
                                                Ok(Some(existing_device)) => {
                                                    // existing_device.addresses 已经是 Option<Vec<String>> 类型
                                                    let existing_addresses = existing_device.addresses.unwrap_or_default();

                                                    // 创建更新的设备记录，保留原有的 first_seen 等信息
                                                    let mut db_device = crate::chat::database::DbDevice::new(
                                                        existing_device.peer_id.clone(),
                                                        device_name_clone.clone(),
                                                        device_name_clone.clone(),
                                                        existing_device.protocol_version.clone(),
                                                        Some(existing_addresses.clone()),
                                                    );
                                                    // 保留原有的首次发现时间和其他信息
                                                    db_device.first_seen = existing_device.first_seen;
                                                    db_device.nickname = nickname_clone;
                                                    db_device.avatar_url = avatar_url_clone;
                                                    db_device.status = Some("online".to_string());
                                                    // 更新最后上线时间
                                                    db_device.mark_online(existing_addresses);

                                                    if let Err(e) = db.upsert_device(db_device).await {
                                                        tracing::error!("❌ 更新设备 {} 信息失败: {}", peer_id_update, e);
                                                    } else {
                                                        tracing::info!("✅ 设备 {} 信息已更新到数据库: {}", peer_id_update, device_name_clone);
                                                        crate::send_log("INFO", "connection_service",
                                                            format!("💾 设备 {} 信息已更新: {}", peer_id_update, device_name_clone));
                                                    }
                                                }
                                                Ok(None) => {
                                                    tracing::warn!("⚠️ 设备 {} 不存在于数据库中，等待下次连接时创建", peer_id_update);
                                                }
                                                Err(e) => {
                                                    tracing::error!("❌ 获取设备 {} 失败: {}", peer_id_update, e);
                                                }
                                            }
                                        }
                                    });
                                }
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

            _ => {
                // 记录未被处理的事件（帮助调试）
                if !matches!(event,
                    libp2p::swarm::SwarmEvent::NewListenAddr { .. }
                    | libp2p::swarm::SwarmEvent::ExpiredListenAddr { .. }
                ) {
                    crate::send_log("TRACE", "connection_service", "🔄 其他 Swarm 事件（已忽略）".to_string());
                }
            }
        }
        Ok(())
    }

    /// 🔥 发送连接服务状态到 Flutter
    ///
    /// 当节点列表变化时调用此方法，通知 Flutter 更新 UI
    pub fn send_connection_status_to_flutter(&self) {
        // 🔥 克隆 NodeManager 引用，在独立任务中发送状态
        let node_manager = self.node_manager.clone();

        // 在新任务中执行异步操作，避免在当前上下文中持有 &self
        tokio::spawn(async move {
            let online_nodes = node_manager.list_online_nodes().await;
            let all_nodes = node_manager.list_all_nodes().await;

            let (health, message) = if !online_nodes.is_empty() {
                (
                    "healthy",
                    format!("服务运行中 | 已连接 {} 个设备", online_nodes.len())
                )
            } else {
                (
                    "degraded",
                    "服务运行中 | 等待连接设备".to_string()
                )
            };

            let status_json = serde_json::json!({
                "service": "Connection",
                "name": "Connection Service",
                "health": health,
                "is_running": true,
                "message": message,
                "connected_peers": online_nodes.len(),
                "discovered_peers": all_nodes.len(),
            });

            crate::send_log("SERVICE_STATUS", "connection_service", status_json.to_string());
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_service_config_default() {
        let config = ConnectionServiceConfig::default();
        assert!(!config.listen_addresses.is_empty());
        assert_eq!(config.identify_interval, std::time::Duration::from_secs(30));
        assert_eq!(config.idle_connection_timeout, std::time::Duration::from_secs(60));
    }

    #[test]
    fn test_connection_service_config_clone() {
        let config = ConnectionServiceConfig::default();
        let config2 = config.clone();
        assert_eq!(config.listen_addresses.len(), config2.listen_addresses.len());
    }
}
