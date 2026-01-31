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
