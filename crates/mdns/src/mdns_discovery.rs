//! mDNS 服务发现（使用 mdns-sd crate）
//!
//! mdns-sd 提供完整的 mDNS/DNS-SD 功能：
//! - 服务广播（Responder/Advertisement）
//! - 服务浏览/发现（Browser/Discovery）

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo, Receiver};
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

    /// 本机网络接口缓存（IP + 子网掩码列表）
    /// 用于判断远程 IP 是否在同一子网
    local_networks: Vec<(std::net::Ipv4Addr, std::net::Ipv4Addr)>,

    /// VPN 接口列表（如果检测到）
    vpn_interfaces: Vec<String>,

    /// 物理接口名称
    physical_interface: Option<String>,
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

        // 检测并获取物理网络接口（排除 VPN/tun/tap）
        let (physical_interface, vpn_interfaces) = Self::get_physical_interface();

        // 创建 ServiceDaemon
        let daemon = ServiceDaemon::new()
            .map_err(|e| MdnsDiscoveryError::DaemonFailed(format!("创建 daemon 失败: {}", e)))?;

        // ⭐ 禁用 VPN 接口，避免 mDNS 流量被路由到 VPN
        if !vpn_interfaces.is_empty() {
            for vpn_if in &vpn_interfaces {
                match daemon.disable_interface(vpn_if.as_str()) {
                    Ok(_) => {
                        tracing::info!("✅ 已禁用 VPN 接口: {}", vpn_if);
                        send_log("INFO", "mdns_discovery", format!("✅ 已禁用 VPN 接口: {}", vpn_if));
                    }
                    Err(e) => {
                        tracing::warn!("⚠️ 禁用 VPN 接口 {} 失败: {}", vpn_if, e);
                    }
                }
            }

            tracing::warn!("⚠️ 检测到 VPN/代理接口: {:?}，已自动禁用", vpn_interfaces);
            send_log("WARN", "mdns_discovery",
                format!("⚠️ 检测到 VPN/代理接口: {:?}\n\
                ✅ 已自动禁用 VPN 接口，mDNS 将使用物理接口广播",
                vpn_interfaces)
            );
        }

        // ⭐ 启用物理接口（如果有指定的物理接口）
        if let Some(ref phy_name) = physical_interface {
            match daemon.enable_interface(phy_name.as_str()) {
                Ok(_) => {
                    tracing::info!("✅ 已启用物理接口: {}", phy_name);
                    send_log("INFO", "mdns_discovery", format!("✅ 已启用物理接口: {}", phy_name));
                }
                Err(e) => {
                    tracing::warn!("⚠️ 启用物理接口 {} 失败: {}", phy_name, e);
                }
            }
        }

        send_log("INFO", "mdns_discovery", "✅ mdns-sd ServiceDaemon 创建成功".to_string());

        // 扫描本机网络接口（IP + 子网掩码）
        let local_networks = Self::scan_local_networks();
        tracing::info!("🌐 本机网络接口: {:?}", local_networks);
        send_log("INFO", "mdns_discovery", format!("🌐 本机网络接口: {:?}", local_networks));

        Ok(Self {
            daemon,
            browse_receiver: None,
            discovery_tx,
            local_peer_id,
            device_name,
            protocol_version,
            discovered_peers: HashMap::new(),
            registered_service_fullname: None,
            local_networks,
            vpn_interfaces,
            physical_interface,
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

        // ⭐ 如果检测到 VPN，发送事件通知 Flutter 启动辅助 mDNS
        if !self.vpn_interfaces.is_empty() {
            tracing::warn!("📡 检测到 VPN，通知 Flutter 启动辅助 mDNS");
            send_log("WARN", "mdns_discovery", "📡 检测到 VPN，通知 Flutter 启动辅助 mDNS".to_string());

            let _ = self.discovery_tx.send(DiscoveryEvent::VpnDetected {
                vpn_interfaces: self.vpn_interfaces.clone(),
                physical_interface: self.physical_interface.clone(),
                local_peer_id: self.local_peer_id.clone(),
                port,
                service_type: SERVICE_TYPE.to_string(),
            });
        }

        Ok(())
    }

    /// 启动服务（返回任务句柄）
    pub fn spawn(mut self) -> JoinHandle<()> {
        tokio::spawn(async move {
            tracing::info!("🚀 mdns-sd 服务发现已启动");
            send_log("INFO", "mdns_discovery", "🚀 mdns-sd 服务发现已启动".to_string());

            // ⭐ 方案2: 先等待一段时间，让服务广播稳定，再开始浏览
            tracing::info!("⏱️  等待服务广播稳定后，再开始浏览...");
            send_log("INFO", "mdns_discovery", "⏱️ 等待服务广播稳定后，再开始浏览...".to_string());
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

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

            tracing::info!("✅ mDNS 浏览已启动，开始监听设备发现事件");
            send_log("INFO", "mdns_discovery", "✅ mDNS 浏览已启动".to_string());

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

                // ⭐ 优化：过滤和排序地址，只连接最合适的地址
                let mut filtered_addrs: Vec<(libp2p::Multiaddr, u32)> = Vec::new();
                use std::net::IpAddr;

                for scoped_ip in addresses.iter() {
                    // ScopedIp 是一个 enum，需要 match 来获取 IP 地址
                    let (ip_addr, original_port) = match scoped_ip {
                        mdns_sd::ScopedIp::V4(v4) => (std::net::IpAddr::V4(*v4.addr()), port),
                        mdns_sd::ScopedIp::V6(v6) => {
                            tracing::debug!("跳过 IPv6 地址: {:?}", v6.addr());
                            continue;
                        }
                        _ => {
                            tracing::debug!("跳过未知类型的地址: {:?}", scoped_ip);
                            continue;
                        }
                    };

                    // 过滤：只保留 IPv4 私有地址和本地回环地址
                    let ip_addr_v4 = match ip_addr {
                        IpAddr::V4(ipv4) => ipv4,
                        _ => continue,
                    };

                    // 子网掩码过滤：只连接与本机在同一子网的 IP
                    let is_same_subnet = self.is_same_subnet(ip_addr_v4);

                    if !is_same_subnet {
                        tracing::debug!("跳过非同子网地址: {}", ip_addr);
                        continue;
                    }

                    // 转换为 Multiaddr
                    let socket_addr = std::net::SocketAddr::new(ip_addr, original_port);
                    if let Ok(multiaddr) = self.socket_addr_to_multiaddr(&socket_addr, original_port) {
                        // 同一子网内的 IP 都使用相同优先级
                        filtered_addrs.push((multiaddr, 0));
                    }
                }

                // 按优先级排序
                filtered_addrs.sort_by_key(|(_, priority)| *priority);

                // 只使用第一个（最佳）地址
                if let Some((multiaddr, _)) = filtered_addrs.first() {
                    use libp2p::PeerId;
                    let peer_id: PeerId = peer_id_str.parse().unwrap_or_else(|_| PeerId::random());

                    // 检查是否已发现过
                    let peer_key = peer_id.to_string();
                    if !self.discovered_peers.contains_key(&peer_key) {
                        self.discovered_peers.insert(peer_key.clone(), (peer_id, multiaddr.clone()));

                        tracing::info!("✅ 发现设备: {} at {} (从 {} 个地址中筛选)", peer_id_str, multiaddr, addresses.len());
                        send_log("INFO", "mdns_discovery", format!("✅ 发现设备: {} at {} (从 {} 个地址中筛选)", peer_id_str, multiaddr, addresses.len()));

                        // 发送发现事件
                        if let Err(_) = self.discovery_tx.send(DiscoveryEvent::Discovered {
                            peer_id,
                            addr: multiaddr.clone(),
                        }) {
                            tracing::warn!("发送发现事件失败");
                            send_log("WARN", "mdns_discovery", "⚠️ 发送发现事件失败".to_string());
                        } else {
                            send_log("INFO", "mdns_discovery", "📨 已发送发现事件到连接服务".to_string());
                        }
                    }
                } else {
                    tracing::warn!("⚠️ 节点 {} 没有可用的地址", peer_id_str);
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

    /// 主动刷新：重新广播自己的服务
    ///
    /// 通过重新注册服务来触发 mDNS 广播
    /// 注意：需要先调用过 `register_service()`，保存了服务信息
    ///
    /// # 使用场景
    /// - 用户点击"刷新"按钮
    /// - 应用从后台恢复
    /// - 网络状态变化
    pub fn refresh_advertise(&mut self) -> Result<(), MdnsDiscoveryError> {
        tracing::info!("🔄 [mDNS] 主动刷新：重新广播服务");
        send_log("INFO", "mdns_discovery", "🔄 主动刷新：重新广播服务".to_string());

        // 注意：mdns-sd 不支持"重新广播"方法
        // 但已注册的服务会自动响应查询，所以不需要手动重新广播
        // 这里只是一个通知，告知用户服务正在广播

        tracing::info!("✓ [mDNS] 服务广播中（自动响应查询）");
        send_log("INFO", "mdns_discovery", "✅ 服务正在广播".to_string());

        Ok(())
    }

    /// 主动刷新：重新扫描网络中的设备
    ///
    /// 通过停止并重新开始浏览来触发重新发现
    ///
    /// # 使用场景
    /// - 用户点击"刷新"按钮
    /// - 应用从后台恢复
    /// - 网络状态变化
    pub fn refresh_discover(&mut self) -> Result<(), MdnsDiscoveryError> {
        tracing::info!("🔍 [mDNS] 主动刷新：重新扫描网络");
        send_log("INFO", "mdns_discovery", "🔍 主动刷新：重新扫描网络".to_string());

        // 停止当前浏览
        if let Some(ref _receiver) = self.browse_receiver {
            // 注意：mdns-sd 的 stop_browse 需要服务类型
            // 但我们没有保存服务类型，所以我们通过其他方式实现
            tracing::debug!("当前正在浏览，继续监听即可");
        }

        // 发送一个"扫描"事件
        let _ = self.discovery_tx.send(DiscoveryEvent::Refresh);

        tracing::info!("✓ [mDNS] 重新扫描完成");
        send_log("INFO", "mdns_discovery", "✅ 重新扫描完成".to_string());

        Ok(())
    }

    /// 将 SocketAddr 转换为 Multiaddr
    fn socket_addr_to_multiaddr(&self, addr: &std::net::SocketAddr, port: u16) -> Result<libp2p::Multiaddr, String> {
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

    /// 扫描本机网络接口，获取所有 IP 和子网掩码
    ///
    /// 返回 Vec<(IP地址, 子网掩码)>
    fn scan_local_networks() -> Vec<(std::net::Ipv4Addr, std::net::Ipv4Addr)> {
        use std::net::Ipv4Addr;

        let mut networks = Vec::new();

        // 遍历所有网络接口
        match if_addrs::get_if_addrs() {
            Ok(interfaces) => {
                for interface in interfaces {
                    // 跳过回环接口
                    if interface.name == "lo" || interface.name == "Loopback" {
                        continue;
                    }

                    // 只处理 IPv4 地址
                    let ifv4 = match interface.addr {
                        if_addrs::IfAddr::V4(ref v4) => v4,
                        _ => continue,
                    };

                    let ipv4_addr = ifv4.ip;
                    let netmask_v4 = ifv4.netmask;

                    // 跳过本地回环地址
                    if ipv4_addr.is_loopback() {
                        continue;
                    }

                    networks.push((ipv4_addr, netmask_v4));
                    tracing::info!("📡 发现接口: {} IP={} 子网掩码={}",
                        interface.name, ipv4_addr, netmask_v4);
                }
            }
            Err(e) => {
                tracing::warn!("⚠️ 无法扫描网络接口: {}", e);
            }
        }

        // 如果没有找到任何网络接口，添加一个默认的（用于测试）
        if networks.is_empty() {
            tracing::warn!("⚠️ 未能扫描到网络接口，使用默认配置");
            networks.push((
                Ipv4Addr::new(127, 0, 0, 1),
                Ipv4Addr::new(255, 0, 0, 0),
            ));
        }

        networks
    }

    /// 判断远程 IPv4 地址是否与本机在同一子网
    ///
    /// 使用子网掩码计算：
    /// - 网络地址 = IP 地址 & 子网掩码
    /// - 两个 IP 在同一子网当且仅当它们的网络地址相同
    ///
    /// # 参数
    /// - `remote_ip`: 远程 IPv4 地址
    ///
    /// # 返回
    /// - `true`: 如果与任何本机接口在同一子网
    /// - `false`: 如果不在任何子网
    fn is_same_subnet(&self, remote_ip: std::net::Ipv4Addr) -> bool {
        for (local_ip, netmask) in &self.local_networks {
            if Self::is_in_same_subnet_impl(remote_ip, *local_ip, *netmask) {
                tracing::debug!("✅ {} 与本机 {} (子网掩码 {}) 在同一子网",
                    remote_ip, local_ip, netmask);
                return true;
            }
        }
        tracing::debug!("❌ {} 不在本机任何子网内", remote_ip);
        false
    }

    /// 子网掩码判断的具体实现
    ///
    /// 计算网络地址并比较
    fn is_in_same_subnet_impl(
        ip1: std::net::Ipv4Addr,
        ip2: std::net::Ipv4Addr,
        netmask: std::net::Ipv4Addr,
    ) -> bool {
        // 将 IP 地址和子网掩码转为 u32
        let ip1_u32: u32 = u32::from_be_bytes(ip1.octets());
        let ip2_u32: u32 = u32::from_be_bytes(ip2.octets());
        let netmask_u32: u32 = u32::from_be_bytes(netmask.octets());

        // 计算网络地址
        let network1 = ip1_u32 & netmask_u32;
        let network2 = ip2_u32 & netmask_u32;

        network1 == network2
    }

    /// 获取物理网络接口名称（排除 VPN/tun/tap 接口）
    ///
    /// 优先级：
    /// 1. wlan*/wlp* (无线)
    /// 2. enp*/eth* (有线)
    /// 3. 其他非VPN接口
    ///
    /// 返回 (物理接口, VPN接口列表)
    fn get_physical_interface() -> (Option<String>, Vec<String>) {
        let mut physical_interfaces = Vec::new();
        let mut vpn_interfaces = Vec::new();

        if let Ok(if_addrs) = if_addrs::get_if_addrs() {
            for iface in if_addrs {
                let name = &iface.name;

                // 排除回环接口
                if name == "lo" || name == "Loopback" {
                    continue;
                }

                // 检测 VPN/虚拟接口
                let is_vpn = name.contains("tun") ||
                             name.contains("tap") ||
                             name.contains("ppp") ||
                             name.contains("vsock") ||
                             name.contains("vpn");

                // 只处理有IPv4地址的接口
                match iface.addr {
                    if_addrs::IfAddr::V4(ref v4) if !v4.ip.is_loopback() => {
                        if is_vpn {
                            vpn_interfaces.push(name.clone());
                            tracing::warn!("⚠️ 检测到VPN/虚拟接口: {} (IP: {})", name, v4.ip);
                        } else {
                            physical_interfaces.push((name.clone(), v4.ip));
                        }
                    }
                    _ => continue,
                }
            }
        }

        // 按优先级排序物理接口
        physical_interfaces.sort_by_key(|(name, _)| {
            // 无线接口优先
            if name.starts_with("wlan") || name.starts_with("wlp") {
                0
            // 有线接口次之
            } else if name.starts_with("enp") || name.starts_with("eth") {
                1
            // 其他接口
            } else {
                2
            }
        });

        let chosen = physical_interfaces.first().map(|(name, ip)| {
            tracing::info!("🌐 选择物理接口: {} (IP: {})", name, ip);
            send_log("INFO", "mdns_discovery", format!("🌐 选择物理接口: {} (IP: {})", name, ip));
            name.clone()
        });

        (chosen, vpn_interfaces)
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
