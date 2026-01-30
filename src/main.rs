use mdns::{
    ManagedDiscovery, NodeManager, NodeManagerConfig, ManagedDiscoveryEvent,
    HealthCheckConfig, UserInfo,
};
use std::sync::Arc;
use std::time::Duration;
use std::env;

mod logging;

/// 架构类型
enum Architecture {
    Old,  // 旧架构：ManagedDiscovery（单 Swarm）
    New,  // 新架构：P2PManager（服务分离）
}

/// CLI 参数配置
struct CliArgs {
    device_name: String,
    tui_mode: bool,
    architecture: Architecture,
}

fn print_usage(program_name: &str) {
    println!("用法: {} <设备名称> [选项]", program_name);
    println!();
    println!("参数:");
    println!("  设备名称      本设备的显示名称");
    println!();
    println!("选项:");
    println!("  --tui, -t     启用 TUI 图形界面模式");
    println!("  --arch <类型> 选择架构类型: old（旧架构）或 new（新架构）");
    println!("                默认: old（旧架构）");
    println!("  --help, -h    显示帮助信息");
    println!();
    println!("架构说明:");
    println!("  old (旧架构)  使用 ManagedDiscovery（单 Swarm，集成 mDNS + 连接）");
    println!("  new (新架构)  使用 P2PManager（服务分离，mDNS 和连接独立）");
    println!();
    println!("示例:");
    println!("  {} \"我的电脑\"                    # 控制台模式（旧架构）", program_name);
    println!("  {} \"客厅电视\" --tui               # TUI 模式（旧架构）", program_name);
    println!("  {} \"卧室NAS\" -t --arch new        # TUI 模式（新架构）", program_name);
    println!("  {} \"我的电脑\" --tui --arch=old    # TUI 模式（旧架构，显式指定）", program_name);
}

fn parse_args() -> CliArgs {
    let args: Vec<String> = env::args().collect();

    // 检查是否请求帮助
    if args.iter().any(|a| a == "-h" || a == "--help") {
        print_usage(&args[0]);
        std::process::exit(0);
    }

    // 检查是否启用 TUI 模式
    let tui_mode = args.iter().any(|a| a == "--tui" || a == "-t");

    // 解析架构参数
    let mut architecture = Architecture::Old;  // 默认使用旧架构
    for arg in &args {
        if arg.starts_with("--arch=") {
            let value = arg.split('=').nth(1).unwrap_or("");
            architecture = match value.to_lowercase().as_str() {
                "new" => Architecture::New,
                "old" => Architecture::Old,
                _ => {
                    eprintln!("错误: 未知的架构类型 '{}'", value);
                    eprintln!("支持的架构: old, new");
                    std::process::exit(1);
                }
            };
        } else if arg == "--arch" {
            // 查找下一个参数作为值
            if let Some(pos) = args.iter().position(|a| a == arg) {
                if pos + 1 < args.len() {
                    let value = &args[pos + 1];
                    if !value.starts_with('-') {
                        architecture = match value.to_lowercase().as_str() {
                            "new" => Architecture::New,
                            "old" => Architecture::Old,
                            _ => {
                                eprintln!("错误: 未知的架构类型 '{}'", value);
                                eprintln!("支持的架构: old, new");
                                std::process::exit(1);
                            }
                        };
                    }
                }
            }
        }
    }

    // 获取设备名称（第一个非选项参数）
    let device_name = args
        .iter()
        .skip(1)
        .find(|a| !a.starts_with('-') && *a != "old" && *a != "new")
        .cloned()
        .unwrap_or_else(|| {
        print_usage(&args[0]);
        std::process::exit(1);
    });

    CliArgs {
        device_name,
        tui_mode,
        architecture,
    }
}

/// 运行控制台模式
async fn run_console_mode(device_name: String) -> Result<(), Box<dyn std::error::Error>> {
    println!("Local P2P mDNS 节点管理示例（带用户信息交换）");
    println!("========================================");
    println!("设备名称: {}", device_name);

    // 创建用户信息（包含设备名称）
    let user_info = UserInfo::new(device_name.clone())
        .with_status("在线".to_string());

    // 创建节点管理器配置
    let config = NodeManagerConfig::new()
        .with_protocol_version("/localp2p/1.0.0".to_string())
        .with_agent_prefix(Some("localp2p-rust/".to_string()))
        .with_device_name(device_name.clone())
        .with_node_timeout(Duration::from_secs(300)) // 5分钟超时
        .with_cleanup_interval(Duration::from_secs(60)); // 1分钟清理间隔

    // 创建节点管理器
    let node_manager = Arc::new(NodeManager::new(config));

    // 启动后台清理任务
    let _cleanup_handle = node_manager.clone().spawn_cleanup_task();
    println!("✓ 后台清理任务已启动");

    // 创建健康检查配置
    let health_config = HealthCheckConfig {
        heartbeat_interval: Duration::from_secs(10),
        max_failures: 3,
    };
    println!("✓ 心跳配置: 10秒间隔，3次失败离线");
    println!("  注意：libp2p ping 会自动对所有已连接节点发送周期性心跳");

    // 创建管理式服务发现器（传入用户信息）
    let listen_addresses = vec![
        "/ip4/0.0.0.0/tcp/0".parse()?,
    ];

    let mut discovery: ManagedDiscovery = ManagedDiscovery::new(
        node_manager.clone(),
        listen_addresses,
        health_config,
        user_info.clone(),  // ← 传入用户信息
        None,  // ← 控制台模式不使用持久化密钥对
    ).await?;

    println!("本地 Peer ID: {}", discovery.local_peer_id());
    println!("协议版本: {}", discovery.protocol_version());
    println!("代理版本: {}", discovery.agent_version());
    println!("本地设备名称: {}", user_info.device_name);
    if let Some(ref status) = user_info.status {
        println!("本地状态: {}", status);
    }
    println!();
    println!("开始扫描局域网内的对等节点...\n");

    // 主循环：处理发现事件
    loop {
        match discovery.run().await? {
            ManagedDiscoveryEvent::Discovered(peer_id, addr) => {
                println!("🔍 发现节点: {} at {}", peer_id, addr);
                println!("   等待 identify 验证和用户信息交换...");
            }
            ManagedDiscoveryEvent::Expired(peer_id) => {
                println!("⏰ 节点 mDNS 记录过期: {}", peer_id);
            }
            ManagedDiscoveryEvent::Verified(peer_id) => {
                println!("✅ 节点验证通过");

                // 获取节点详细信息
                if let Some(node) = discovery.node_manager().get_node(&peer_id).await {
                    println!("   Peer ID: {}", node.peer_id);
                    println!("   协议版本: {}", node.protocol_version);
                    println!("   地址: {:?}", node.addresses);
                }
            }
            ManagedDiscoveryEvent::VerificationFailed(peer_id, reason) => {
                println!("❌ 节点验证失败: {}", peer_id);
                println!("   原因: {}", reason);
            }
            ManagedDiscoveryEvent::UserInfoReceived(peer_id, user_info) => {
                // ← 处理用户信息事件
                println!("📝 收到来自 {} 的用户信息", peer_id);
                println!("   显示名称: {}", user_info.display_name());
                println!("   设备名称: {}", user_info.device_name);
                if let Some(ref nickname) = user_info.nickname {
                    println!("   昵称: {}", nickname);
                }
                if let Some(ref avatar_url) = user_info.avatar_url {
                    println!("   头像: {}", avatar_url);
                }
                if let Some(ref status) = user_info.status {
                    println!("   状态: {}", status);
                }

                // 列出所有验证通过的节点
                println!("\n当前验证通过的节点数: {}",
                    discovery.node_manager().node_count().await);
            }
            ManagedDiscoveryEvent::NodeRecovered(peer_id, rtt) => {
                // 优先使用用户信息中的显示名称
                let display_name = match discovery.get_user_info(&peer_id) {
                    Some(info) => info.display_name(),
                    None => {
                        // 从节点管理器获取显示名称
                        match discovery.node_manager().get_node(&peer_id).await {
                            Some(node) => node.display_name(),
                            None => peer_id.to_string(),
                        }
                    }
                };

                println!("💚 节点 {} 恢复健康 (RTT: {:?})", display_name, rtt);
            }
            ManagedDiscoveryEvent::NodeOffline(peer_id) => {
                // 优先使用用户信息中的显示名称
                let display_name = match discovery.get_user_info(&peer_id) {
                    Some(info) => info.display_name(),
                    None => {
                        // 从节点管理器获取显示名称
                        match discovery.node_manager().get_node(&peer_id).await {
                            Some(node) => node.display_name(),
                            None => peer_id.to_string(),
                        }
                    }
                };

                println!("💔 节点 {} 被判定为离线 (连续3次心跳失败)", display_name);
                println!("   该节点已从管理器中自动移除");
                println!("\n当前验证通过的节点数: {}",
                    discovery.node_manager().node_count().await);
            }
        }
    }

    // 清理任务会持续运行
    // _cleanup_handle.abort();
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 解析命令行参数
    let args = parse_args();

    // 初始化日志
    // TUI 模式：只输出到文件（避免干扰 TUI 界面）
    // 控制台模式：输出到文件和控制台
    if args.tui_mode {
        logging::init_logging_with_level(logging::LogLevel::Info)?;
    } else {
        logging::init_logging_with_console(logging::LogLevel::Info)?;
    }

    // 根据参数选择运行模式
    if args.tui_mode {
        // TUI 模式 - 根据架构选择运行方式
        match args.architecture {
            Architecture::New => {
                tracing::info!("使用新架构（P2PManager 服务分离）");
                tui_app::run_tui_new(args.device_name).await?;
            }
            Architecture::Old => {
                tracing::info!("使用旧架构（ManagedDiscovery 单 Swarm）");
                tui_app::run_tui(args.device_name).await?;
            }
        }
    } else {
        // 控制台模式（原有功能）
        run_console_mode(args.device_name).await?;
    }

    Ok(())
}
