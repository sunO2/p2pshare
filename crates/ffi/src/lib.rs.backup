//! Local P2P FFI 层
//!
//! 提供 C ABI 兼容的接口，供 Flutter/Dart 调用
//!
//! 使用 Stream 模式：Rust 通过 StreamSink 推送事件到 Flutter
//! 这样避免了从 Rust 后台线程直接调用 Dart 回调的问题

#![allow(clippy::missing_safety_doc)]

use std::sync::{Arc, Mutex};
use std::thread;

use once_cell::sync::Lazy;
use tokio::runtime::Runtime;
use mdns::{
    NodeManager, NodeManagerConfig,
    HealthCheckConfig, UserInfo, ChatExtension,
    IdentityManager, P2PManager, P2PManagerConfig, set_log_callback, send_log as mdns_send_log,
};

mod types;
mod error;
pub mod bridge;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

use types::*;

// 导入 UUID 生成器（用于文件 ID 生成）
use uuid::Uuid;

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

/// 全局 Discovery 资源存储（在 init 和 start 之间传递）
struct GlobalDiscoveryResources {
    /// P2P 管理器（新架构）使用 Arc<tokio::sync::Mutex<>> 允许多个地方共享访问
    p2p_manager: Option<Arc<tokio::sync::Mutex<P2PManager>>>,
    /// 命令接收器（用于监控线程）
    command_rx: Option<tokio::sync::mpsc::UnboundedReceiver<P2PCommand>>,
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

    // 设置聊天事件回调
    unsafe {
        mdns::set_chat_event_callback(|from, content| {
            // 清理 JSON 字符串（内联实现）
            let cleaned = content
                .chars()
                .map(|c| match c {
                    '\n' => "\\n".to_string(),
                    '\r' => "\\r".to_string(),
                    '\t' => "\\t".to_string(),
                    '"' => "\\\"".to_string(),
                    '\\' => "\\\\".to_string(),
                    c if c.is_control() => "".to_string(),
                    c => c.to_string(),
                })
                .collect::<String>();

            // 发送聊天消息事件到 Flutter
            let data = format!(
                r#"{{"from":"{}","content":"{}"}}"#,
                from,
                cleaned
            );

            let event = bridge::P2PBridgeEvent {
                event_type: 6, // MessageReceived (Flutter 端定义: 6)
                data,
            };

            send_event_to_stream(event);
        });

        // ⚠️ 设置 mdns crate 的日志回调，将 Rust 日志传递到 Flutter
        mdns::set_log_callback(|level, target, message| {
            // 将 mdns crate 的日志转发到 Flutter
            send_log_to_flutter(level, target, message);
        });
    }

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
        let node_manager_config = NodeManagerConfig::new()
            .with_protocol_version("/localp2p/1.0.0".to_string())
            .with_agent_prefix(Some("localp2p-rust/".to_string()))
            .with_device_name(device_name.clone());

        let node_manager = Arc::new(NodeManager::new(node_manager_config.clone()));

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

        // 🔄 新架构：创建 P2PManager
        tracing::info!("创建 P2PManager（新架构）...");

        // 从证书路径提取目录，作为数据库路径
        let chat_db_path = if !identity_path.is_empty() {
            mdns_send_log("INFO", "ffi", format!("🔍 identity_path 不为空，尝试提取数据库路径: {}", identity_path));
            // 获取证书文件的目录
            if let Some(parent_dir) = std::path::Path::new(&identity_path).parent() {
                let mut db_path = parent_dir.to_path_buf();
                db_path.push("chat.db");
                mdns_send_log("INFO", "ffi", format!("🔍 计算的数据库路径: {:?}", db_path));
                Some(db_path)
            } else {
                mdns_send_log("WARN", "ffi", format!("⚠️ 无法从 identity_path 提取父目录: {}", identity_path));
                None
            }
        } else {
            mdns_send_log("WARN", "ffi", "⚠️ identity_path 为空，数据库将使用默认路径".to_string());
            None
        };

        let mut p2p_manager_config = P2PManagerConfig::new()
            .with_identity(identity.clone().unwrap_or_else(|| libp2p::identity::Keypair::generate_ed25519()))
            .with_node_manager_config(node_manager_config)
            .with_node_manager(node_manager.clone())  // ⚠️ 关键修复：传递共享的 NodeManager
            .with_local_user_info(user_info.clone())
            .with_health_check_config(health_config.clone())
            .with_listen_addresses(listen_addresses.clone());

        // 设置数据库路径（如果有）
        if let Some(db_path) = chat_db_path {
            mdns_send_log("INFO", "ffi", format!("  聊天数据库路径: {:?}", db_path));
            p2p_manager_config = p2p_manager_config.with_chat_db_path(db_path);
        }

        let p2p_manager = match P2PManager::new(p2p_manager_config).await {
            Ok(pm) => {
                tracing::info!("✓ P2PManager 创建成功，Peer ID: {}", pm.local_peer_id());
                pm
            }
            Err(e) => {
                tracing::error!("P2PManager 创建失败: {:?}", e);
                return Err(format!("Failed to create P2PManager: {:?}", e));
            }
        };

        let local_peer_id = p2p_manager.local_peer_id().to_string();

        // 创建命令通道
        let (command_tx, command_rx) = tokio::sync::mpsc::unbounded_channel();

        // 创建实例
        let instance = P2PInstance {
            node_manager,
            local_peer_id: local_peer_id.clone(),
            device_name: device_name.clone(),
            identity: identity_for_instance, // 保存 identity 以保持 Peer ID 稳定
            command_tx,
            discovery_thread: None,
        };

        // 保存到全局变量（只使用新架构）
        unsafe {
            DISCOVERY_RESOURCES = Some(GlobalDiscoveryResources {
                p2p_manager: Some(Arc::new(tokio::sync::Mutex::new(p2p_manager))),
                command_rx: Some(command_rx),
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
///
/// 🔄 新架构：使用 P2PManager 服务分离架构
/// 1. P2PManager.start_all() 启动两个独立服务
/// 2. 监控线程轮询 NodeManager 获取状态变化
/// 3. 状态变化转换为事件发送到 Flutter
pub fn internal_start() -> Result<(), String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;

        // 启动 P2P 服务（服务分离架构）
        if let Some(resources) = DISCOVERY_RESOURCES.as_mut() {
            let node_manager = if let Some(ref instance) = P2P_INSTANCE {
                instance.lock().unwrap().node_manager.clone()
            } else {
                return Err("P2P_INSTANCE not available".to_string());
            };

            let command_rx = resources.command_rx.take();

            // 🔄 使用服务分离架构
            if let Some(ref p2p_manager_arc) = resources.p2p_manager {
                tracing::info!("使用 P2PManager 服务分离架构启动");
                send_log_to_flutter("INFO", "ffi", "使用 P2PManager 服务分离架构启动".to_string());

                // 启动所有服务（MdnsDiscoveryService + ConnectionService）
                let start_result = runtime.block_on(async {
                    let mut pm = p2p_manager_arc.lock().await;
                    pm.start_all().await
                });

                if let Err(e) = start_result {
                    send_log_to_flutter("ERROR", "ffi", format!("启动服务失败: {:?}", e));
                    // 新架构启动失败，直接返回错误
                    tracing::error!("服务分离架构启动失败: {:?}", e);
                    return Err(format!("启动服务失败: {:?}", e));
                }

                send_log_to_flutter("INFO", "ffi", "✓ 服务分离架构启动成功".to_string());

                // ⚠️ 关键：克隆 P2PManager 的 Arc 引用，不消耗所有权
                let p2p_manager = p2p_manager_arc.clone();

                // 启动事件监控线程（轮询 NodeManager）
                if let Some(command_rx) = command_rx {
                    let handle = std::thread::spawn(move || {
                        runtime.block_on(async move {
                            tracing::info!("事件监控线程启动（服务分离架构）");
                            send_log_to_flutter("INFO", "ffi", "事件监控线程启动".to_string());

                            let mut command_rx = command_rx;
                            let node_manager = node_manager;
                            let p2p_manager = p2p_manager;  // 持有 Arc<Mutex<P2PManager>>

                            // 用于跟踪已发现的节点
                            let mut known_nodes: std::collections::HashSet<String> = std::collections::HashSet::new();
                            let mut offline_nodes: std::collections::HashSet<String> = std::collections::HashSet::new();

                            // 🔥 定期状态推送（每 30 秒）
                            let mut status_push_interval = tokio::time::interval(tokio::time::Duration::from_secs(30));

                            // 🔥 定期心跳检测（每 30 秒）
                            let mut heartbeat_interval = tokio::time::interval(tokio::time::Duration::from_secs(30));

                            loop {
                                tokio::select! {
                                    // 处理命令
                                    Some(command) = command_rx.recv() => {
                                        match command {
                                            P2PCommand::SendMessage { target_peer_id, message, response_tx } => {
                                                let send_start = std::time::Instant::now();
                                                tracing::info!("📨 [事件线程] 收到 SendMessage 命令: target={}, message='{}'", target_peer_id, message);

                                                // ⚠️ 使用 P2PManager 发送消息（需要 lock）
                                                let result = {
                                                    let lock_start = std::time::Instant::now();
                                                    tracing::info!("⏱️  [事件线程] 等待 P2PManager lock...");
                                                    let pm = p2p_manager.lock().await;
                                                    tracing::info!("⏱️  [事件线程] 获取 lock 耗时: {:?}", lock_start.elapsed());

                                                    let send_start = std::time::Instant::now();
                                                    let result = pm.send_message(target_peer_id, message).await;
                                                    tracing::info!("⏱️  [事件线程] send_message 耗时: {:?}, 结果: {:?}", send_start.elapsed(), result.is_ok());
                                                    result
                                                };

                                                tracing::info!("⏱️  [事件线程] SendMessage 总耗时: {:?}", send_start.elapsed());
                                                let _ = response_tx.send(result.map(|_| "OK".to_string()).map_err(|e| e.to_string()));
                                            }
                                            P2PCommand::BroadcastMessage { target_peer_ids: _, message: _, response_tx } => {
                                                let _ = response_tx.send(Err("广播消息功能待实现".to_string()));
                                            }
                                            P2PCommand::Ping { response_tx } => {
                                                let _ = response_tx.send(Ok(()));
                                            }
                                            P2PCommand::Stop => {
                                                tracing::info!("收到停止命令");
                                                break;
                                            }
                                        }
                                    }

                                    // 定期检查节点状态变化
                                    _ = tokio::time::sleep(tokio::time::Duration::from_millis(500)) => {
                                        // 获取当前所有节点
                                        let current_nodes = node_manager.list_all_nodes().await;
                                        let current_peer_ids: std::collections::HashSet<String> =
                                            current_nodes.iter().map(|n| n.peer_id.to_string()).collect();

                                        // 用于跟踪节点状态的 HashMap
                                        let mut node_statuses: std::collections::HashMap<String, bool> = std::collections::HashMap::new();

                                        // 检测新节点和状态变化
                                        for node in &current_nodes {
                                            let peer_id = node.peer_id.to_string();
                                            let is_online = node.status.is_online();
                                            node_statuses.insert(peer_id.clone(), is_online);

                                            if !known_nodes.contains(&peer_id) {
                                                // 新节点
                                                known_nodes.insert(peer_id.clone());
                                                offline_nodes.remove(&peer_id);

                                                // 发送发现事件
                                                send_log_to_flutter(
                                                    "INFO",
                                                    "monitor",
                                                    format!("发现节点: {}", peer_id)
                                                );

                                                let event = bridge::P2PEvent {
                                                    event_type: 1, // Discovered
                                                    data: format!(r#"{{"peer_id":"{}","addr":""}}"#, peer_id),
                                                };
                                                send_event_to_stream(event);

                                                // 发送验证事件
                                                let display_name = node.display_name();
                                                send_log_to_flutter(
                                                    "INFO",
                                                    "monitor",
                                                    format!("验证节点: {}", display_name)
                                                );

                                                let event = bridge::P2PEvent {
                                                    event_type: 3, // Verified
                                                    data: format!(r#"{{"peer_id":"{}","display_name":"{}"}}"#, peer_id, display_name),
                                                };
                                                send_event_to_stream(event);

                                                // 🔥 更新 mDNS 发现设备追踪
                                                {
                                                    let mut pm = p2p_manager.lock().await;
                                                    pm.update_discovery_tracking();
                                                }

                                                // 更新最后事件时间
                                                update_last_event_time();
                                            } else {
                                                // 已知节点，检查状态是否变化
                                                if offline_nodes.contains(&peer_id) && is_online {
                                                    // 从离线恢复在线
                                                    offline_nodes.remove(&peer_id);
                                                    send_log_to_flutter(
                                                        "INFO",
                                                        "monitor",
                                                        format!("节点恢复在线: {}", peer_id)
                                                    );

                                                    // 可以发送 NodeOnline 事件（如果需要）
                                                    let event = bridge::P2PEvent {
                                                        event_type: 3, // Verified (复用 Verified 事件表示在线)
                                                        data: format!(r#"{{"peer_id":"{}","display_name":"{}"}}"#, peer_id, node.display_name()),
                                                    };
                                                    send_event_to_stream(event);
                                                }
                                            }
                                        }

                                        // 检测离线节点
                                        // 1. 从已知节点中消失的节点
                                        let offline: Vec<_> = known_nodes.difference(&current_peer_ids).cloned().collect();
                                        for peer_id in offline {
                                            if !offline_nodes.contains(&peer_id) {
                                                offline_nodes.insert(peer_id.clone());

                                                send_log_to_flutter(
                                                    "WARN",
                                                    "monitor",
                                                    format!("节点离线（消失）: {}", peer_id)
                                                );

                                                let event = bridge::P2PEvent {
                                                    event_type: 4, // NodeOffline
                                                    data: format!(r#"{{"peer_id":"{}"}}"#, peer_id),
                                                };
                                                send_event_to_stream(event);
                                            }
                                        }

                                        // 2. 仍在列表中但状态变为离线的节点
                                        for node in &current_nodes {
                                            let peer_id = node.peer_id.to_string();
                                            if !node.status.is_online() && !offline_nodes.contains(&peer_id) {
                                                offline_nodes.insert(peer_id.clone());

                                                send_log_to_flutter(
                                                    "WARN",
                                                    "monitor",
                                                    format!("节点离线（状态变化）: {}", peer_id)
                                                );

                                                let event = bridge::P2PEvent {
                                                    event_type: 4, // NodeOffline
                                                    data: format!(r#"{{"peer_id":"{}","display_name":"{}"}}"#, peer_id, node.display_name()),
                                                };
                                                send_event_to_stream(event);
                                            }
                                        }

                                        // 清理已离线节点（如果需要）
                                        // known_nodes.retain(|id| !offline_nodes.contains(id));
                                    }

                                    // 🔥 定期推送服务状态到 Flutter
                                    _ = status_push_interval.tick() => {
                                        let pm = p2p_manager.lock().await;
                                        pm.send_status_to_flutter();
                                    }

                                    // 🔥 定期心跳检测（验证服务事件循环是否正常）
                                    _ = heartbeat_interval.tick() => {
                                        // 简化版心跳：由于我们已经在事件循环内部，
                                        // 如果这段代码能执行，说明事件循环是响应的
                                        // 我们只需验证能够获取 P2PManager 锁即可
                                        let heartbeat_ok = match tokio::time::timeout(
                                            std::time::Duration::from_secs(5),
                                            p2p_manager.lock()
                                        ).await {
                                            Ok(_) => {
                                                tracing::debug!("💓 服务心跳正常（P2PManager 可访问）");
                                                true
                                            }
                                            Err(_) => {
                                                let error_msg = "P2PManager 锁获取超时（5秒），可能存在死锁".to_string();
                                                tracing::error!("💔 服务心跳异常: {}", error_msg);
                                                send_log_to_flutter("ERROR", "heartbeat", format!("💔 {}", error_msg));
                                                false
                                            }
                                        };

                                        if !heartbeat_ok {
                                            // 🔥 发送服务状态变化事件到 Flutter，更新 UI
                                            let status_json = serde_json::json!({
                                                "service": "Connection",
                                                "name": "Connection Service",
                                                "health": "unhealthy",
                                                "is_running": true,
                                                "message": "P2PManager 锁获取超时，服务可能存在死锁",
                                            });
                                            send_log_to_flutter("SERVICE_STATUS", "heartbeat", status_json.to_string());
                                        }
                                    }
                                }
                            }

                            tracing::info!("事件监控线程结束");
                            send_log_to_flutter("WARN", "ffi", "事件监控线程结束".to_string());
                        });
                    });

                    // 保存线程句柄
                    if let Some(instance) = P2P_INSTANCE.as_mut() {
                        let mut inst = instance.lock().unwrap();
                        inst.discovery_thread = Some(handle);
                    }
                }

                P2P_IS_RUNNING = true;
                send_log_to_flutter("INFO", "ffi", "P2P 服务已启动（服务分离架构）".to_string());
                return Ok(());
            }

            send_log_to_flutter("ERROR", "ffi", "P2P Manager 未初始化".to_string());
            Err("P2P Manager not initialized".to_string())
        } else {
            Err("DISCOVERY_RESOURCES not available".to_string())
        }
    }
}

// ============================================================================
// 内部停止函数
// ============================================================================
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

/// 内部刷新函数（同步版本）
pub fn internal_trigger_refresh_sync() -> Result<(), String> {
    let start = std::time::Instant::now();
    tracing::info!("🔄 [FFI] 开始触发刷新");

    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            return Err("P2P not initialized. Call p2p_init() first.".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        if resources.p2p_manager.is_none() {
            return Err("P2PManager not available. Call p2p_start() first.".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let result = runtime.block_on(async {
            // 获取 p2p_manager 的引用
            let p2p_manager = resources.p2p_manager.as_ref().unwrap();

            // 调用 P2PManager 的 refresh 方法
            match p2p_manager.lock().await.refresh().await {
                Ok(()) => {
                    tracing::info!("✓ [FFI] 刷新成功");
                    send_log_to_flutter("INFO", "ffi", "✅ 刷新成功".to_string());
                    Ok(())
                }
                Err(e) => {
                    tracing::error!("❌ [FFI] 刷新失败: {:?}", e);
                    send_log_to_flutter("ERROR", "ffi", format!("❌ 刷新失败: {:?}", e));
                    Err(format!("刷新失败: {:?}", e))
                }
            }
        });

        tracing::info!("⏱️  [FFI] 刷新总耗时: {:?}", start.elapsed());

        result
    }
}

/// 内部清理函数
pub fn internal_cleanup() {
    unsafe {
        P2P_INSTANCE = None;
        P2P_IS_RUNNING = false;
        RUNTIME = None;
        DISCOVERY_RESOURCES = None;
    }

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

/// 重启 discovery 服务（新架构）- 同步版本（已废弃，保留兼容性）
///
/// ⚠️ 此函数使用 block_on 会导致 UI 卡顿，建议使用 internal_restart_discovery_async 代替
///
/// 用于应用从后台恢复时，如果发现服务已失效，重启它
///
/// 🔄 使用 P2PManager.restart_mdns()，只重启 mDNS 部分，不影响 TCP 连接
pub fn internal_restart_discovery() -> Result<(), String> {
    send_log_to_flutter("WARN", "ffi", "⚠️ 使用同步版本的 restart_discovery 可能导致卡顿，建议使用异步版本".to_string());
    send_log_to_flutter("INFO", "ffi", "开始重启 Discovery 服务（新架构）".to_string());

    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        if let Some(ref resources) = DISCOVERY_RESOURCES {
            if resources.p2p_manager.is_some() {
                send_log_to_flutter("INFO", "ffi", "使用 P2PManager.restart_mdns()".to_string());

                let runtime = RUNTIME.as_ref().ok_or("No runtime")?;

                // 使用 P2PManager 重启 mDNS（不影响连接）
                let result = runtime.block_on(async {
                    let p2p_manager = resources.p2p_manager.as_ref().unwrap();
                    let mut pm = p2p_manager.lock().await;
                    pm.restart_mdns().await
                });

                match result {
                    Ok(()) => {
                        send_log_to_flutter("INFO", "ffi", "✓ mDNS 服务重启成功（TCP 连接保持不变）".to_string());
                        return Ok(());
                    }
                    Err(e) => {
                        send_log_to_flutter("ERROR", "ffi", format!("P2PManager.restart_mdns() 失败: {:?}", e));
                        return Err(format!("重启 mDNS 失败: {:?}", e));
                    }
                }
            }
        }

        Err("P2PManager 未初始化".to_string())
    }
}

/// 重启 discovery 服务（新架构）- 异步版本（推荐）
///
/// 🔄 使用 P2PManager.restart_mdns()，只重启 mDNS 部分，不影响 TCP 连接
///
/// # 优势
/// - 不使用 block_on，避免阻塞 FFI 调用线程
/// - Flutter 端可以使用 async/await，不会卡顿 UI
pub async fn internal_restart_discovery_async() -> Result<(), String> {
    send_log_to_flutter("INFO", "ffi", "🔄 [异步] 开始重启 Discovery 服务".to_string());

    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        if let Some(ref resources) = DISCOVERY_RESOURCES {
            if resources.p2p_manager.is_some() {
                send_log_to_flutter("INFO", "ffi", "使用 P2PManager.restart_mdns()".to_string());

                // 直接在异步上下文中调用，不需要 block_on
                let p2p_manager = resources.p2p_manager.as_ref().unwrap();
                let mut pm = p2p_manager.lock().await;
                match pm.restart_mdns().await {
                    Ok(()) => {
                        send_log_to_flutter("INFO", "ffi", "✓ mDNS 服务重启成功（TCP 连接保持不变）".to_string());
                        Ok(())
                    }
                    Err(e) => {
                        send_log_to_flutter("ERROR", "ffi", format!("P2PManager.restart_mdns() 失败: {:?}", e));
                        Err(format!("重启 mDNS 失败: {:?}", e))
                    }
                }
            } else {
                Err("P2PManager 未初始化".to_string())
            }
        } else {
            Err("DISCOVERY_RESOURCES 不可用".to_string())
        }
    }
}

/// 重启 discovery 服务 - 非阻塞版本（使用 spawn_blocking）
///
/// 🔄 此函数使用 spawn_blocking 在后台线程执行，避免阻塞 FFI 调用线程
/// 立即返回 Ok(())，实际操作在后台进行
///
/// # 适用场景
/// - Flutter 调用时不想等待完成
/// - 不需要知道重启是否成功
pub fn internal_restart_discovery_non_blocking() -> Result<(), String> {
    send_log_to_flutter("INFO", "ffi", "🔄 [非阻塞] 启动后台重启 Discovery 服务".to_string());

    let runtime = unsafe { RUNTIME.as_ref().ok_or("No runtime")? };
    let runtime_handle = runtime.handle();

    // 在后台线程执行，不阻塞 FFI 调用线程
    std::thread::spawn(move || {
        runtime_handle.block_on(async {
            if let Err(e) = internal_restart_discovery_async().await {
                send_log_to_flutter("ERROR", "ffi", format!("后台重启失败: {}", e));
            }
        });
    });

    // 立即返回，不等待完成
    Ok(())
}

/// 发送消息 - 非阻塞版本（使用 spawn_blocking）
///
/// 🔄 此函数使用 spawn_blocking 在后台线程执行，避免阻塞 FFI 调用线程
/// 立即返回 Ok(())，实际操作在后台进行
pub fn internal_send_message_non_blocking(target_peer_id: String, message: String) -> Result<(), String> {
    send_log_to_flutter("INFO", "ffi", format!("📤 [非阻塞] 发送消息给 {}", target_peer_id));

    let runtime = unsafe { RUNTIME.as_ref().ok_or("No runtime")? };
    let runtime_handle = runtime.handle();

    // 在后台线程执行
    std::thread::spawn(move || {
        runtime_handle.block_on(async {
            if let Err(e) = internal_send_message(target_peer_id, message).await {
                send_log_to_flutter("ERROR", "ffi", format!("发送消息失败: {}", e));
            }
        });
    });

    // 立即返回
    Ok(())
}

/// 广播消息 - 非阻塞版本（使用 spawn_blocking）
///
/// 🔄 此函数使用 spawn_blocking 在后台线程执行，避免阻塞 FFI 调用线程
/// 立即返回 Ok(())，实际操作在后台进行
pub fn internal_broadcast_message_non_blocking(target_peer_ids: Vec<String>, message: String) -> Result<(), String> {
    send_log_to_flutter("INFO", "ffi", format!("📡 [非阻塞] 广播消息给 {} 个节点", target_peer_ids.len()));

    let runtime = unsafe { RUNTIME.as_ref().ok_or("No runtime")? };
    let runtime_handle = runtime.handle();

    // 在后台线程执行
    std::thread::spawn(move || {
        runtime_handle.block_on(async {
            if let Err(e) = internal_broadcast_message(target_peer_ids, message).await {
                send_log_to_flutter("ERROR", "ffi", format!("广播消息失败: {}", e));
            }
        });
    });

    // 立即返回
    Ok(())
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
            node_manager.list_all_nodes().await
        });

        // ⭐ 从节点 attributes 中读取用户信息（ConnectionService 已存储）
        Ok(nodes.into_iter().map(|node| {
            let peer_id = node.peer_id.to_string();

            // 提取地址列表
            let addresses: Vec<String> = node.addresses
                .iter()
                .map(|addr| addr.to_string())
                .collect();

            // 提取协议版本
            let protocol_version = node.protocol_version.clone();

            // 尝试从 attributes 中获取用户信息
            let device_name = node.attributes.get("device_name").cloned();
            let nickname = node.attributes.get("nickname").cloned();
            let avatar_url = node.attributes.get("avatar_url").cloned();

            // ⭐ 优先使用连接状态（离线时显示"离线"），否则使用用户自定义状态
            let status = if !node.status.is_online() {
                Some("离线".to_string())
            } else {
                node.attributes.get("status").cloned()
            };

            if let Some(device_name) = device_name {
                // 使用 attributes 中的用户信息
                InternalNodeInfo {
                    peer_id: peer_id.clone(),
                    display_name: nickname.clone().unwrap_or_else(|| device_name.clone()),
                    device_name,
                    nickname,
                    status,
                    avatar_url,
                    addresses,
                    protocol_version,
                }
            } else {
                // 降级：使用基本信息（从 agent_version 解析的 name）
                InternalNodeInfo {
                    peer_id: peer_id.clone(),
                    display_name: node.display_name(),
                    device_name: node.name.clone().unwrap_or_default(),
                    nickname: None,
                    status,
                    avatar_url: None,
                    addresses,
                    protocol_version,
                }
            }
        }).collect())
    }
}

/// 🔥 获取系统状态（同步版本）
pub fn internal_get_system_status_sync() -> Result<bridge::SystemStatusJson, String> {
    use mdns::events::{ServiceHealth, ServiceStatus};

    let start = std::time::Instant::now();
    tracing::info!("📊 [FFI] 获取系统状态");

    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            return Err("P2P not initialized".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        if resources.p2p_manager.is_none() {
            return Err("P2PManager not available".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let result = runtime.block_on(async {
            let p2p_manager = resources.p2p_manager.as_ref().unwrap();
            p2p_manager.lock().await.get_system_status().await
        });

        let system_status = result.map_err(|e| e.to_string())?;

        // 转换为 JSON 格式
        let mdns_service = bridge::ServiceStatusJson {
            name: system_status.mdns_service.name,
            health: match system_status.mdns_service.health {
                ServiceHealth::Healthy => bridge::ServiceHealthJson::Healthy,
                ServiceHealth::Degraded => bridge::ServiceHealthJson::Degraded,
                ServiceHealth::Unhealthy => bridge::ServiceHealthJson::Unhealthy,
            },
            is_running: system_status.mdns_service.is_running,
            message: system_status.mdns_service.message,
        };

        let connection_service = bridge::ServiceStatusJson {
            name: system_status.connection_service.name,
            health: match system_status.connection_service.health {
                ServiceHealth::Healthy => bridge::ServiceHealthJson::Healthy,
                ServiceHealth::Degraded => bridge::ServiceHealthJson::Degraded,
                ServiceHealth::Unhealthy => bridge::ServiceHealthJson::Unhealthy,
            },
            is_running: system_status.connection_service.is_running,
            message: system_status.connection_service.message,
        };

        tracing::info!("✓ [FFI] 系统状态获取成功: mDNS={:?}, Connection={:?}",
            mdns_service.health, connection_service.health);
        tracing::info!("⏱️  [FFI] 获取系统状态耗时: {:?}", start.elapsed());

        Ok(bridge::SystemStatusJson {
            mdns_service,
            connection_service,
            connected_peers: system_status.connected_peers,
            discovered_peers: system_status.discovered_peers,
        })
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

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let node_manager = {
            let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
            instance.node_manager.clone()
        };

        // 从 NodeManager 获取节点信息
        let peer_id_parsed = peer_id.parse::<libp2p::PeerId>()
            .map_err(|e| format!("Invalid peer ID: {}", e))?;

        let node = runtime.block_on(async {
            node_manager.get_node(&peer_id_parsed).await
        });

        if let Some(node) = node {
            // 从 attributes 中读取用户信息
            let device_name = node.attributes.get("device_name").cloned();
            let nickname = node.attributes.get("nickname").cloned();
            let avatar_url = node.attributes.get("avatar_url").cloned();

            // ⭐ 优先使用连接状态（离线时显示"离线"），否则使用用户自定义状态
            let status = if !node.status.is_online() {
                Some("离线".to_string())
            } else {
                node.attributes.get("status").cloned()
            };

            // 提取地址列表
            let addresses: Vec<String> = node.addresses
                .iter()
                .map(|addr| addr.to_string())
                .collect();

            // 提取协议版本
            let protocol_version = node.protocol_version.clone();

            if device_name.is_some() {
                return Ok(Some(bridge::P2PBridgeNodeInfo {
                    peer_id: peer_id.clone(),
                    display_name: nickname.clone().unwrap_or_else(|| device_name.clone().unwrap()),
                    device_name: device_name.unwrap(),
                    nickname,
                    status,
                    avatar_url: avatar_url,
                    addresses,
                    protocol_version,
                }));
            }
        }

        Ok(None)
    }
}

/// 获取所有节点的用户信息
pub async fn internal_list_user_info() -> Result<Vec<bridge::P2PBridgeNodeInfo>, String> {
    // 直接使用 internal_get_nodes 并过滤有用户信息的节点
    let nodes = internal_get_nodes().await?;
    Ok(nodes.into_iter()
        .filter(|n| !n.device_name.is_empty())
        .map(|n| bridge::P2PBridgeNodeInfo {
            peer_id: n.peer_id.clone(),
            display_name: n.display_name.clone(),
            device_name: n.device_name.clone(),
            nickname: n.nickname.clone(),
            status: n.status.clone(),
            avatar_url: n.avatar_url.clone(),
            addresses: n.addresses.clone(),
            protocol_version: n.protocol_version.clone(),
        })
        .collect())
}

// ============================================================================
// 内部消息函数
// ============================================================================

/// 发送消息（同步版本）
fn internal_send_message_sync(target_peer_id: String, message: String) -> Result<(), String> {
    let start = std::time::Instant::now();
    tracing::info!("📤 [FFI] 开始发送消息: target={}, message='{}'", target_peer_id, message);

    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let step1 = start.elapsed();
        tracing::info!("⏱️  [FFI] 创建 oneshot channel: {:?}", step1);

        let (response_tx, response_rx) = tokio::sync::oneshot::channel();
        let command = P2PCommand::SendMessage {
            target_peer_id,
            message,
            response_tx,
        };

        let step2 = start.elapsed();
        tracing::info!("⏱️  [FFI] 获取 P2P_INSTANCE lock...");

        let instance = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();

        let step3 = start.elapsed();
        tracing::info!("⏱️  [FFI] 获取锁成功: {:?}", step3);

        if let Err(_) = instance.command_tx.send(command) {
            return Err("Failed to send command".to_string());
        }
        drop(instance);

        let step4 = start.elapsed();
        tracing::info!("⏱️  [FFI] 命令已发送: {:?}", step4);

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
        let result = runtime.block_on(async {
            tracing::info!("⏱️  [FFI] 等待响应...");
            let recv_start = std::time::Instant::now();
            let result = response_rx.await
                .map_err(|e| format!("Response error: {:?}", e))
                .and_then(|r| r);
            tracing::info!("⏱️  [FFI] 响应收到: {:?}, 结果: {:?}", recv_start.elapsed(), result.is_ok());
            result
        });

        let total = start.elapsed();
        tracing::info!("⏱️  [FFI] 发送消息总耗时: {:?}, 结果: {:?}", total, result.is_ok());

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

/// 检查事件流是否已设置
fn is_event_stream_ready() -> bool {
    if let Ok(sink) = GLOBAL_STREAM_SINK.lock() {
        sink.is_some()
    } else {
        false
    }
}

/// 发送事件到 StreamSink（如果已设置）
fn send_event_to_stream(event: bridge::P2PBridgeEvent) {
    if let Ok(sink) = GLOBAL_STREAM_SINK.lock() {
        if let Some(ref sink) = *sink {
            // 将事件添加到 Stream
            match sink.add(event) {
                Ok(()) => {}
                Err(e) => {
                    // 使用 tracing 记录错误，避免递归调用 send_log_to_flutter
                    tracing::error!("Failed to send event to stream: {:?}", e);
                }
            }
        } else {
            // Sink 为 None，记录但不要频繁记录（使用 tracing 避免递归）
            // 只在非日志事件时记录，避免日志事件本身造成日志洪水
            if event.event_type != 9 {
                tracing::debug!("Event stream sink not ready, event (type={}) will be lost", event.event_type);
            }
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
    // 检查是否是聊天消息
    if message.contains("💬 MESSAGE:from=") {
        // 解析聊天消息
        if let Some(start) = message.find("from=") {
            if let Some(end) = message.find(",content=") {
                let from = &message[start + 5..end];
                let content = &message[end + 8..];

                // 发送聊天消息事件
                let data = format!(
                    r#"{{"from":"{}","content":"{}"}}"#,
                    from,
                    clean_json_string(content)
                );

                let event = bridge::P2PBridgeEvent {
                    event_type: 5, // MessageReceived
                    data,
                };

                send_event_to_stream(event);
                return; // 跳过常规日志处理
            }
        }
    }

    // 清理消息，移除可能导致 JSON 解析错误的字符
    // 1. 替换换行符和制表符
    // 2. 转义引号和反斜杠
    // 3. 移除其他控制字符
    let cleaned = message
        .chars()
        .map(|c| match c {
            '\n' => "\\n".to_string(),
            '\r' => "\\r".to_string(),
            '\t' => "\\t".to_string(),
            '"' => "\\\"".to_string(),
            '\\' => "\\\\".to_string(),
            c if c.is_control() => "".to_string(), // 移除其他控制字符
            c => c.to_string(),
        })
        .collect::<String>();

    let data = format!(
        r#"{{"level":"{}","target":"{}","message":"{}"}}"#,
        level,
        target,
        cleaned
    );

    let event = bridge::P2PBridgeEvent {
        event_type: 9, // Log 事件
        data,
    };

    send_event_to_stream(event);
}

/// 清理 JSON 字符串
fn clean_json_string(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '\n' => "\\n".to_string(),
            '\r' => "\\r".to_string(),
            '\t' => "\\t".to_string(),
            '"' => "\\\"".to_string(),
            '\\' => "\\\\".to_string(),
            c if c.is_control() => "".to_string(),
            c => c.to_string(),
        })
        .collect::<String>()
}

/// 轮询事件（返回所有待处理的事件并清空队列）
/// ⚠️ 已废弃：请使用 Stream 模式代替
pub fn poll_events() -> Vec<bridge::P2PEvent> {
    // Stream 模式下不需要轮询，直接返回空
    Vec::new()
}

// ============================================================================
// 外部 mDNS 发现（Flutter mDNS 辅助）
// ============================================================================

/// 报告外部发现的设备（由 Flutter mDNS 发现）
///
/// 当 Flutter 的 mDNS 辅助服务发现设备时，调用此方法通知 Rust 层
/// Rust 层会像处理正常 mDNS 发现一样，尝试连接到该设备
pub fn internal_report_external_discovery(
    peer_id: String,
    address: String,
) -> Result<(), String> {
    tracing::info!("📡 [FFI] 收到 Flutter mDNS 发现: {} at {}", peer_id, address);
    send_log_to_flutter(
        "INFO",
        "ffi",
        format!("收到 Flutter mDNS 发现: {} at {}", peer_id, address)
    );

    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            return Err("P2P not initialized".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        if resources.p2p_manager.is_none() {
            return Err("P2PManager not available".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;

        // 在运行时中异步处理连接
        runtime.block_on(async {
            let p2p_manager = resources.p2p_manager.as_ref().unwrap();
            let pm_locked = p2p_manager.lock().await;

            // 解析地址
            let addr = address.parse::<libp2p::Multiaddr>()
                .map_err(|e| format!("Invalid address {}: {:?}", address, e))?;

            // 解析 Peer ID
            let peer = peer_id.parse::<libp2p::PeerId>()
                .map_err(|e| format!("Invalid peer ID {}: {:?}", peer_id, e))?;

            tracing::info!("🔗 [FFI] 尝试连接到: {} at {}", peer_id, address);
            send_log_to_flutter(
                "INFO",
                "ffi",
                format!("尝试连接到: {} at {}", peer_id, address)
            );

            // 通过 ConnectionService 触发连接
            if let Some(connection_service) = pm_locked.connection_service() {
                let mut service = connection_service.lock().await;
                service.connect(peer, addr).await;
                Ok(())
            } else {
                Err("ConnectionService not available".to_string())
            }
        })
    }
}

/// 批量报告外部发现的设备
pub fn internal_report_external_discoveries(
    discoveries: Vec<bridge::ExternalDiscovery>,
) -> Result<(), String> {
    tracing::info!("📡 [FFI] 收到 Flutter mDNS 批量发现: {} 个设备", discoveries.len());

    for discovery in discoveries {
        // 逐个报告
        internal_report_external_discovery(discovery.peer_id, discovery.address)?;
    }

    Ok(())
}

/// 报告外部发现的设备离线（由 Flutter mDNS 检测到）
///
/// 当 Flutter 的 mDNS 辅助服务检测到设备离线时，调用此方法通知 Rust 层
/// Rust 层会更新内部设备状态
pub fn internal_report_external_device_lost(
    peer_id: String,
) -> Result<(), String> {
    tracing::info!("📡 [FFI] 收到 Flutter mDNS 设备离线: {}", peer_id);
    send_log_to_flutter(
        "INFO",
        "ffi",
        format!("收到 Flutter mDNS 设备离线: {}", peer_id)
    );

    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            return Err("P2P not initialized".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        if resources.p2p_manager.is_none() {
            return Err("P2PManager not available".to_string());
        }

        let runtime = RUNTIME.as_ref().ok_or("No runtime")?;

        // 在运行时中异步处理离线事件
        runtime.block_on(async {
            let p2p_manager = resources.p2p_manager.as_ref().unwrap();
            let pm_locked = p2p_manager.lock().await;

            // 解析 Peer ID
            let peer = peer_id.parse::<libp2p::PeerId>()
                .map_err(|e| format!("Invalid peer ID {}: {:?}", peer_id, e))?;

            tracing::info!("🔴 [FFI] 设备离线: {}", peer_id);
            send_log_to_flutter(
                "INFO",
                "ffi",
                format!("设备离线: {}", peer_id)
            );

            // 通过 NodeManager 标记节点为离线
            let node_manager = pm_locked.node_manager();
            node_manager.mark_node_offline(&peer, "Flutter mDNS: 设备离线").await;

            tracing::info!("✓ [FFI] 已标记节点为离线: {}", peer_id);
            Ok(())
        })
    }
}

// ============================================================================
// 数据库操作函数（新增）
// ============================================================================

/// 获取所有会话列表
pub async fn internal_get_conversations() -> Result<Vec<types::ConversationJson>, String> {
    tracing::info!("📋 [FFI] internal_get_conversations 被调用");

    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            tracing::error!("❌ [FFI] P2P not initialized");
            return Err("P2P not initialized".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        let p2p_manager_option = resources.p2p_manager.as_ref()
            .ok_or("P2PManager not available. Call p2p_start() first.")?;

        let p2p_manager = p2p_manager_option.lock().await;

        // 获取会话列表
        tracing::info!("📋 [FFI] 调用 get_conversations...");
        let conversations = p2p_manager.get_conversations().await
            .map_err(|e| {
                tracing::error!("❌ [FFI] get_conversations 失败: {}", e);
                format!("Failed to get conversations: {}", e)
            })?;

        tracing::info!("📋 [FFI] 获取到 {} 个会话", conversations.len());

        // 转换为 JSON 格式
        let result: Vec<types::ConversationJson> = conversations.into_iter().map(|c| {
            tracing::info!("📋 [FFI] 会话: peer_id={}, peer_name={:?}, last_message={:?}",
                c.peer_id, c.peer_name, c.last_message);
            types::ConversationJson {
                id: c.id,
                peer_id: c.peer_id,
                peer_name: c.peer_name,
                peer_avatar: c.peer_avatar,
                last_message: c.last_message,
                last_message_type: c.last_message_type,
                last_message_time: c.last_message_time,
                unread_count: c.unread_count,
                is_pinned: c.is_pinned,
                is_muted: c.is_muted,
            }
        }).collect();

        Ok(result)
    }
}

/// 获取指定会话的消息列表（已弃用，请使用 internal_get_messages_by_peer）
#[deprecated(note = "请使用 internal_get_messages_by_peer 代替")]
pub async fn internal_get_messages(
    conversation_id: String,
    limit: i32,
    before_timestamp: Option<i64>,
) -> Result<Vec<types::MessageJson>, String> {
    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            return Err("P2P not initialized".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        let p2p_manager_option = resources.p2p_manager.as_ref()
            .ok_or("P2PManager not available. Call p2p_start() first.")?;

        let p2p_manager = p2p_manager_option.lock().await;

        // 获取消息列表
        let messages = p2p_manager.get_messages(&conversation_id, limit, before_timestamp).await
            .map_err(|e| format!("Failed to get messages: {}", e))?;

        // 转换为 JSON 格式
        let result: Vec<types::MessageJson> = messages.into_iter().map(|m| {
            types::MessageJson {
                id: m.id,
                conversation_id: m.conversation_id,
                sender_peer_id: m.sender_peer_id,
                message_type: m.message_type,
                content: m.content,
                timestamp: m.timestamp,
                reply_to_id: m.reply_to_id,
                status: m.status,
                is_deleted: m.is_deleted,
                is_revoked: m.is_revoked,
            }
        }).collect();

        Ok(result)
    }
}

/// 通过 peer_id 获取消息列表（支持分页）
pub async fn internal_get_messages_by_peer(
    peer_id: String,
    limit: i32,
    before_timestamp: Option<i64>,
) -> Result<Vec<types::MessageJson>, String> {
    tracing::info!("💬 [FFI] internal_get_messages_by_peer 被调用: peer_id={}, limit={:?}, before={:?}",
        peer_id, limit, before_timestamp);

    unsafe {
        if DISCOVERY_RESOURCES.is_none() {
            tracing::error!("❌ [FFI] P2P not initialized");
            return Err("P2P not initialized".to_string());
        }

        let resources = DISCOVERY_RESOURCES.as_ref().unwrap();
        let p2p_manager_option = resources.p2p_manager.as_ref()
            .ok_or("P2PManager not available. Call p2p_start() first.")?;

        let p2p_manager = p2p_manager_option.lock().await;

        // 获取消息列表
        tracing::info!("💬 [FFI] 调用 get_messages_by_peer...");
        let messages = p2p_manager.get_messages_by_peer(&peer_id, limit, before_timestamp).await
            .map_err(|e| {
                tracing::error!("❌ [FFI] get_messages_by_peer 失败: {}", e);
                format!("Failed to get messages: {}", e)
            })?;

        tracing::info!("💬 [FFI] 获取到 {} 条消息", messages.len());

        // 转换为 JSON 格式
        let result: Vec<types::MessageJson> = messages.into_iter().map(|m| {
            tracing::info!("💬 [FFI] 消息: id={}, sender={}, type={}, content={}",
                m.id, m.sender_peer_id, m.message_type,
                m.content.chars().take(50).collect::<String>());
            types::MessageJson {
                id: m.id,
                conversation_id: m.conversation_id,
                sender_peer_id: m.sender_peer_id,
                message_type: m.message_type,
                content: m.content,
                timestamp: m.timestamp,
                reply_to_id: m.reply_to_id,
                status: m.status,
                is_deleted: m.is_deleted,
                is_revoked: m.is_revoked,
            }
        }).collect();

        Ok(result)
    }
}

/// 发送扩展消息（支持多种消息类型）
pub async fn internal_send_message_ex(
    target_peer_id: String,
    message_type: i32,
    content: String,
    extra: Option<String>,
) -> Result<String, String> {
    unsafe {
        if P2P_INSTANCE.is_none() {
            return Err("Not initialized".to_string());
        }

        let (response_tx, response_rx) = tokio::sync::oneshot::channel();

        let command = P2PCommand::SendMessage {
            target_peer_id,
            message: content.clone(),  // 暂时使用简单消息
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

        result
    }
}

/// 标记消息为已读
pub async fn internal_mark_messages_read(
    conversation_id: String,
    message_ids: Vec<String>,
) -> Result<(), String> {
    tracing::info!("标记 {} 条消息为已读 (会话: {})", message_ids.len(), conversation_id);
    // TODO: 实现标记已读功能
    Ok(())
}

/// 删除消息
pub async fn internal_delete_message(message_id: String) -> Result<(), String> {
    tracing::info!("删除消息: {}", message_id);
    // TODO: 实现删除消息功能
    Ok(())
}

/// 撤回消息
pub async fn internal_revoke_message(message_id: String) -> Result<(), String> {
    tracing::info!("撤回消息: {}", message_id);
    // TODO: 实现撤回消息功能
    Ok(())
}

/// 清空聊天记录
pub async fn internal_clear_conversation(conversation_id: String) -> Result<(), String> {
    tracing::info!("清空聊天记录: {}", conversation_id);
    // TODO: 实现清空聊天记录功能
    Ok(())
}

/// 注册文件（发送前调用）
pub async fn internal_register_file(
    file_name: String,
    file_size: i64,
    mime_type: String,
    local_path: String,
) -> Result<String, String> {
    let file_id = uuid::Uuid::new_v4().to_string();
    tracing::info!("注册文件: {} ({}, {} bytes)", file_name, mime_type, file_size);
    // TODO: 实现文件注册到数据库
    Ok(file_id)
}

/// 获取文件元数据
pub async fn internal_get_file_info(file_id: String) -> Result<types::FileInfoJson, String> {
    tracing::info!("获取文件信息: {}", file_id);
    // TODO: 实现从数据库获取文件信息
    Err(format!("文件不存在: {}", file_id))
}
