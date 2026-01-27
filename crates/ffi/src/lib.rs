//! Local P2P FFI 层
//!
//! 提供 C ABI 兼容的接口，供 Flutter/Dart 调用
//!
//! 使用事件队列模式：Rust 将事件放入队列，Dart 通过轮询获取事件
//! 这样避免了从 Rust 后台线程直接调用 Dart 回调的问题

#![allow(clippy::missing_safety_doc)]

use std::ffi::{CStr, CString, c_char};
use std::sync::{Arc, Mutex};
use std::thread;
use libc::size_t;
use tokio::runtime::Runtime;
use mdns::{
    ManagedDiscovery, NodeManager, NodeManagerConfig,
    HealthCheckConfig, UserInfo, ChatExtension, ChatMessage,
};

mod types;
mod error;

use types::*;

// ============================================================================
// 全局运行时和状态管理
// ============================================================================

/// 全局 Tokio 运行时
static mut RUNTIME: Option<Runtime> = None;

/// 全局 P2P 实例
static mut P2P_INSTANCE: Option<Arc<Mutex<P2PInstance>>> = None;

/// 全局 Discovery 资源存储（在 init 和 start 之间传递）
struct GlobalDiscoveryResources {
    discovery: Option<ManagedDiscovery>,
    chat_event_rx: Option<tokio::sync::mpsc::UnboundedReceiver<mdns::chat::ChatEvent>>,
    command_rx: Option<tokio::sync::mpsc::UnboundedReceiver<P2PCommand>>,
    event_tx: Option<tokio::sync::mpsc::UnboundedSender<P2PEvent>>,
}

static mut DISCOVERY_RESOURCES: Option<GlobalDiscoveryResources> = None;

/// 事件队列（线程安全，Rust 写入，Dart 轮询读取）
static EVENT_QUEUE: Mutex<Vec<EventData>> = Mutex::new(Vec::new());

/// 事件数据（可序列化到 Dart）
#[derive(Clone)]
struct EventData {
    event_type: i32,
    data: String,
}

/// P2P 实例（包含所有核心组件）
struct P2PInstance {
    node_manager: Arc<NodeManager>,
    local_peer_id: String,
    device_name: String,
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
    Stop,
}

// ============================================================================
// 初始化和生命周期管理
// ============================================================================

/// 初始化 P2P 模块
///
/// # Safety
/// 必须在使用任何其他函数之前调用，且只能调用一次
#[no_mangle]
pub unsafe extern "C" fn localp2p_init(
    device_name: *const c_char,
    error_out: *mut *mut c_char,
) -> P2PHandle {
    // 初始化日志
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init()
        .ok();

    // 解析设备名称
    let device_name: String = match unsafe_cstr_to_string(device_name) {
        Ok(name) if !name.is_empty() => name,
        _ => "Unnamed Device".to_string(),
    };

    // 创建 Tokio 运行时
    RUNTIME = Some(
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to create runtime")
    );

    let runtime = RUNTIME.as_ref().unwrap();

    // 在运行时中初始化核心组件
    let (instance, result) = runtime.block_on(async {
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

        // 创建发现器
        let listen_addresses = vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()];
        let discovery_result = ManagedDiscovery::new(
            node_manager.clone(),
            listen_addresses,
            health_config,
            user_info,
        ).await;

        let mut discovery = match discovery_result {
            Ok(d) => d,
            Err(e) => {
                let error_msg = CString::new(format!("Failed to create discovery: {:?}", e))
                    .unwrap().into_raw();
                if !error_out.is_null() {
                    *error_out = error_msg;
                }
                return (None, Err(()));
            }
        };

        let local_peer_id = discovery.local_peer_id().to_string();

        // 启用聊天功能
        if let Err(e) = discovery.enable_chat().await {
            tracing::error!("Failed to enable chat: {:?}", e);
        }

        // 创建命令通道
        let (command_tx, command_rx) = tokio::sync::mpsc::unbounded_channel();

        // 创建事件通道
        let (event_tx, mut event_rx) = tokio::sync::mpsc::unbounded_channel();

        // 获取 chat 事件接收器
        let chat_event_rx = discovery.take_chat_events();

        // 创建实例
        let instance = P2PInstance {
            node_manager,
            local_peer_id: local_peer_id.clone(),
            device_name,
            command_tx,
            discovery_thread: None,
        };

        // 启动事件处理任务（将事件放入队列）
        tokio::spawn(async move {
            while let Some(event) = event_rx.recv().await {
                let event_data = match event {
                    P2PEvent::NodeDiscovered { peer_id, .. } => EventData {
                        event_type: types::P2PEventType::NodeDiscovered as i32,
                        data: format!(r#"{{"peer_id":"{}"}}"#, peer_id),
                    },
                    P2PEvent::NodeVerified { peer_id, display_name } => EventData {
                        event_type: types::P2PEventType::NodeVerified as i32,
                        data: format!(r#"{{"peer_id":"{}","display_name":"{}"}}"#, peer_id, display_name),
                    },
                    P2PEvent::NodeOffline { peer_id } => EventData {
                        event_type: types::P2PEventType::NodeOffline as i32,
                        data: format!(r#"{{"peer_id":"{}"}}"#, peer_id),
                    },
                    P2PEvent::MessageReceived { from, message } => EventData {
                        event_type: types::P2PEventType::MessageReceived as i32,
                        data: format!(r#"{{"peer_id":"{}","message":"{}"}}"#, from, message.content),
                    },
                    P2PEvent::MessageSent { to, message_id } => EventData {
                        event_type: types::P2PEventType::MessageSent as i32,
                        data: format!(r#"{{"peer_id":"{}","message_id":"{}"}}"#, to, message_id),
                    },
                    P2PEvent::PeerTyping { from, is_typing } => EventData {
                        event_type: types::P2PEventType::PeerTyping as i32,
                        data: format!(r#"{{"peer_id":"{}","is_typing":{}}}"#, from, is_typing),
                    },
                    _ => continue,
                };

                // 将事件放入队列（线程安全）
                let mut queue = EVENT_QUEUE.lock().unwrap();
                queue.push(event_data);
            }
        });

        // 保存 discovery 和相关资源，供 localp2p_start 使用
        (Some((instance, discovery, chat_event_rx, command_rx, event_tx)), Ok(()))
    });

    match result {
        Ok(_) => {
            if let Some((instance, discovery, chat_event_rx, command_rx, event_tx)) = instance {
                // 保存到全局变量
                DISCOVERY_RESOURCES = Some(GlobalDiscoveryResources {
                    discovery: Some(discovery),
                    chat_event_rx,
                    command_rx: Some(command_rx),
                    event_tx: Some(event_tx),
                });

                P2P_INSTANCE = Some(Arc::new(Mutex::new(instance)));
                P2PHandle { _private: 0 }
            } else {
                P2PHandle { _private: 0 }
            }
        }
        Err(_) => P2PHandle { _private: 0 },
    }
}

/// 启动 P2P 服务并开始发现节点
///
/// # Safety
/// 必须在 `localp2p_init` 之后调用
#[no_mangle]
pub unsafe extern "C" fn localp2p_start(
    _handle: P2PHandle,
) -> P2PErrorCode {
    if P2P_INSTANCE.is_none() {
        return P2PErrorCode::NotInitialized;
    }

    // 从全局变量取出资源
    let resources = if let Some(ref mut res) = DISCOVERY_RESOURCES {
        (
            res.discovery.take(),
            res.chat_event_rx.take(),
            res.command_rx.take(),
            res.event_tx.take(),
        )
    } else {
        tracing::error!("Discovery resources not available");
        return P2PErrorCode::NotInitialized;
    };

    let (discovery, chat_event_rx, command_rx, event_tx) = resources;

    let mut command_rx = match command_rx {
        Some(rx) => rx,
        None => {
            tracing::error!("Command rx not available");
            return P2PErrorCode::NotInitialized;
        }
    };

    let mut chat_event_rx = match chat_event_rx {
        Some(rx) => rx,
        None => {
            tracing::error!("Chat event rx not available");
            return P2PErrorCode::NotInitialized;
        }
    };

    let discovery = match discovery {
        Some(d) => d,
        None => {
            tracing::error!("Discovery not available");
            return P2PErrorCode::NotInitialized;
        }
    };

    let event_tx = match event_tx {
        Some(tx) => tx,
        None => {
            tracing::error!("Event tx not available");
            return P2PErrorCode::NotInitialized;
        }
    };

    // 启动 discovery 线程
    let handle = thread::spawn(move || {
        let runtime = RUNTIME.as_ref().unwrap();
        runtime.block_on(async move {
            tracing::info!("Discovery 线程启动");

            // 将 discovery 放入任务中运行
            let mut discovery = discovery;

            // 创建一个任务来同时处理 discovery 事件和命令
            loop {
                tokio::select! {
                    // 处理 discovery 事件
                    result = discovery.run() => {
                        match result {
                            Ok(event) => {
                                use mdns::managed_discovery::DiscoveryEvent;
                                match event {
                                    DiscoveryEvent::Discovered(peer_id, addr) => {
                                        let _ = event_tx.send(P2PEvent::NodeDiscovered {
                                            peer_id: peer_id.to_string(),
                                            addr: addr.to_string(),
                                        });
                                    }
                                    DiscoveryEvent::Verified(peer_id) => {
                                        // 获取节点信息（如果有的话）
                                        let display_name = discovery.get_user_info(&peer_id)
                                            .and_then(|info| info.nickname.as_ref())
                                            .cloned()
                                            .unwrap_or_else(|| peer_id.to_string());

                                        let _ = event_tx.send(P2PEvent::NodeVerified {
                                            peer_id: peer_id.to_string(),
                                            display_name,
                                        });
                                    }
                                    DiscoveryEvent::NodeOffline(peer_id) => {
                                        let _ = event_tx.send(P2PEvent::NodeOffline {
                                            peer_id: peer_id.to_string(),
                                        });
                                    }
                                    _ => {}
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
                            P2PCommand::SendMessage { target_peer_id, message, response_tx } => {
                                let peer_id: libp2p::PeerId = match target_peer_id.parse() {
                                    Ok(id) => id,
                                    Err(e) => {
                                        let _ = response_tx.send(Err(format!("Invalid peer_id: {:?}", e)));
                                        continue;
                                    }
                                };

                                let chat_msg = ChatMessage::text(message);
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
                                    let chat_msg = ChatMessage::text(message);
                                    let result = discovery.broadcast_message(peer_ids, chat_msg).await;
                                    let _ = response_tx.send(result.map(|_| "OK".to_string()).map_err(|e| format!("{:?}", e)));
                                }
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
                                use mdns::chat::ChatMessage;
                                let (id, sender_peer_id, content, timestamp) = match message {
                                    ChatMessage::Text(text) => (
                                        text.id.clone(),
                                        text.sender_peer_id.clone(),
                                        text.content.clone(),
                                        text.timestamp,
                                    ),
                                    _ => (String::new(), String::new(), String::new(), 0),
                                };
                                let _ = event_tx.send(P2PEvent::MessageReceived {
                                    from: from.to_string(),
                                    message: ChatMessageJson {
                                        id,
                                        sender_peer_id,
                                        content,
                                        timestamp,
                                    },
                                });
                            }
                            ChatEvent::MessageSent { to, message_id } => {
                                let _ = event_tx.send(P2PEvent::MessageSent {
                                    to: to.to_string(),
                                    message_id,
                                });
                            }
                            ChatEvent::PeerTyping { from, is_typing } => {
                                let _ = event_tx.send(P2PEvent::PeerTyping {
                                    from: from.to_string(),
                                    is_typing,
                                });
                            }
                            _ => {}
                        }
                    }
                }
            }

            tracing::info!("Discovery 线程结束");
        });
    });

    // 保存线程句柄
    if let Some(instance) = P2P_INSTANCE.as_mut() {
        let mut inst = instance.lock().unwrap();
        inst.discovery_thread = Some(handle);
    }

    P2PErrorCode::Success
}

/// 轮询事件队列（Dart 调用此函数获取事件）
///
/// # Safety
/// 调用者负责释放返回的字符串
#[no_mangle]
pub unsafe extern "C" fn localp2p_poll_events(
    _handle: P2PHandle,
    out_events: *mut *mut EventRaw,
    out_count: *mut size_t,
) -> size_t {
    if out_events.is_null() || out_count.is_null() {
        return 0;
    }

    // 从队列中取出所有事件
    let mut queue = EVENT_QUEUE.lock().unwrap();
    let count = queue.len();

    if count == 0 {
        *out_count = 0;
        return 0;
    }

    // 转换为 C 数组
    let events: Vec<EventRaw> = queue.drain(..).map(|event| {
        let data_ptr = string_to_cstring(event.data).into_raw();
        EventRaw {
            event_type: event.event_type,
            data: data_ptr,
        }
    }).collect();

    let ptr = events.as_ptr() as *mut EventRaw;
    let len = events.len();
    std::mem::forget(events);

    *out_events = ptr;
    *out_count = len;

    len
}

/// 释放事件数组
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_free_events(
    events: *mut EventRaw,
    count: size_t,
) {
    if events.is_null() || count == 0 {
        return;
    }

    let slice = std::slice::from_raw_parts_mut(events, count);
    for event in slice {
        if !event.data.is_null() {
            let _ = CString::from_raw(event.data);
        }
    }
}

/// 停止 P2P 服务
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_stop(_handle: P2PHandle) -> P2PErrorCode {
    P2P_INSTANCE = None;
    P2PErrorCode::Success
}

/// 清理资源
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_cleanup(_handle: P2PHandle) {
    localp2p_stop(P2PHandle { _private: 0 });
    RUNTIME = None;

    // 清空事件队列
    let mut queue = EVENT_QUEUE.lock().unwrap();
    queue.clear();
}

// ============================================================================
// 节点管理
// ============================================================================

/// 获取本地 Peer ID
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_get_local_peer_id(
    _handle: P2PHandle,
    out: *mut c_char,
    out_len: size_t,
) -> P2PErrorCode {
    if P2P_INSTANCE.is_none() {
        return P2PErrorCode::NotInitialized;
    }

    let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
    let peer_id = instance.local_peer_id.clone();

    string_to_cstr(&peer_id, out, out_len);
    P2PErrorCode::Success
}

/// 获取设备名称
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_get_device_name(
    _handle: P2PHandle,
    out: *mut c_char,
    out_len: size_t,
) -> P2PErrorCode {
    if P2P_INSTANCE.is_none() {
        return P2PErrorCode::NotInitialized;
    }

    let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
    let device_name = instance.device_name.clone();

    string_to_cstr(&device_name, out, out_len);
    P2PErrorCode::Success
}

/// 获取已验证的节点列表
///
/// # Safety
/// 调用者负责释放返回的数组
#[no_mangle]
pub unsafe extern "C" fn localp2p_get_verified_nodes(
    _handle: P2PHandle,
    out: *mut *mut NodeInfo,
    out_len: *mut size_t,
) -> P2PErrorCode {
    if P2P_INSTANCE.is_none() {
        return P2PErrorCode::NotInitialized;
    }

    let runtime = RUNTIME.as_ref().unwrap();
    let node_manager = {
        let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
        instance.node_manager.clone()
    };
    let nodes = runtime.block_on(async {
        node_manager.list_nodes().await
    });

    let node_infos: Vec<NodeInfo> = nodes.into_iter().map(|node| NodeInfo {
        peer_id: string_to_cstring(node.peer_id.to_string()).into_raw(),
        display_name: string_to_cstring(node.display_name()).into_raw(),
        device_name: string_to_cstring(node.name.unwrap_or_default()).into_raw(),
        address_count: node.addresses.len() as size_t,
        addresses: std::ptr::null_mut(), // 简化实现
    }).collect();

    let ptr = node_infos.as_ptr() as *mut NodeInfo;
    let len = node_infos.len();
    std::mem::forget(node_infos);

    *out = ptr;
    *out_len = len;

    P2PErrorCode::Success
}

/// 释放节点列表
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_free_node_list(
    nodes: *mut NodeInfo,
    len: size_t,
) {
    if nodes.is_null() || len == 0 {
        return;
    }

    let slice = std::slice::from_raw_parts_mut(nodes, len);
    for node in slice {
        if !node.peer_id.is_null() {
            let _ = CString::from_raw(node.peer_id);
        }
        if !node.display_name.is_null() {
            let _ = CString::from_raw(node.display_name);
        }
        if !node.device_name.is_null() {
            let _ = CString::from_raw(node.device_name);
        }
    }
}

// ============================================================================
// 聊天功能
// ============================================================================

/// 发送消息
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_send_message(
    _handle: P2PHandle,
    target_peer_id: *const c_char,
    message: *const c_char,
    error_out: *mut *mut c_char,
) -> P2PErrorCode {
    if P2P_INSTANCE.is_none() {
        return P2PErrorCode::NotInitialized;
    }

    let target_peer_id = match unsafe_cstr_to_string(target_peer_id) {
        Ok(id) => id,
        Err(e) => {
            if !error_out.is_null() {
                *error_out = CString::new(format!("Invalid peer_id: {:?}", e))
                    .unwrap().into_raw();
            }
            return P2PErrorCode::InvalidArgument;
        }
    };

    let message = match unsafe_cstr_to_string(message) {
        Ok(msg) if !msg.is_empty() => msg,
        Ok(_) => {
            if !error_out.is_null() {
                *error_out = CString::new("Empty message".to_string())
                    .unwrap().into_raw();
            }
            return P2PErrorCode::InvalidArgument;
        }
        Err(e) => {
            if !error_out.is_null() {
                *error_out = CString::new(format!("Invalid message: {:?}", e))
                    .unwrap().into_raw();
            }
            return P2PErrorCode::InvalidArgument;
        }
    };

    // 通过命令通道发送消息
    let (response_tx, response_rx) = tokio::sync::oneshot::channel();
    let command = P2PCommand::SendMessage {
        target_peer_id,
        message,
        response_tx,
    };

    let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
    if let Err(_) = instance.command_tx.send(command) {
        if !error_out.is_null() {
            *error_out = CString::new("Failed to send command".to_string())
                .unwrap().into_raw();
        }
        return P2PErrorCode::SendFailed;
    }
    drop(instance); // 释放锁

    // 等待响应
    let runtime = RUNTIME.as_ref().unwrap();
    let result = runtime.block_on(async {
        response_rx.await
            .map_err(|e| format!("Response error: {:?}", e))
            .and_then(|r| r)
    });

    match result {
        Ok(_) => P2PErrorCode::Success,
        Err(e) => {
            if !error_out.is_null() {
                *error_out = CString::new(e).unwrap().into_raw();
            }
            P2PErrorCode::SendFailed
        }
    }
}

/// 广播消息给多个节点
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_broadcast_message(
    _handle: P2PHandle,
    target_peer_ids: *const *const c_char,
    target_count: size_t,
    message: *const c_char,
    error_out: *mut *mut c_char,
) -> P2PErrorCode {
    if P2P_INSTANCE.is_none() {
        return P2PErrorCode::NotInitialized;
    }

    if target_peer_ids.is_null() || target_count == 0 {
        if !error_out.is_null() {
            *error_out = CString::new("Empty target list".to_string())
                .unwrap().into_raw();
        }
        return P2PErrorCode::InvalidArgument;
    }

    // 解析目标 Peer IDs
    let mut targets = Vec::with_capacity(target_count);
    for i in 0..target_count {
        let peer_id_ptr = *target_peer_ids.add(i);
        match unsafe_cstr_to_string(peer_id_ptr) {
            Ok(id) => targets.push(id),
            Err(e) => {
                if !error_out.is_null() {
                    *error_out = CString::new(format!("Invalid peer_id at index {}: {:?}", i, e))
                        .unwrap().into_raw();
                }
                return P2PErrorCode::InvalidArgument;
            }
        }
    }

    // 解析消息
    let message = match unsafe_cstr_to_string(message) {
        Ok(msg) if !msg.is_empty() => msg,
        Ok(_) => {
            if !error_out.is_null() {
                *error_out = CString::new("Empty message".to_string())
                    .unwrap().into_raw();
            }
            return P2PErrorCode::InvalidArgument;
        }
        Err(e) => {
            if !error_out.is_null() {
                *error_out = CString::new(format!("Invalid message: {:?}", e))
                    .unwrap().into_raw();
            }
            return P2PErrorCode::InvalidArgument;
        }
    };

    // 通过命令通道发送广播命令
    let (response_tx, response_rx) = tokio::sync::oneshot::channel();
    let command = P2PCommand::BroadcastMessage {
        target_peer_ids: targets,
        message,
        response_tx,
    };

    let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
    if let Err(_) = instance.command_tx.send(command) {
        if !error_out.is_null() {
            *error_out = CString::new("Failed to send command".to_string())
                .unwrap().into_raw();
        }
        return P2PErrorCode::SendFailed;
    }
    drop(instance); // 释放锁

    // 等待响应
    let runtime = RUNTIME.as_ref().unwrap();
    let result = runtime.block_on(async {
        response_rx.await
            .map_err(|e| format!("Response error: {:?}", e))
            .and_then(|r| r)
    });

    match result {
        Ok(_) => P2PErrorCode::Success,
        Err(e) => {
            if !error_out.is_null() {
                *error_out = CString::new(e).unwrap().into_raw();
            }
            P2PErrorCode::SendFailed
        }
    }
}

// ============================================================================
// 辅助函数
// ============================================================================

/// 将 C 字符串转换为 Rust String
unsafe fn unsafe_cstr_to_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("Null pointer".to_string());
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map(|s| s.to_string())
        .map_err(|e| e.to_string())
}

/// 将 Rust String 复制到 C 字符串缓冲区
fn string_to_cstr(s: &str, out: *mut c_char, out_len: size_t) {
    if out.is_null() || out_len == 0 {
        return;
    }

    let bytes = s.as_bytes();
    let copy_len = bytes.len().min(out_len - 1);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, out, copy_len);
        *out.add(copy_len) = 0;
    }
}

/// 将 Rust String 转换为 CString
fn string_to_cstring(s: String) -> CString {
    CString::new(s).unwrap_or_else(|_| CString::new("<invalid utf8>").unwrap())
}

// ============================================================================
// 错误信息
// ============================================================================

/// 释放错误信息字符串
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn localp2p_free_error(error: *mut c_char) {
    if !error.is_null() {
        let _ = CString::from_raw(error);
    }
}
