//! mDNS 服务发现（使用 mdns-sd crate）
//!
//! mdns-sd 提供完整的 mDNS/DNS-SD 功能：
//! - 服务广播（Responder/Advertisement）
//! - 服务浏览/发现（Browser/Discovery）

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo, Receiver, AsIpAddrs};
use std::collections::HashMap;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use crate::events::DiscoveryEvent;
use crate::send_log;

/// mDNS 服务类型 (DNS-SD)
const SERVICE_TYPE: &str = "_localp2p._tcp.local.";

/// 设备元数据（从发现的服务中提取）
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DeviceMetadata {
    /// 服务名称（通常是 Peer ID）
    pub peer_id: String,

    /// 设备名称
    pub device_name: String,

    /// 协议版本
    pub protocol_version: String,

    /// 监听端口
    pub port: u16,

    /// 监听地址列表
    pub addresses: Vec<String>,

    /// TXT 记录中的其他属性
    #[serde(flatten)]
    pub extra: HashMap<String, String>,
}

/// mDNS 服务发现（独立运行）
pub struct MdnsServiceDiscovery {
    /// mdns-sd ServiceDaemon
    daemon: ServiceDaemon,

    /// 浏览事件接收器
    browse_receiver: Option<Receiver<ServiceEvent>>,

    /// 发现事件发送器
    discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,

    /// 本地 Peer ID
    local_peer_id: String,

    /// 本地设备名称
    device_name: String,

    /// 协议版本
    protocol_version: String,

    /// 发现的设备缓存（用于去重）
    discovered_peers: HashMap<String, (libp2p::PeerId, libp2p::Multiaddr)>,

    /// 已注册的服务名（用于注销）
    registered_service_fullname: Option<String>,
}

/// mDNS 发现错误
#[derive(Debug, thiserror::Error)]
pub enum MdnsDiscoveryError {
    #[error("创建 mDNS daemon 失败: {0}")]
    DaemonFailed(String),

    #[error("注册服务失败: {0}")]
    RegistrationFailed(String),

    #[error("浏览服务失败: {0}")]
    BrowseFailed(String),

    #[error("发送事件失败")]
    SendFailed,
}

impl MdnsServiceDiscovery {
    /// 创建新的 mDNS 服务发现
    pub async fn new(
        local_peer_id: String,
        device_name: String,
        protocol_version: String,
        discovery_tx: mpsc::UnboundedSender<DiscoveryEvent>,
    ) -> Result<Self, MdnsDiscoveryError> {
        tracing::info!("🔍 初始化 mdns-sd 服务发现...");
        send_log("INFO", "mdns_discovery", "🔍 正在初始化 mdns-sd 服务发现...".to_string());

        // 创建 ServiceDaemon
        let daemon = ServiceDaemon::new()
            .map_err(|e| MdnsDiscoveryError::DaemonFailed(format!("创建 daemon 失败: {}", e)))?;

        send_log("INFO", "mdns_discovery", "✅ mdns-sd ServiceDaemon 创建成功".to_string());

        Ok(Self {
            daemon,
            browse_receiver: None,
            discovery_tx,
            local_peer_id,
            device_name,
            protocol_version,
            discovered_peers: HashMap::new(),
            registered_service_fullname: None,
        })
    }

    /// 注册服务（广播自己的存在）
    pub fn register_service(
        &mut self,
        port: u16,
        addresses: Vec<String>,
        extra_metadata: HashMap<String, String>,
    ) -> Result<(), MdnsDiscoveryError> {
        tracing::info!("📡 注册 mDNS 服务: {}@{}", self.local_peer_id, port);
        send_log("INFO", "mdns_discovery", format!("📡 注册 mDNS 服务: {}@{}", self.local_peer_id, port));

        // 构建属性（TXT 记录）
        let mut properties = vec![
            ("peer_id".to_string(), self.local_peer_id.clone()),
            ("device_name".to_string(), self.device_name.clone()),
            ("protocol_version".to_string(), self.protocol_version.clone()),
            ("port".to_string(), port.to_string()),
        ];

        // 添加地址信息
        for addr in &addresses {
            properties.push(("addr".to_string(), addr.clone()));
        }

        // 添加额外的属性
        for (key, value) in extra_metadata {
            properties.push((key, value));
        }

        // 获取第一个 IP 地址作为 host_ipv4
        let host_ip = addresses.first()
            .cloned()
            .unwrap_or_else(|| "127.0.0.1".to_string());

        // 使用 peer_id 作为实例名
        let instance_name = self.local_peer_id.as_str();
        let host_name = format!("{}.local.", host_ip);
        let host_name_str = host_name.as_str();
        let host_ip_str = host_ip.as_str();

        // 创建 ServiceInfo
        let service_info = ServiceInfo::new(
            SERVICE_TYPE,
            instance_name,
            host_name_str,
            host_ip_str,
            port,
            &properties[..],
        ).map_err(|e| MdnsDiscoveryError::RegistrationFailed(format!("创建 ServiceInfo 失败: {}", e)))?;

        // 注册服务
        let fullname = service_info.get_fullname().to_string();
        self.daemon.register(service_info)
            .map_err(|e| MdnsDiscoveryError::RegistrationFailed(format!("注册失败: {}", e)))?;

        self.registered_service_fullname = Some(fullname.clone());

        tracing::info!("✅ mDNS 服务注册成功: {}", fullname);
        send_log("INFO", "mdns_discovery", "✅ mDNS 服务注册成功".to_string());

        Ok(())
    }

    /// 启动服务（返回任务句柄）
    pub fn spawn(mut self) -> JoinHandle<()> {
        tokio::spawn(async move {
            tracing::info!("🚀 mdns-sd 服务发现已启动");
            send_log("INFO", "mdns_discovery", "🚀 mdns-sd 服务发现已启动".to_string());

            // 开始浏览服务
            let service_type = SERVICE_TYPE;
            tracing::info!("🔍 开始浏览服务: {}", service_type);
            send_log("INFO", "mdns_discovery", format!("🔍 开始浏览服务: {}", service_type));

            let browse_receiver = match self.daemon.browse(service_type) {
                Ok(receiver) => {
                    send_log("INFO", "mdns_discovery", "✅ ServiceBrowser 创建成功".to_string());
                    receiver
                }
                Err(e) => {
                    tracing::error!("创建 browser 失败: {}", e);
                    send_log("ERROR", "mdns_discovery", format!("❌ 创建 browser 失败: {}", e));
                    return;
                }
            };

            self.browse_receiver = Some(browse_receiver);

            // 持续处理浏览事件
            loop {
                if let Some(ref receiver) = self.browse_receiver {
                    match receiver.recv() {
                        Ok(event) => {
                            self.process_service_event(&event);
                        }
                        Err(e) => {
                            tracing::warn!("接收 mDNS 事件失败: {}", e);
                        }
                    }
                }

                // 短暂等待
                tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
            }
        })
    }

    /// 处理 mDNS 服务事件
    fn process_service_event(&mut self, event: &ServiceEvent) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                tracing::info!("🔍 解析服务: {}", info.get_fullname());

                // 从实例名中提取 peer_id
                // 格式：peer_id._localp2p._tcp.local
                let fullname = info.get_fullname();
                let peer_id_str = fullname
                    .trim_end_matches(SERVICE_TYPE)
                    .trim_end_matches('.')
                    .to_string();

                // 跳过自己
                if peer_id_str == self.local_peer_id {
                    return;
                }

                // 获取地址和端口
                let port = info.get_port();
                let addresses = info.get_addresses();

                tracing::info!("📡 发现服务: {} at {:?}", peer_id_str, addresses);

                // 创建 Multiaddr 并发送发现事件
                for scoped_ip in addresses {
                    // 将 ScopedIp 转换为 SocketAddr
                    let ip_addr = scoped_ip.to_ip_addr();
                    let socket_addr = std::net::SocketAddr::new(ip_addr, port);

                    let multiaddr = self.socket_addr_to_multiaddr(&socket_addr, port);
                    if let Ok(multiaddr) = multiaddr {
                        let peer_id = peer_id_str.parse().unwrap_or_else(|_| {
                            use libp2p::PeerId;
                            PeerId::random()
                        });

                        // 检查是否已发现过
                        let peer_key = peer_id.to_string();
                        if !self.discovered_peers.contains_key(&peer_key) {
                            self.discovered_peers.insert(peer_key.clone(), (peer_id, multiaddr.clone()));

                            tracing::info!("✅ 发现设备: {} at {}", peer_id_str, multiaddr);
                            send_log("INFO", "mdns_discovery", format!("✅ 发现设备: {} at {}", peer_id_str, multiaddr));

                            // 发送发现事件
                            if let Err(_) = self.discovery_tx.send(DiscoveryEvent::Discovered {
                                peer_id,
                                addr: multiaddr,
                            }) {
                                tracing::warn!("发送发现事件失败");
                                send_log("WARN", "mdns_discovery", "⚠️ 发送发现事件失败".to_string());
                            } else {
                                send_log("INFO", "mdns_discovery", "📨 已发送发现事件到连接服务".to_string());
                            }
                        }
                    }
                }
            }
            ServiceEvent::ServiceRemoved(fullname, _ty) => {
                tracing::info!("🗑️ 服务已移除: {}", fullname);
                // 可以从缓存中移除该节点
            }
            _ => {
                tracing::trace!("收到其他 mDNS 事件: {:?}", event);
            }
        }
    }

    /// 将 SocketAddr 转换为 Multiaddr
    fn socket_addr_to_multiaddr(&self, addr: &std::net::SocketAddr, port: u16) -> Result<libp2p::Multiaddr, String> {
        use libp2p::Multiaddr;

        match addr.ip() {
            std::net::IpAddr::V4(ipv4) => {
                let multiaddr_str = format!("/ip4/{}/tcp/{}", ipv4, port);
                multiaddr_str.parse().map_err(|_| format!("无效的地址: {}", multiaddr_str))
            }
            std::net::IpAddr::V6(ipv6) => {
                let multiaddr_str = format!("/ip6/{}/tcp/{}", ipv6, port);
                multiaddr_str.parse().map_err(|_| format!("无效的地址: {}", multiaddr_str))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mdns_discovery_creation() {
        let (tx, _rx) = mpsc::unbounded_channel();
        let result = MdnsServiceDiscovery::new(
            "test_peer_id".to_string(),
            "test_device".to_string(),
            "1.0.0".to_string(),
            tx,
        ).await;

        // mdns-sd 应该能正常创建
        assert!(result.is_ok());
    }
}
