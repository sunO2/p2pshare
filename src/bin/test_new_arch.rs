//! 测试新架构（P2PManager）的简单程序
//!
//! 用法: cargo run --bin test_new_arch -- 节点名称

use mdns::{
    P2PManager, P2PManagerConfig, NodeManager, NodeManagerConfig,
    HealthCheckConfig, UserInfo,
};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;
use libp2p::identity::Keypair;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 初始化日志
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

    let args: Vec<String> = std::env::args().collect();
    let device_name = args.get(1).cloned().unwrap_or_else(|| "测试节点".to_string());

    println!("╔═══════════════════════════════════════════════════════════════════════════════");
    println!("║ 🧪 [新架构测试] 测试 P2PManager（服务分离）");
    println!("╚═══════════════════════════════════════════════════════════════════════════════");
    println!("设备名称: {}", device_name);

    // 步骤 1: 创建身份
    tracing::info!("📝 [步骤 1/5] 生成临时密钥对...");
    let identity = Keypair::generate_ed25519();
    let peer_id = identity.public().to_peer_id();
    tracing::info!("✓ Peer ID: {}", peer_id);

    // 步骤 2: 创建用户信息
    tracing::info!("📝 [步骤 2/5] 创建用户信息...");
    let user_info = UserInfo::new(device_name.clone())
        .with_status("在线".to_string());
    tracing::info!("✓ 用户信息创建成功");

    // 步骤 3: 创建节点管理器配置
    tracing::info!("📝 [步骤 3/5] 创建节点管理器配置...");
    let node_manager_config = NodeManagerConfig::new()
        .with_protocol_version("/localp2p/1.0.0".to_string())
        .with_agent_prefix(Some("localp2p-rust/".to_string()))
        .with_device_name(device_name.clone());

    // 步骤 4: 创建节点管理器
    tracing::info!("📝 [步骤 4/5] 创建节点管理器...");
    let node_manager = Arc::new(NodeManager::new(node_manager_config.clone()));
    tracing::info!("✓ 节点管理器创建成功");

    // 启动后台清理任务
    node_manager.clone().spawn_cleanup_task();

    // 步骤 5: 创建健康检查配置
    tracing::info!("📝 [步骤 5/5] 创建健康检查配置...");
    let health_config = HealthCheckConfig {
        heartbeat_interval: Duration::from_secs(10),
        max_failures: 3,
    };

    // 创建 P2PManager 配置
    tracing::info!("📝 [P2PManager] 创建 P2PManager 配置...");
    let p2p_config = P2PManagerConfig::new()
        .with_identity(identity.clone())
        .with_node_manager_config(node_manager_config)
        .with_node_manager(node_manager.clone())
        .with_local_user_info(user_info)
        .with_health_check_config(health_config)
        .with_listen_addresses(vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()]);

    // 创建 P2PManager
    tracing::info!("📝 [P2PManager] 创建 P2PManager...");
    let mut p2p_manager = P2PManager::new(p2p_config).await?;
    tracing::info!("✓ P2PManager 创建成功");

    // 启动所有服务
    tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
    tracing::info!("║ 🚀 [服务启动] 启动所有服务");
    tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");
    p2p_manager.start_all().await?;
    tracing::info!("✓ 所有服务启动成功");

    println!("✓ 服务已启动，运行 60 秒...");
    println!("  请在另一个终端运行相同的程序来测试发现");

    // 运行 60 秒
    for i in 1..=60 {
        sleep(Duration::from_secs(1)).await;
        if i % 10 == 0 {
            let nodes = node_manager.list_all_nodes().await;
            println!("[{} 秒] 当前发现节点数: {}", i, nodes.len());
            for node in &nodes {
                println!("  - {} ({})", node.display_name(), node.peer_id);
            }
        }
    }

    println!("测试完成");

    Ok(())
}
