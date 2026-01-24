use mdns::{
    ManagedDiscovery, NodeManager, NodeManagerConfig, ManagedDiscoveryEvent,
    HealthCheckConfig,
};
use std::sync::Arc;
use std::time::Duration;
use std::env;

fn print_usage(program_name: &str) {
    println!("用法: {} <设备名称>", program_name);
    println!();
    println!("参数:");
    println!("  设备名称    本设备的显示名称");
    println!();
    println!("示例:");
    println!("  {} \"我的电脑\"        # 设置设备名称", program_name);
    println!("  {} \"客厅电视\"        # 设置设备名称", program_name);
    println!("  {} \"卧室NAS\"         # 设置设备名称", program_name);
}

fn get_device_name() -> String {
    let args: Vec<String> = env::args().collect();

    // 检查是否请求帮助
    if args.len() > 1 && (args[1] == "-h" || args[1] == "--help") {
        print_usage(&args[0]);
        std::process::exit(0);
    }

    // 获取设备名称
    if args.len() > 1 {
        args[1].clone()
    } else {
        print_usage(&args[0]);
        std::process::exit(1);
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 初始化日志
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    // 获取设备名称
    let device_name = get_device_name();

    println!("Local P2P mDNS 节点管理示例（带心跳）");
    println!("====================================");
    println!("设备名称: {}", device_name);

    // 创建节点管理器配置
    let config = NodeManagerConfig::new()
        .with_protocol_version("/localp2p/1.0.0".to_string())
        .with_agent_prefix(Some("localp2p-rust/".to_string()))
        .with_device_name(device_name)
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

    // 创建管理式服务发现器
    let listen_addresses = vec![
        "/ip4/0.0.0.0/tcp/0".parse()?,
    ];

    let mut discovery = ManagedDiscovery::new(
        node_manager.clone(),
        listen_addresses,
        health_config,
    ).await?;

    println!("本地 Peer ID: {}", discovery.local_peer_id());
    println!("协议版本: {}", discovery.protocol_version());
    println!("代理版本: {}", discovery.agent_version());
    println!();
    println!("开始扫描局域网内的对等节点...\n");

    // 主循环：处理发现事件
    loop {
        match discovery.run().await? {
            ManagedDiscoveryEvent::Discovered(peer_id, addr) => {
                println!("🔍 发现节点: {} at {}", peer_id, addr);
                println!("   等待 identify 验证...");
            }
            ManagedDiscoveryEvent::Expired(peer_id) => {
                println!("⏰ 节点 mDNS 记录过期: {}", peer_id);
            }
            ManagedDiscoveryEvent::Verified(peer_id) => {
                println!("✅ 节点验证通过");

                // 获取节点详细信息
                if let Some(node) = discovery.node_manager().get_node(&peer_id).await {
                    println!("   显示名称: {}", node.display_name());
                    if let Some(ref name) = node.name {
                        println!("   设备名称: {}", name);
                    }
                    println!("   Peer ID: {}", node.peer_id);
                    println!("   协议版本: {}", node.protocol_version);
                    println!("   代理版本: {}", node.agent_version);
                    println!("   地址: {:?}", node.addresses);
                }

                // 列出所有验证通过的节点
                println!("\n当前验证通过的节点数: {}",
                    discovery.node_manager().node_count().await);
            }
            ManagedDiscoveryEvent::VerificationFailed(peer_id, reason) => {
                println!("❌ 节点验证失败: {}", peer_id);
                println!("   原因: {}", reason);
            }
            ManagedDiscoveryEvent::NodeRecovered(peer_id, rtt) => {
                // 获取节点显示名称
                let display_name = discovery.node_manager()
                    .get_node(&peer_id)
                    .await
                    .map(|n| n.display_name())
                    .unwrap_or_else(|| peer_id.to_string());

                println!("💚 节点 {} 恢复健康 (RTT: {:?})", display_name, rtt);
            }
            ManagedDiscoveryEvent::NodeOffline(peer_id) => {
                // 获取节点显示名称
                let display_name = discovery.node_manager()
                    .get_node(&peer_id)
                    .await
                    .map(|n| n.display_name())
                    .unwrap_or_else(|| peer_id.to_string());

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
