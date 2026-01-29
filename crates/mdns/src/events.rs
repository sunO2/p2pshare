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
