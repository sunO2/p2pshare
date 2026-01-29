//! Local P2P FFI 层
//!
//! 提供 C ABI 兼容的接口，供 Flutter/Dart 调用
//!
//! 使用事件队列模式：Rust 将事件放入队列，Dart 通过轮询获取事件
//! 这样避免了从 Rust 后台线程直接调用 Dart 回调的问题

#![allow(clippy::missing_safety_doc)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, RwLock};
use std::thread;

use once_cell::sync::Lazy;
use tokio::runtime::Runtime;
use mdns::{
    ManagedDiscovery, NodeManager, NodeManagerConfig,
    HealthCheckConfig, UserInfo, ChatExtension, ChatMessage,
    IdentityManager,
};

mod types;
mod error;
pub mod bridge;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

use types::*;

// ============================================================================
// 全局运行时和状态管理
// ============================================================================

/// 全局 Tokio 运行时
static mut RUNTIME: Option<Runtime> = None;

/// 获取 Tokio 运行时的引用（供 bridge 模块使用）
pub fn get_runtime() -> Option<&'static Runtime> {
    unsafe { RUNTIME.as_ref() }
}

/// 全局 P2P 实例
static mut P2P_INSTANCE: Option<Arc<Mutex<P2PInstance>>> = None;

/// 全局用户信息缓存（用于查询用户信息）
/// 使用 RwLock 允许多读单写
static GLOBAL_USER_INFO: Lazy<Mutex<RwLock<HashMap<String, mdns::UserInfo>>>> = Lazy::new(|| {
    Mutex::new(RwLock::new(HashMap::new()))
});

/// 全局 Discovery 资源存储（在 init 和 start 之间传递）
struct GlobalDiscoveryResources {
    discovery: Option<ManagedDiscovery>,
    chat_event_rx: Option<tokio::sync::mpsc::UnboundedReceiver<mdns::chat::ChatEvent>>,
    command_rx: Option<tokio::sync::mpsc::UnboundedReceiver<P2PCommand>>,
    event_tx: Option<tokio::sync::mpsc::UnboundedSender<P2PEvent>>,
}

static mut DISCOVERY_RESOURCES: Option<GlobalDiscoveryResources> = None;

/// P2P 服务运行标志（用于 internal_is_running 检查）
static mut P2P_IS_RUNNING: bool = false;

/// 最后一次收到 discovery 事件的时间
static LAST_EVENT_TIME: Mutex<Option<std::time::Instant>> = Mutex::new(None);

/// 更新最后事件时间
fn update_last_event_time() {
    if let Ok(mut time) = LAST_EVENT_TIME.lock() {
        *time = Some(std::time::Instant::now());
    }
}

/// 获取距离上次事件的时间
fn time_since_last_event() -> Option<std::time::Duration> {
    LAST_EVENT_TIME.lock().ok().and_then(|time| {
        time.map(|instant| instant.elapsed())
    })
}

/// P2P 实例（包含所有核心组件）
struct P2PInstance {
    node_manager: Arc<NodeManager>,
    local_peer_id: String,
    device_name: String,
    /// 身份密钥对（用于保持 Peer ID 稳定）
    identity: Option<libp2p::identity::Keypair>,
    /// 命令通道，用于向 discovery 线程发送命令
    command_tx: tokio::sync::mpsc::UnboundedSender<P2PCommand>,
    /// Discovery 线程句柄
    discovery_thread: Option<thread::JoinHandle<()>>,
}

/// P2P 内部事件
#[derive(Debug)]
enum P2PEvent {
    NodeDiscovered { peer_id: String, addr: String },
    NodeExpired { peer_id: String },
    NodeVerified { peer_id: String, display_name: String },
    NodeOffline { peer_id: String },
    UserInfoReceived { peer_id: String, user_info: UserInfoJson },
    MessageReceived { from: String, message: ChatMessageJson },
    MessageSent { to: String, message_id: String },
    PeerTyping { from: String, is_typing: bool },
}

/// P2P 命令（用于与 discovery 线程通信）
#[derive(Debug)]
enum P2PCommand {
    SendMessage {
        target_peer_id: String,
        message: String,
        response_tx: tokio::sync::oneshot::Sender<Result<String, String>>,
    },
    BroadcastMessage {
        target_peer_ids: Vec<String>,
        message: String,
        response_tx: tokio::sync::oneshot::Sender<Result<String, String>>,
    },
    Ping {
        response_tx: tokio::sync::oneshot::Sender<Result<(), String>>,
    },
    Stop,
}

// ============================================================================
// Flutter Rust Bridge 内部 API
// ============================================================================

/// 全局事件通道（用于 FRB stream）
static GLOBAL_EVENT_TX: Mutex<Option<tokio::sync::mpsc::UnboundedSender<bridge::P2PEvent>>> = Mutex::new(None);

// 使用 bridge 模块中的类型别名
use bridge::InternalNodeInfo;

// ============================================================================
// 内部初始化和生命周期函数
// ============================================================================

/// 内部初始化函数（供 FRB 调用）
pub fn internal_init(device_name: String, identity_path: String) -> Result<(), String> {
    // 初始化日志
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init()
        .ok();

    // 创建 Tokio 运行时
    unsafe {
        if RUNTIME.is_some() {
            return Err("Already initialized".to_string());
        }

        RUNTIME = Some(
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("Failed to create runtime")
        );
    }

    let runtime = unsafe { RUNTIME.as_ref().unwrap() };

    // 在运行时中初始化核心组件
    let result = runtime.block_on(async {
        // 加载或生成密钥对
        let identity = if !identity_path.is_empty() {
            // 使用指定的路径加载或生成密钥对
            tracing::info!("尝试从文件加载密钥对: {}", identity_path);
            match IdentityManager::load_or_generate(std::path::Path::new(&identity_path)) {
                Ok(keypair) => {
                    let peer_id = keypair.public().to_peer_id();
                    tracing::info!("✓ 成功加载密钥对，Peer ID: {}", peer_id);
                    Some(keypair)
                }
                Err(e) => {
                    tracing::warn!("密钥对加载失败，将生成临时密钥对: {}", e);
                    None
                }
            }
        } else {
            // 未指定路径，生成临时密钥对
            tracing::info!("未指定密钥文件路径，将生成临时密钥对");
            None
        };

        // 创建用户信息
        let user_info = UserInfo::new(device_name.clone())
            .with_status("在线".to_string());

        // 创建节点管理器配置
        let config = NodeManagerConfig::new()
            .with_protocol_version("/localp2p/1.0.0".to_string())
            .with_agent_prefix(Some("localp2p-rust/".to_string()))
            .with_device_name(device_name.clone());

        let node_manager = Arc::new(NodeManager::new(config));

        // 启动后台清理任务
        node_manager.clone().spawn_cleanup_task();

        // 创建健康检查配置
        let health_config = HealthCheckConfig {
            heartbeat_interval: std::time::Duration::from_secs(10),
            max_failures: 3,
        };

        // 解析监听地址
        let listen_addresses = vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()];

        // 保存 identity 的克隆，用于后续保存到 P2PInstance
        let identity_for_instance = identity.clone();

        // 创建发现器，传入密钥对（如果有）
        let discovery_result = ManagedDiscovery::new(
            node_manager.clone(),
            listen_addresses,
            health_config,
            user_info,
            identity,
        ).await;

        let mut discovery = match discovery_result {
            Ok(d) => d,
            Err(e) => {
                return Err(format!("Failed to create discovery: {:?}", e));
            }
        };

        let local_peer_id = discovery.local_peer_id().to_string();

        // 启用聊天功能
        if let Err(e) = discovery.enable_chat().await {
            tracing::error!("Failed to enable chat: {:?}", e);
        }

        // 创建命令通道
        let (command_tx, command_rx) = tokio::sync::mpsc::unbounded_channel();

        // 获取 chat 事件接收器
        let chat_event_rx = discovery.take_chat_events();

        // 创建实例
        let instance = P2PInstance {
            node_manager,
            local_peer_id: local_peer_id.clone(),
            device_name: device_name.clone(),
            identity: identity_for_instance, // 保存 identity 以保持 Peer ID 稳定
            command_tx,
            discovery_thread: None,
        };

        // 保存到全局变量
        unsafe {
            DISCOVERY_RESOURCES = Some(GlobalDiscoveryResources {
                discovery: Some(discovery),
                chat_event_rx,
                command_rx: Some(command_rx),
                event_tx: None, // 不使用旧的 event_tx
            });

            P2P_INSTANCE = Some(Arc::new(Mutex::new(instance)));
        }

        tracing::info!("✓ P2P 初始化成功");
        tracing::info!("  设备名称: {}", device_name);
        tracing::info!("  Peer ID: {}", local_peer_id);
        if !identity_path.is_empty() {
            tracing::info!("  密钥文件路径: {}", identity_path);
            tracing::info!("  ✓ 使用持久化密钥对，Peer ID 将保持不变");
        } else {
            tracing::warn!("  未指定密钥文件路径，每次启动会生成新的 Peer ID");
        }

        Ok::<(), String>(())
    });

    result
}

/// 内部启动函数（供 FRB 调用）
pub fn internal_start() -> Result<(), String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;

        // 启动 discovery 事件循环
        if let Some(resources) = DISCOVERY_RESOURCES.as_mut() {
            let discovery = resources.discovery.take();
            let chat_event_rx = resources.chat_event_rx.take();
            let command_rx = resources.command_rx.take();

            if let (Some(discovery), Some(chat_event_rx), Some(command_rx)) = (discovery, chat_event_rx, command_rx) {
                // 启动 discovery 线程
                let handle = std::thread::spawn(move || {
                    runtime.block_on(async move {
                        tracing::info!("FRB Discovery 线程启动");
                        send_log_to_flutter("INFO", "ffi", "Discovery 线程启动".to_string());
                        let mut discovery = discovery;
                        let mut command_rx = command_rx;
                        let mut chat_event_rx = chat_event_rx;

                        loop {
                            tokio::select! {
                                // 处理 discovery 事件
                                result = discovery.run() => {
                                    match result {
                                        Ok(event) => {
                                            // 更新最后事件时间（任何 discovery 事件都算）
                                            update_last_event_time();

                                            use mdns::managed_discovery::DiscoveryEvent;
                                            match event {
                                                DiscoveryEvent::Discovered(peer_id, addr) => {
                                                    send_log_to_flutter(
                                                        "INFO",
                                                        "discovery",
                                                        format!("发现节点: {} @ {}", peer_id, addr)
                                                    );
                                                    let event = bridge::P2PEvent {
                                                        event_type: 1,
                                                        data: format!(r#"{{"peer_id":"{}","addr":"{}"}}"#, peer_id, addr),
                                                    };
                                                    // 同时发送到 Stream 和队列（兼容模式）
                                                    send_event_to_stream(event.clone());
                                                    let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                                    queue.push(event);
                                                }
                                                DiscoveryEvent::Verified(peer_id) => {
                                                    send_log_to_flutter(
                                                        "INFO",
                                                        "discovery",
                                                        format!("验证节点: {}", peer_id)
                                                    );
                                                    let display_name = peer_id.to_string();
                                                    let event = bridge::P2PEvent {
                                                        event_type: 3,
                                                        data: format!(r#"{{"peer_id":"{}","display_name":"{}"}}"#, peer_id, display_name),
                                                    };
                                                    // 同时发送到 Stream 和队列（兼容模式）
                                                    send_event_to_stream(event.clone());
                                                    let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                                    queue.push(event);
                                                }
                                                DiscoveryEvent::NodeOffline(peer_id) => {
                                                    send_log_to_flutter(
                                                        "WARN",
                                                        "discovery",
                                                        format!("节点离线: {}", peer_id)
                                                    );
                                                    let event = bridge::P2PEvent {
                                                        event_type: 4,
                                                        data: format!(r#"{{"peer_id":"{}"}}"#, peer_id),
                                                    };
                                                    // 同时发送到 Stream 和队列（兼容模式）
                                                    send_event_to_stream(event.clone());
                                                    let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                                    queue.push(event);

                                                    // 从用户信息缓存中移除
                                                    if let Some(cache) = GLOBAL_USER_INFO.lock().ok() {
                                                        let mut cache = cache.write().unwrap();
                                                        cache.remove(&peer_id.to_string());
                                                    }
                                                }
                                                DiscoveryEvent::UserInfoReceived(peer_id, user_info) => {
                                                    // 更新全局用户信息缓存
                                                    if let Some(cache) = GLOBAL_USER_INFO.lock().ok() {
                                                        let mut cache = cache.write().unwrap();
                                                        cache.insert(peer_id.to_string(), user_info.clone());
                                                    }

                                                    // 发送用户信息事件到 Flutter
                                                    let event = bridge::P2PEvent {
                                                        event_type: 5, // UserInfoReceived
                                                        data: format!(r#"{{"peer_id":"{}","device_name":"{}","nickname":"{}","status":"{}","avatar_url":"{}"}}"#,
                                                            peer_id,
                                                            user_info.device_name,
                                                            user_info.nickname.as_ref().unwrap_or(&String::new()),
                                                            user_info.status.as_ref().unwrap_or(&String::new()),
                                                            user_info.avatar_url.as_ref().unwrap_or(&String::new()),
                                                        ),
                                                    };
                                                    // 同时发送到 Stream 和队列（兼容模式）
                                                    send_event_to_stream(event.clone());
                                                    let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                                    queue.push(event);
                                                }
                                                _ => {}
                                            }
                                        }
                                        Err(e) => {
                                            let error_msg = format!("Discovery error: {:?}", e);
                                            tracing::error!("{}", error_msg);
                                            send_log_to_flutter("ERROR", "discovery", error_msg);
                                            break;
                                        }
                                    }
                                }

                                // 处理命令
                                Some(command) = command_rx.recv() => {
                                    match command {
                                        P2PCommand::SendMessage { target_peer_id, message, response_tx } => {
                                            let peer_id: libp2p::PeerId = match target_peer_id.parse() {
                                                Ok(id) => id,
                                                Err(e) => {
                                                    let _ = response_tx.send(Err(format!("Invalid peer_id: {:?}", e)));
                                                    continue;
                                                }
                                            };

                                            let chat_msg = mdns::ChatMessage::text(message);
                                            let result = discovery.send_message(peer_id, chat_msg).await;
                                            let _ = response_tx.send(result.map(|_| "OK".to_string()).map_err(|e| format!("{:?}", e)));
                                        }
                                        P2PCommand::BroadcastMessage { target_peer_ids, message, response_tx } => {
                                            let mut peer_ids = Vec::new();
                                            let mut parse_error = None;

                                            for target in &target_peer_ids {
                                                match target.parse::<libp2p::PeerId>() {
                                                    Ok(id) => peer_ids.push(id),
                                                    Err(e) => {
                                                        parse_error = Some(format!("Invalid peer_id: {:?} - {:?}", target, e));
                                                        break;
                                                    }
                                                }
                                            }

                                            if let Some(err) = parse_error {
                                                let _ = response_tx.send(Err(err));
                                            } else {
                                                let chat_msg = mdns::ChatMessage::text(message);
                                                let result = discovery.broadcast_message(peer_ids, chat_msg).await;
                                                let _ = response_tx.send(result.map(|_| "OK".to_string()).map_err(|e| format!("{:?}", e)));
                                            }
                                        }
                                        P2PCommand::Ping { response_tx } => {
                                            // Ping 命令用于健康检查
                                            let _ = response_tx.send(Ok(()));
                                        }
                                        P2PCommand::Stop => {
                                            tracing::info!("Received stop command");
                                            break;
                                        }
                                    }
                                }

                                // 处理 chat 事件
                                Some(chat_event) = chat_event_rx.recv() => {
                                    use mdns::chat::ChatEvent;
                                    match chat_event {
                                        ChatEvent::MessageReceived { from, message } => {
                                            if let mdns::chat::ChatMessage::Text(text) = message {
                                                let event = bridge::P2PEvent {
                                                    event_type: 6,
                                                    data: format!(r#"{{"from":"{}","content":"{}","timestamp":{}}}"#, from, text.content, text.timestamp),
                                                };
                                                // 同时发送到 Stream 和队列（兼容模式）
                                                send_event_to_stream(event.clone());
                                                let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                                queue.push(event);
                                            }
                                        }
                                        ChatEvent::MessageSent { to, message_id } => {
                                            let event = bridge::P2PEvent {
                                                event_type: 7,
                                                data: format!(r#"{{"to":"{}","message_id":"{}"}}"#, to, message_id),
                                            };
                                            // 同时发送到 Stream 和队列（兼容模式）
                                            send_event_to_stream(event.clone());
                                            let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                            queue.push(event);
                                        }
                                        ChatEvent::PeerTyping { from, is_typing } => {
                                            let event = bridge::P2PEvent {
                                                event_type: 8,
                                                data: format!(r#"{{"from":"{}","is_typing":{}}}"#, from, is_typing),
                                            };
                                            // 同时发送到 Stream 和队列（兼容模式）
                                            send_event_to_stream(event.clone());
                                            let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
                                            queue.push(event);
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        }

                        tracing::info!("FRB Discovery 线程结束");
                        send_log_to_flutter("WARN", "ffi", "Discovery 线程结束".to_string());
                    });
                });

                // 保存线程句柄
                if let Some(instance) = P2P_INSTANCE.as_mut() {
                    let mut inst = instance.lock().unwrap();
                    inst.discovery_thread = Some(handle);
                }
            } else {
                return Err("Discovery resources not complete".to_string());
            }
        } else {
            return Err("Discovery resources not available".to_string());
        }

        // 设置运行标志
        P2P_IS_RUNNING = true;
        send_log_to_flutter("INFO", "ffi", "P2P 服务已启动".to_string());

        Ok(())
    }
}

/// 获取事件接收器（供 FRB stream 使用）
pub async fn get_event_receiver() -> Result<tokio::sync::mpsc::UnboundedReceiver<bridge::P2PEvent>, String> {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    *GLOBAL_EVENT_TX.lock().unwrap() = Some(tx);

    // 启动事件转发任务
    if let Some(resources) = unsafe { DISCOVERY_RESOURCES.as_mut() } {
        let discovery = resources.discovery.take();
        let chat_event_rx = resources.chat_event_rx.take();
        let command_rx = resources.command_rx.take();

        if let (Some(discovery), Some(mut chat_event_rx), Some(mut command_rx)) = (discovery, chat_event_rx, command_rx) {
            tokio::spawn(async move {
                let event_tx = GLOBAL_EVENT_TX.lock().unwrap().clone();
                let mut discovery = discovery;

                loop {
                    tokio::select! {
                        // 处理 discovery 事件
                        result = discovery.run() => {
                            match result {
                                Ok(event) => {
                                    // 更新最后事件时间（任何 discovery 事件都算）
                                    update_last_event_time();

                                    use mdns::managed_discovery::DiscoveryEvent;
                                    if let Some(tx) = event_tx.as_ref() {
                                        match event {
                                            DiscoveryEvent::Discovered(peer_id, addr) => {
                                                let _ = tx.send(bridge::P2PEvent {
                                                    event_type: 1,
                                                    data: format!(r#"{{"peer_id":"{}","addr":"{}"}}"#, peer_id, addr),
                                                });
                                            }
                                            DiscoveryEvent::Verified(peer_id) => {
                                                let display_name = peer_id.to_string();
                                                let _ = tx.send(bridge::P2PEvent {
                                                    event_type: 3,
                                                    data: format!(r#"{{"peer_id":"{}","display_name":"{}"}}"#, peer_id, display_name),
                                                });
                                            }
                                            DiscoveryEvent::NodeOffline(peer_id) => {
                                                let _ = tx.send(bridge::P2PEvent {
                                                    event_type: 4,
                                                    data: format!(r#"{{"peer_id":"{}"}}"#, peer_id),
                                                });
                                            }
                                            _ => {}
                                        }
                                    }
                                }
                                Err(e) => {
                                    tracing::error!("Discovery error: {:?}", e);
                                    break;
                                }
                            }
                        }

                        // 处理命令
                        Some(command) = command_rx.recv() => {
                            match command {
                                P2PCommand::Ping { response_tx } => {
                                    // Ping 命令用于健康检查
                                    let _ = response_tx.send(Ok(()));
                                }
                                P2PCommand::Stop => {
                                    tracing::info!("Received stop command");
                                    break;
                                }
                                _ => {}
                            }
                        }

                        // 处理 chat 事件
                        Some(chat_event) = chat_event_rx.recv() => {
                            use mdns::chat::ChatEvent;
                            if let Some(tx) = event_tx.as_ref() {
                                match chat_event {
                                    ChatEvent::MessageReceived { from, message } => {
                                        use mdns::chat::ChatMessage;
                                        if let ChatMessage::Text(text) = message {
                                            let _ = tx.send(bridge::P2PEvent {
                                                event_type: 6,
                                                data: format!(r#"{{"from":"{}","content":"{}","timestamp":{}}}"#, from, text.content, text.timestamp),
                                            });
                                        }
                                    }
                                    ChatEvent::MessageSent { to, message_id } => {
                                        let _ = tx.send(bridge::P2PEvent {
                                            event_type: 7,
                                            data: format!(r#"{{"to":"{}","message_id":"{}"}}"#, to, message_id),
                                        });
                                    }
                                    ChatEvent::PeerTyping { from, is_typing } => {
                                        let _ = tx.send(bridge::P2PEvent {
                                            event_type: 8,
                                            data: format!(r#"{{"from":"{}","is_typing":{}}}"#, from, is_typing),
                                        });
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                }
            });
        }
    }

    Ok(rx)
}

/// 内部停止函数
pub fn internal_stop() -> Result<(), String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        // 发送停止命令
        if let Some(instance) = P2P_INSTANCE.as_ref() {
            let inst = instance.lock().unwrap();
            let _ = inst.command_tx.send(P2PCommand::Stop);
        }

        // 清除运行标志
        P2P_IS_RUNNING = false;
        send_log_to_flutter("INFO", "ffi", "P2P 服务已停止".to_string());

        P2P_INSTANCE = None;
        Ok(())
    }
}

/// 内部清理函数
pub fn internal_cleanup() {
    unsafe {
        P2P_INSTANCE = None;
        P2P_IS_RUNNING = false;
        RUNTIME = None;
        DISCOVERY_RESOURCES = None;

        // 清空用户信息缓存
        if let Some(cache) = GLOBAL_USER_INFO.lock().ok() {
            let mut cache = cache.write().unwrap();
            cache.clear();
        }
    }

    // 清空全局事件通道
    *GLOBAL_EVENT_TX.lock().unwrap() = None;

    // 清空 FRB 事件队列
    let mut frb_queue = FRB_EVENT_QUEUE.lock().unwrap();
    frb_queue.clear();

    // 清空 StreamSink
    *GLOBAL_STREAM_SINK.lock().unwrap() = None;
}

// ============================================================================
// 状态检查函数
// ============================================================================

/// 检查 P2P 是否已初始化
pub fn internal_is_initialized() -> bool {
    unsafe { P2P_INSTANCE.is_some() }
}

/// 检查 P2P 服务是否正在运行
pub fn internal_is_running() -> bool {
    unsafe { P2P_IS_RUNNING }
}

/// 检查 discovery 线程是否真的活着
///
/// 通过两个条件检查：
/// 1. Ping 命令检查线程是否响应
/// 2. 检查是否在最近收到过 discovery 事件（验证 mDNS 是否工作）
pub fn internal_is_discovery_thread_alive() -> bool {
    send_log_to_flutter("INFO", "ffi", "开始 Discovery 健康检查...".to_string());

    unsafe {
        if P2P_INSTANCE.is_none() {
            send_log_to_flutter("WARN", "ffi", "P2P 实例不存在，无法检查健康状态".to_string());
            return false;
        }

        let instance = P2P_INSTANCE.as_ref().unwrap();
        let inst = instance.lock().unwrap();

        // 发送 Ping 命令
        let (response_tx, response_rx) = tokio::sync::oneshot::channel();
        let ping_command = P2PCommand::Ping { response_tx };

        if let Err(_) = inst.command_tx.send(ping_command) {
            send_log_to_flutter("ERROR", "ffi", "Ping 发送失败，线程已死".to_string());
            return false;
        }
        drop(inst);

        let runtime = RUNTIME.as_ref();
        if let Some(rt) = runtime {
            let ping_result = rt.block_on(async {
                tokio::time::timeout(
                    std::time::Duration::from_millis(100),
                    response_rx
                ).await
            });

            let ping_alive = ping_result.is_ok() && ping_result.unwrap().is_ok();

            // 检查最后事件时间
            let event_alive = if let Some(elapsed) = time_since_last_event() {
                // 如果超过 10 秒没有事件，认为 discovery 已停止工作
                // 降低阈值以更快检测到从后台恢复时的 mDNS 问题
                let is_alive = elapsed.as_secs() < 10;
                if !is_alive {
                    send_log_to_flutter(
                        "WARN",
                        "ffi",
                        format!("距离上次事件已 {:.1} 秒，超过阈值 10 秒，discovery 可能已停止", elapsed.as_secs_f64())
                    );
                }
                send_log_to_flutter(
                    "INFO",
                    "ffi",
                    format!("距离上次事件 {:.1} 秒", elapsed.as_secs_f64())
                );
                is_alive
            } else {
                send_log_to_flutter("INFO", "ffi", "尚未收到过 discovery 事件".to_string());
                true // 如果还没有收到过事件，暂时认为健康
            };

            let alive = ping_alive && event_alive;
            send_log_to_flutter(
                "INFO",
                "ffi",
                format!("Discovery 健康检查结果: Ping={} 事件时间={} => {}", ping_alive, event_alive, alive)
            );

            alive
        } else {
            send_log_to_flutter("ERROR", "ffi", "运行时不存在".to_string());
            false
        }
    }
}

/// 重启 discovery 服务
///
/// 用于应用从后台恢复时，如果发现线程已死，重启它
/// 如果服务仍在运行，会先停止再重启
pub fn internal_restart_discovery() -> Result<(), String> {
    send_log_to_flutter("INFO", "ffi", "开始重启 Discovery 服务".to_string());

    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;

        // 发送停止命令给 discovery 线程
        if let Some(instance) = P2P_INSTANCE.as_ref() {
            let inst = instance.lock().unwrap();
            let _ = inst.command_tx.send(P2PCommand::Stop);
            drop(inst);
        }

        // 清除运行标志（但不删除 P2P_INSTANCE）
        P2P_IS_RUNNING = false;
        send_log_to_flutter("INFO", "ffi", "已停止旧 Discovery 服务".to_string());

        // 等待一小段时间确保线程退出
        std::thread::sleep(std::time::Duration::from_millis(300));

        // 记录 identity 使用情况
        let has_identity = {
            let inst = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
            inst.identity.is_some()
        };

        if has_identity {
            send_log_to_flutter("INFO", "ffi", "重启时使用保存的密钥对，Peer ID 将保持不变".to_string());
        } else {
            send_log_to_flutter("INFO", "ffi", "重启时生成新密钥对，Peer ID 将变化".to_string());
        }

        // 重新创建 discovery 资源
        let (node_manager, device_name, local_peer_id, identity) = {
            let inst = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
            (
                inst.node_manager.clone(),
                inst.device_name.clone(),
                inst.local_peer_id.clone(),
                inst.identity.clone(), // 获取保存的 identity
            )
        };

        // 在运行时中创建新的 discovery
        let result = runtime.block_on(async {
            // 创建用户信息
            let user_info = UserInfo::new(device_name.clone())
                .with_status("在线".to_string());

            // 创建健康检查配置
            let health_config = HealthCheckConfig {
                heartbeat_interval: std::time::Duration::from_secs(10),
                max_failures: 3,
            };

            // 解析监听地址
            let listen_addresses = vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()];

            // 创建新的 discovery，使用保存的 identity 以保持 Peer ID 稳定
            let discovery_result = ManagedDiscovery::new(
                node_manager.clone(),
                listen_addresses,
                health_config,
                user_info,
                identity, // 使用保存的密钥对
            ).await;

            match discovery_result {
                Ok(mut discovery) => {
                    // 启用聊天功能
                    if let Err(e) = discovery.enable_chat().await {
                        tracing::error!("Failed to enable chat: {:?}", e);
                    }

                    // 获取 chat 事件接收器
                    let chat_event_rx = discovery.take_chat_events();

                    // 创建新的命令通道
                    let (command_tx, command_rx) = tokio::sync::mpsc::unbounded_channel();

                    // 创建新的事件通道
                    let (event_tx, _) = tokio::sync::mpsc::unbounded_channel();

                    // 更新 P2P_INSTANCE 中的 command_tx
                    if let Some(instance) = P2P_INSTANCE.as_ref() {
                        let mut inst = instance.lock().unwrap();
                        inst.command_tx = command_tx.clone();
                    }

                    Ok((discovery, chat_event_rx, command_rx, event_tx, command_tx))
                }
                Err(e) => {
                    Err(format!("Failed to create discovery: {:?}", e))
                }
            }
        });

        let (discovery, chat_event_rx, command_rx, event_tx, command_tx) = result?;

        // 将新资源放入 DISCOVERY_RESOURCES
        DISCOVERY_RESOURCES = Some(GlobalDiscoveryResources {
            discovery: Some(discovery),
            chat_event_rx,
            command_rx: Some(command_rx),
            event_tx: Some(event_tx),
        });

        // 等待一小段时间
        std::thread::sleep(std::time::Duration::from_millis(100));

        // 调用 internal_start 启动 discovery 线程
        internal_start()?;
        send_log_to_flutter("INFO", "ffi", "Discovery 服务重启成功".to_string());

        Ok(())
    }
}

// ============================================================================
// 内部查询函数
// ============================================================================

/// 获取本地 Peer ID
pub async fn internal_get_local_peer_id() -> Result<String, String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
        Ok(instance.local_peer_id.clone())
    }
}

/// 获取设备名称
pub async fn internal_get_device_name() -> Result<String, String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
        Ok(instance.device_name.clone())
    }
}

/// 获取已验证的节点列表
///
/// 注意：这是一个同步函数，因为需要在内部使用 block_on
/// 调用此函数需要 tokio::task::spawn_blocking
pub fn internal_get_nodes_sync() -> Result<Vec<InternalNodeInfo>, String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let node_manager = {
            let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
            instance.node_manager.clone()
        };

        // 在正确的运行时上执行异步操作
        let nodes = runtime.block_on(async {
            node_manager.list_nodes().await
        });

        // 同时从用户信息缓存中获取详细信息
        let user_info_cache: HashMap<String, mdns::UserInfo> = GLOBAL_USER_INFO
            .lock()
            .unwrap()
            .read()
            .unwrap()
            .clone();

        Ok(nodes.into_iter().map(|node| {
            let peer_id = node.peer_id.to_string();
            if let Some(user_info) = user_info_cache.get(&peer_id) {
                // 使用缓存的用户信息
                InternalNodeInfo {
                    peer_id: peer_id.clone(),
                    display_name: user_info.display_name(),
                    device_name: user_info.device_name.clone(),
                    nickname: user_info.nickname.clone(),
                    status: user_info.status.clone(),
                    avatar_url: user_info.avatar_url.clone(),
                }
            } else {
                // 使用基本信息
                InternalNodeInfo {
                    peer_id: peer_id.clone(),
                    display_name: node.display_name(),
                    device_name: node.name.unwrap_or_default(),
                    nickname: None,
                    status: None,
                    avatar_url: None,
                }
            }
        }).collect())
    }
}

/// 获取已验证的节点列表（async 包装器）
pub async fn internal_get_nodes() -> Result<Vec<InternalNodeInfo>, String> {
    // 使用 spawn_blocking 在后台线程执行同步操作
    let handle = tokio::task::spawn_blocking(|| {
        internal_get_nodes_sync()
    });
    handle.await.map_err(|e| format!("Join error: {:?}", e))?
}

/// 获取指定节点的用户信息
pub async fn internal_get_user_info(peer_id: String) -> Result<Option<bridge::P2PBridgeNodeInfo>, String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        // 从用户信息缓存中获取
        if let Some(cache) = GLOBAL_USER_INFO.lock().ok() {
            let cache = cache.read().unwrap();
            if let Some(user_info) = cache.get(&peer_id) {
                return Ok(Some(bridge::P2PBridgeNodeInfo::from_peer_id_and_info(
                    peer_id.clone(),
                    user_info
                )));
            }
        }

        Ok(None)
    }
}

/// 获取所有节点的用户信息
pub async fn internal_list_user_info() -> Result<Vec<bridge::P2PBridgeNodeInfo>, String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        // 从用户信息缓存中获取所有信息
        if let Some(cache) = GLOBAL_USER_INFO.lock().ok() {
            let cache = cache.read().unwrap();
            let result = cache.iter().map(|(peer_id, user_info)| {
                bridge::P2PBridgeNodeInfo::from_peer_id_and_info(
                    peer_id.clone(),
                    user_info
                )
            }).collect();
            return Ok(result);
        }

        Ok(Vec::new())
    }
}

// ============================================================================
// 内部消息函数
// ============================================================================

/// 发送消息（同步版本）
fn internal_send_message_sync(target_peer_id: String, message: String) -> Result<(), String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let (response_tx, response_rx) = tokio::sync::oneshot::channel();
        let command = P2PCommand::SendMessage {
            target_peer_id,
            message,
            response_tx,
        };

        let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
        if let Err(_) = instance.command_tx.send(command) {
            return Err("Failed to send command".to_string());
        }
        drop(instance);

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let result = runtime.block_on(async {
            response_rx.await
                .map_err(|e| format!("Response error: {:?}", e))
                .and_then(|r| r)
        });

        result.map(|_| ())
    }
}

/// 发送消息
pub async fn internal_send_message(target_peer_id: String, message: String) -> Result<(), String> {
    let (peer_id, msg) = (target_peer_id, message);
    tokio::task::spawn_blocking(move || {
        internal_send_message_sync(peer_id, msg)
    })
    .await
    .map_err(|e| format!("Join error: {:?}", e))?
}

/// 广播消息（同步版本）
fn internal_broadcast_message_sync(target_peer_ids: Vec<String>, message: String) -> Result<(), String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let (response_tx, response_rx) = tokio::sync::oneshot::channel();
        let command = P2PCommand::BroadcastMessage {
            target_peer_ids,
            message,
            response_tx,
        };

        let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
        if let Err(_) = instance.command_tx.send(command) {
            return Err("Failed to send command".to_string());
        }
        drop(instance);

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let result = runtime.block_on(async {
            response_rx.await
                .map_err(|e| format!("Response error: {:?}", e))
                .and_then(|r| r)
        });

        result.map(|_| ())
    }
}

/// 广播消息
pub async fn internal_broadcast_message(target_peer_ids: Vec<String>, message: String) -> Result<(), String> {
    let (peer_ids, msg) = (target_peer_ids, message);
    tokio::task::spawn_blocking(move || {
        internal_broadcast_message_sync(peer_ids, msg)
    })
    .await
    .map_err(|e| format!("Join error: {:?}", e))?
}

// ============================================================================
// 事件轮询函数（供 FRB 调用）
// ============================================================================

/// 全局事件队列（用于 FRB 轮询）
static FRB_EVENT_QUEUE: Mutex<Vec<bridge::P2PEvent>> = Mutex::new(Vec::new());

/// 全局 StreamSink（用于 FRB Stream 模式）
static GLOBAL_STREAM_SINK: Mutex<Option<frb_generated::StreamSink<bridge::P2PEvent, flutter_rust_bridge::for_generated::SseCodec>>> = Mutex::new(None);

/// 设置事件流接收器（用于 Stream 模式）
///
/// 这个函数会保存 StreamSink，之后的 P2P 事件会通过它推送到 Flutter
pub fn set_event_stream_sink(stream_sink: frb_generated::StreamSink<bridge::P2PEvent, flutter_rust_bridge::for_generated::SseCodec>) -> Result<(), String> {
    let mut sink = GLOBAL_STREAM_SINK.lock().map_err(|e| format!("Failed to lock stream sink: {:?}", e))?;
    *sink = Some(stream_sink);
    Ok(())
}

/// 发送事件到 StreamSink（如果已设置）
fn send_event_to_stream(event: crate::bridge::P2PBridgeEvent) {
    if let Ok(sink) = GLOBAL_STREAM_SINK.lock() {
        if let Some(ref sink) = *sink {
            // 将事件添加到 Stream，忽略错误
            let _: Result<(), flutter_rust_bridge::Rust2DartSendError> = sink.add(event);
        }
    }
}

/// 发送 Rust 日志到 Flutter
///
/// 将 Rust 的 tracing 日志转发到 Flutter，便于调试
///
/// # Arguments
/// * `level` - 日志级别 (ERROR, WARN, INFO, DEBUG, TRACE)
/// * `target` - 日志目标 (模块名)
/// * `message` - 日志消息
fn send_log_to_flutter(level: &str, target: &str, message: String) {
    let data = format!(
        r#"{{"level":"{}","target":"{}","message":"{}"}}"#,
        level,
        target,
        message.replace('"', "\\\"")
    );

    let event = bridge::P2PBridgeEvent {
        event_type: 9, // Log 事件
        data,
    };

    send_event_to_stream(event);
}

/// 轮询事件（返回所有待处理的事件并清空队列）
pub fn poll_events() -> Vec<bridge::P2PEvent> {
    let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
    let events = queue.drain(..).collect();
    events
}

// ============================================================================
// 事件获取函数（供 FRB 调用）
// ============================================================================

/// 获取下一个事件（阻塞式）
/// Flutter 可以在一个单独的 isolate 中轮询调用这个函数
pub async fn get_next_event() -> Option<bridge::P2PEvent> {
    // 从全局事件通道获取事件
    // 注意：这个实现需要配合 get_event_receiver 修改
    // 因为 get_event_receiver 已经启动了后台任务
    // 这里需要创建一个临时接收器来获取事件

    // 简化实现：返回 None，实际应该从事件队列中获取
    // 完整实现需要重构事件系统
    None
}
