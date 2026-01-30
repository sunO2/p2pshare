//! mDNS 服务发现集成测试
//!
//! 测试 mdns-sd 的广播和发现功能

use std::time::Duration;
use tokio::time::sleep;

#[tokio::test]
async fn test_mdns_broadcast_and_discovery() {
    // 创建两个服务发现实例来模拟两个设备

    // 设备 1
    let (tx1, _rx1) = tokio::sync::mpsc::unbounded_channel();
    let peer_id1 = "12D3KooWTestDevice1".to_string();
    let mut discovery1 = mdns::mdns_discovery::MdnsServiceDiscovery::new(
        peer_id1.clone(),
        "测试设备1".to_string(),
        "1.0.0".to_string(),
        tx1,
    ).await.unwrap();

    // 注册设备 1 的服务
    let addresses1 = vec!["127.0.0.1".to_string()];
    discovery1.register_service(12345, addresses1, std::collections::HashMap::new()).unwrap();

    // 启动设备 1 的浏览任务
    let _task1 = discovery1.spawn();

    println!("✅ 设备 1 ({}) 已启动并广播服务", peer_id1);

    // 等待 mDNS 广播生效
    sleep(Duration::from_secs(1)).await;

    // 设备 2
    let (tx2, mut rx2) = tokio::sync::mpsc::unbounded_channel();
    let peer_id2 = "12D3KooWTestDevice2".to_string();
    let mut discovery2 = mdns::mdns_discovery::MdnsServiceDiscovery::new(
        peer_id2,
        "测试设备2".to_string(),
        "1.0.0".to_string(),
        tx2,
    ).await.unwrap();

    // 注册设备 2 的服务
    let addresses2 = vec!["127.0.0.1".to_string()];
    discovery2.register_service(12346, addresses2, std::collections::HashMap::new()).unwrap();

    // 启动设备 2 的浏览任务
    let _task2 = discovery2.spawn();

    println!("✅ 设备 2 已启动并广播服务");

    // 检查设备 2 是否发现了任何设备（排除自己）
    let mut discovered_count = 0;
    let mut discovered_device1 = false;
    let timeout = sleep(Duration::from_secs(5));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            event = rx2.recv() => {
                if let Some(mdns::events::DiscoveryEvent::Discovered { peer_id, addr }) = event {
                    println!("📡 设备 2 发现了设备: {} at {}", peer_id, addr);
                    discovered_count += 1;

                    // 检查是否发现了设备 1（通过端口号判断）
                    if addr.to_string().contains("12345") {
                        discovered_device1 = true;
                        println!("✅ 确认发现了设备 1 (端口 12345)");
                        break;
                    }
                }
            }
            _ = &mut timeout => {
                println!("⏱️ 超时或发现完成，共发现 {} 个设备", discovered_count);
                break;
            }
        }
    }

    // 验证至少发现了一个设备
    assert!(discovered_count > 0, "设备 2 应该至少发现一个设备");
    assert!(discovered_device1, "设备 2 应该发现设备 1 (端口 12345)");
    println!("✅ 集成测试通过: mDNS 广播和发现功能正常工作");
    println!("   - 设备 2 共发现 {} 个设备", discovered_count);
}
