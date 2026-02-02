//! P2P 事件定义
//!
//! 定义服务间通信的事件类型。

use libp2p::{PeerId, Multiaddr};

/// P2P 发现事件（服务间通信）
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiscoveryEvent {
    /// 发现新设备
    Discovered {
        peer_id: PeerId,
        addr: Multiaddr,
    },

    /// 设备过期
    Expired {
        peer_id: PeerId,
    },

    /// 刷新事件（用于触发重新扫描）
    Refresh,

    /// mDNS 服务已启动，通知 Flutter 启动辅助 mDNS 广播
    /// 用于测试 Flutter mDNS 能否正常工作，以及 Rust 能否接收到 Flutter 的广播
    MdnsStarted {
        /// 本地 Peer ID
        local_peer_id: String,
        /// 监听端口
        port: u16,
        /// 服务类型
        service_type: String,
    },

    /// 🔥 服务状态变化（用于健康监控）
    ServiceStateChanged {
        /// 服务名称（如 "mDNS", "Connection"）
        service: String,
        /// 服务状态
        status: ServiceStatus,
    },

    /// 🔥 节点列表已更新（触发状态刷新）
    NodesUpdated,
}

/// P2P 连接事件
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionEvent {
    /// 连接建立
    Connected {
        peer_id: PeerId,
    },

    /// 连接关闭
    Disconnected {
        peer_id: PeerId,
        reason: String,
    },
}

/// 服务健康状态
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServiceHealth {
    /// 服务正常
    Healthy,
    /// 服务 degraded（部分功能可用）
    Degraded,
    /// 服务不健康
    Unhealthy,
}

/// 单个服务状态
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServiceStatus {
    /// 服务名称
    pub name: String,
    /// 健康状态
    pub health: ServiceHealth,
    /// 是否正在运行
    pub is_running: bool,
    /// 状态消息（可选）
    pub message: Option<String>,
}

impl ServiceStatus {
    /// 创建新的服务状态
    pub fn new(name: impl Into<String>, health: ServiceHealth, is_running: bool) -> Self {
        Self {
            name: name.into(),
            health,
            is_running,
            message: None,
        }
    }

    /// 设置状态消息
    pub fn with_message(mut self, message: impl Into<String>) -> Self {
        self.message = Some(message.into());
        self
    }
}

/// P2P 系统整体状态
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemStatus {
    /// mDNS 服务状态
    pub mdns_service: ServiceStatus,
    /// 连接服务状态
    pub connection_service: ServiceStatus,
    /// 已连接的节点数量
    pub connected_peers: usize,
    /// 已发现的节点数量
    pub discovered_peers: usize,
}

impl SystemStatus {
    /// 创建新的系统状态
    pub fn new(mdns_service: ServiceStatus, connection_service: ServiceStatus) -> Self {
        Self {
            mdns_service,
            connection_service,
            connected_peers: 0,
            discovered_peers: 0,
        }
    }

    /// 设置连接的节点数量
    pub fn with_connected_peers(mut self, count: usize) -> Self {
        self.connected_peers = count;
        self
    }

    /// 设置发现的节点数量
    pub fn with_discovered_peers(mut self, count: usize) -> Self {
        self.discovered_peers = count;
        self
    }

    /// 判断系统是否健康
    pub fn is_healthy(&self) -> bool {
        self.mdns_service.is_running && self.connection_service.is_running &&
        self.mdns_service.health == ServiceHealth::Healthy &&
        self.connection_service.health == ServiceHealth::Healthy
    }
}

/// 服务状态变化事件
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServiceStateEvent {
    /// mDNS 服务状态变化
    MdnsServiceChanged {
        status: ServiceStatus,
    },

    /// 连接服务状态变化
    ConnectionServiceChanged {
        status: ServiceStatus,
    },

    /// 系统整体状态变化
    SystemStatusChanged {
        status: SystemStatus,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    use libp2p::{PeerId, Multiaddr};

    #[test]
    fn test_discovery_event_equality() {
        let peer_id = PeerId::random();
        let addr: Multiaddr = "/ip4/127.0.0.1/tcp/8000".parse().unwrap();

        let event1 = DiscoveryEvent::Discovered {
            peer_id,
            addr: addr.clone(),
        };

        let event2 = DiscoveryEvent::Discovered {
            peer_id,
            addr,
        };

        assert_eq!(event1, event2);
    }

    #[test]
    fn test_discovery_event_expired() {
        let peer_id = PeerId::random();
        let event = DiscoveryEvent::Expired { peer_id };

        match event {
            DiscoveryEvent::Expired { peer_id: pid } => {
                assert_eq!(pid, peer_id);
            }
            _ => panic!("Expected Expired event"),
        }
    }

    #[test]
    fn test_connection_event_connected() {
        let peer_id = PeerId::random();
        let event = ConnectionEvent::Connected { peer_id };

        assert_eq!(event, ConnectionEvent::Connected { peer_id });
    }

    #[test]
    fn test_connection_event_disconnected() {
        let peer_id = PeerId::random();
        let reason = "连接超时".to_string();
        let event = ConnectionEvent::Disconnected {
            peer_id,
            reason: reason.clone(),
        };

        match event {
            ConnectionEvent::Disconnected { peer_id: pid, reason: r } => {
                assert_eq!(pid, peer_id);
                assert_eq!(r, reason);
            }
            _ => panic!("Expected Disconnected event"),
        }
    }

    #[test]
    fn test_connection_event_not_equal() {
        let peer_id1 = PeerId::random();
        let peer_id2 = PeerId::random();

        let event1 = ConnectionEvent::Connected { peer_id: peer_id1 };
        let event2 = ConnectionEvent::Connected { peer_id: peer_id2 };

        assert_ne!(event1, event2);
    }
}
