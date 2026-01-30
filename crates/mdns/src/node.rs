//! 节点管理模块
//!
//! 提供节点管理器来维护验证通过的节点列表。

use libp2p::{PeerId, Multiaddr};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// 节点连接状态
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NodeStatus {
    /// 在线（有活跃连接）
    Online,
    /// 离线（连接断开，但节点信息保留）
    Offline,
}

impl NodeStatus {
    /// 是否在线
    pub fn is_online(&self) -> bool {
        matches!(self, Self::Online)
    }

    /// 是否离线
    pub fn is_offline(&self) -> bool {
        matches!(self, Self::Offline)
    }
}

/// 验证通过的节点信息
#[derive(Debug, Clone)]
pub struct VerifiedNode {
    /// 节点 Peer ID
    pub peer_id: PeerId,

    /// 节点地址列表
    pub addresses: Vec<Multiaddr>,

    /// 协议版本（用于验证）
    pub protocol_version: String,

    /// 代理/应用版本（用于验证）
    pub agent_version: String,

    /// 设备名称（从 agent_version 解析，用于显示）
    pub name: Option<String>,

    /// 首次发现时间
    pub first_seen: Instant,

    /// 最后活跃时间
    pub last_seen: Instant,

    /// ⭐ 节点状态
    pub status: NodeStatus,

    /// 离线原因
    pub offline_reason: Option<String>,

    /// 离线时间
    pub offline_since: Option<Instant>,

    /// 自定义属性
    pub attributes: HashMap<String, String>,
}

impl VerifiedNode {
    /// 创建新的验证节点
    pub fn new(
        peer_id: PeerId,
        addresses: Vec<Multiaddr>,
        protocol_version: String,
        agent_version: String,
    ) -> Self {
        let name = parse_device_name(&agent_version);
        let now = Instant::now();
        Self {
            peer_id,
            addresses,
            protocol_version,
            agent_version,
            name,
            first_seen: now,
            last_seen: now,
            status: NodeStatus::Online,  // ← 默认在线
            offline_reason: None,
            offline_since: None,
            attributes: HashMap::new(),
        }
    }

    /// 获取显示名称（优先使用设备名称，否则使用 Peer ID）
    pub fn display_name(&self) -> String {
        if let Some(ref name) = self.name {
            format!("{} ({})", name, self.peer_id)
        } else {
            self.peer_id.to_string()
        }
    }

    /// 获取显示名称（包含状态）
    pub fn display_name_with_status(&self) -> String {
        let status_indicator = if self.status.is_online() {
            "🟢"
        } else {
            "🔴"
        };
        format!("{} {}", status_indicator, self.display_name())
    }

    /// 更新最后活跃时间
    pub fn update_last_seen(&mut self) {
        self.last_seen = Instant::now();
    }

    /// 检查节点是否超时（距离最后活跃时间超过指定时长）
    pub fn is_timeout(&self, timeout: Duration) -> bool {
        self.last_seen.elapsed() > timeout
    }

    /// 添加自定义属性
    pub fn with_attribute(mut self, key: String, value: String) -> Self {
        self.attributes.insert(key, value);
        self
    }

    /// 获取节点存活时长
    pub fn age(&self) -> Duration {
        self.first_seen.elapsed()
    }

    /// 获取距离最后活跃的时间
    pub fn idle_time(&self) -> Duration {
        self.last_seen.elapsed()
    }
}

/// 节点管理器配置
#[derive(Debug, Clone)]
pub struct NodeManagerConfig {
    /// 节点超时时间（超过此时间未活跃的节点将被清理）
    pub node_timeout: Duration,

    /// 清理任务执行间隔
    pub cleanup_interval: Duration,

    /// 期望的协议版本（用于验证节点）
    pub expected_protocol_version: String,

    /// 期望的代理版本前缀（用于验证节点）
    pub expected_agent_prefix: Option<String>,

    /// 本设备名称（会包含在 agent_version 中）
    pub device_name: Option<String>,
}

impl Default for NodeManagerConfig {
    fn default() -> Self {
        Self {
            node_timeout: Duration::from_secs(300), // 5分钟
            cleanup_interval: Duration::from_secs(60), // 1分钟
            expected_protocol_version: "/localp2p/1.0.0".to_string(),
            expected_agent_prefix: Some("localp2p-rust/".to_string()),
            device_name: None,
        }
    }
}

impl NodeManagerConfig {
    /// 创建新的配置
    pub fn new() -> Self {
        Self::default()
    }

    /// 设置节点超时时间
    pub fn with_node_timeout(mut self, timeout: Duration) -> Self {
        self.node_timeout = timeout;
        self
    }

    /// 设置清理间隔
    pub fn with_cleanup_interval(mut self, interval: Duration) -> Self {
        self.cleanup_interval = interval;
        self
    }

    /// 设置期望的协议版本
    pub fn with_protocol_version(mut self, version: String) -> Self {
        self.expected_protocol_version = version;
        self
    }

    /// 设置期望的代理版本前缀
    pub fn with_agent_prefix(mut self, prefix: Option<String>) -> Self {
        self.expected_agent_prefix = prefix;
        self
    }

    /// 设置设备名称
    pub fn with_device_name(mut self, name: String) -> Self {
        self.device_name = Some(name);
        self
    }

    /// 构建完整的 agent_version（包含设备名称）
    pub fn build_agent_version(&self) -> String {
        if let Some(ref name) = self.device_name {
            format!("{}1.0.0 ({})", self.expected_agent_prefix.as_ref().unwrap_or(&"localp2p-rust/".to_string()), name)
        } else {
            format!("{}1.0.0", self.expected_agent_prefix.as_ref().unwrap_or(&"localp2p-rust/".to_string()))
        }
    }
}

use crate::MdnsError;

/// 节点管理器
///
/// 负责管理所有验证通过的节点，提供添加、移除、查询等功能。
#[derive(Debug)]
pub struct NodeManager {
    /// 节点存储
    nodes: RwLock<HashMap<PeerId, VerifiedNode>>,

    /// 配置
    config: NodeManagerConfig,
}

impl NodeManager {
    /// 创建新的节点管理器
    pub fn new(config: NodeManagerConfig) -> Self {
        Self {
            nodes: RwLock::new(HashMap::new()),
            config,
        }
    }

    /// 使用默认配置创建节点管理器
    pub fn with_default_config() -> Self {
        Self::new(NodeManagerConfig::default())
    }

    /// 添加或更新验证通过的节点
    pub async fn add_or_update_node(&self, node: VerifiedNode) {
        let mut nodes = self.nodes.write().await;
        let peer_id = node.peer_id;

        // 如果节点已存在，更新其最后活跃时间和地址
        if let Some(existing) = nodes.get_mut(&peer_id) {
            existing.update_last_seen();
            existing.addresses = node.addresses;
            tracing::debug!("更新节点: {}", peer_id);
        } else {
            // 新节点，直接添加
            nodes.insert(peer_id, node);
            tracing::info!("添加验证通过的节点: {}", peer_id);
        }
    }

    /// 移除节点
    pub async fn remove_node(&self, peer_id: &PeerId) -> Option<VerifiedNode> {
        let mut nodes = self.nodes.write().await;
        let removed = nodes.remove(peer_id);
        if removed.is_some() {
            tracing::info!("移除节点: {}", peer_id);
        }
        removed
    }

    /// 获取节点信息
    pub async fn get_node(&self, peer_id: &PeerId) -> Option<VerifiedNode> {
        let nodes = self.nodes.read().await;
        nodes.get(peer_id).cloned()
    }

    /// 检查节点是否已验证
    pub async fn is_node_verified(&self, peer_id: &PeerId) -> bool {
        let nodes = self.nodes.read().await;
        nodes.contains_key(peer_id)
    }

    /// 获取节点数量
    pub async fn node_count(&self) -> usize {
        let nodes = self.nodes.read().await;
        nodes.len()
    }

    /// 清理超时的节点
    pub async fn cleanup_inactive(&self) -> Vec<PeerId> {
        let mut nodes = self.nodes.write().await;
        let mut removed = Vec::new();

        nodes.retain(|peer_id, node| {
            if node.is_timeout(self.config.node_timeout) {
                removed.push(*peer_id);
                false
            } else {
                true
            }
        });

        if !removed.is_empty() {
            for peer_id in &removed {
                tracing::info!("清理超时节点: {}", peer_id);
            }
        }

        removed
    }

    /// 启动后台清理任务
    pub fn spawn_cleanup_task(self: std::sync::Arc<Self>) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(self.config.cleanup_interval);
            loop {
                interval.tick().await;
                let removed = self.cleanup_inactive().await;
                if !removed.is_empty() {
                    tracing::debug!("后台清理任务移除了 {} 个超时节点", removed.len());
                }
            }
        })
    }

    /// 获取配置
    pub fn config(&self) -> &NodeManagerConfig {
        &self.config
    }

    /// 标记节点为离线（不移除）
    pub async fn mark_node_offline(
        &self,
        peer_id: &PeerId,
        reason: &str,
    ) -> bool {
        let mut nodes = self.nodes.write().await;
        if let Some(node) = nodes.get_mut(peer_id) {
            // 只在节点从在线变为离线时返回 true
            let was_online = matches!(node.status, NodeStatus::Online);

            node.status = NodeStatus::Offline;
            node.offline_reason = Some(reason.to_string());
            node.offline_since = Some(Instant::now());

            let display_name = if let Some(ref name) = node.name {
                name.clone()
            } else {
                peer_id.to_string()
            };

            if was_online {
                tracing::info!(
                    "节点 {} 已标记为离线: {} (原因: {})",
                    display_name,
                    peer_id,
                    reason
                );
            }

            was_online
        } else {
            false
        }
    }

    /// 标记节点为在线（重新连接时）
    pub async fn mark_node_online(&self, peer_id: &PeerId) {
        let mut nodes = self.nodes.write().await;
        if let Some(node) = nodes.get_mut(peer_id) {
            let was_offline = node.status.is_offline();

            node.status = NodeStatus::Online;
            node.offline_reason = None;
            node.offline_since = None;
            node.update_last_seen();

            if was_offline {
                let display_name = if let Some(ref name) = node.name {
                    name.clone()
                } else {
                    peer_id.to_string()
                };
                tracing::info!(
                    "💚 节点 {} 已恢复在线",
                    display_name
                );
            }
        }
    }

    /// 更新节点的用户信息（存储在 attributes 中）
    pub async fn update_node_user_info(
        &self,
        peer_id: &PeerId,
        user_info: &crate::user_info::UserInfo,
    ) {
        let mut nodes = self.nodes.write().await;
        if let Some(node) = nodes.get_mut(peer_id) {
            // 将用户信息存储到 attributes 中
            node.attributes.insert("device_name".to_string(), user_info.device_name.clone());
            if let Some(ref nickname) = user_info.nickname {
                node.attributes.insert("nickname".to_string(), nickname.clone());
            }
            if let Some(ref status) = user_info.status {
                node.attributes.insert("status".to_string(), status.clone());
            }
            if let Some(ref avatar_url) = user_info.avatar_url {
                node.attributes.insert("avatar_url".to_string(), avatar_url.clone());
            }
            tracing::debug!("更新节点 {} 的用户信息: {}", peer_id, user_info.device_name);
        }
    }

    /// 列出所有节点（包括离线）
    pub async fn list_all_nodes(&self) -> Vec<VerifiedNode> {
        let nodes = self.nodes.read().await;
        nodes.values().cloned().collect()
    }

    /// 只列出在线节点
    pub async fn list_online_nodes(&self) -> Vec<VerifiedNode> {
        let nodes = self.nodes.read().await;
        nodes.values()
            .filter(|n| n.status.is_online())
            .cloned()
            .collect()
    }

    /// ⚠️ 已弃用：使用 list_all_nodes() 代替
    #[deprecated(note = "请使用 list_all_nodes() 代替")]
    pub async fn list_nodes(&self) -> Vec<VerifiedNode> {
        self.list_all_nodes().await
    }

    /// 验证节点信息
    pub fn verify_node_info(
        &self,
        protocol_version: &str,
        agent_version: &str,
    ) -> std::result::Result<(), MdnsError> {
        // 验证协议版本
        if protocol_version != self.config.expected_protocol_version {
            return Err(MdnsError::SwarmBuild(format!(
                "协议版本不匹配: 期望 {}, 收到 {}",
                self.config.expected_protocol_version, protocol_version
            )));
        }

        // 验证代理版本前缀
        if let Some(ref prefix) = self.config.expected_agent_prefix {
            if !agent_version.starts_with(prefix) {
                return Err(MdnsError::SwarmBuild(format!(
                    "代理版本不匹配: 期望前缀 {}, 收到 {}",
                    prefix, agent_version
                )));
            }
        }

        Ok(())
    }
}

/// 从 agent_version 中解析设备名称
///
/// 支持格式: `prefix/version (name)` 或 `prefix/version`
/// 例如: `localp2p-rust/1.0.0 (我的设备)` → "我的设备"
fn parse_device_name(agent_version: &str) -> Option<String> {
    // 查找括号中的设备名称
    if let Some(start) = agent_version.find('(') {
        if let Some(end) = agent_version.rfind(')') {
            if start < end {
                let name = agent_version[start + 1..end].trim().to_string();
                if !name.is_empty() {
                    return Some(name);
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_device_name_with_name() {
        let agent = "localp2p-rust/1.0.0 (我的电脑)";
        let name = parse_device_name(agent);
        assert_eq!(name, Some("我的电脑".to_string()));
    }

    #[test]
    fn test_parse_device_name_without_name() {
        let agent = "localp2p-rust/1.0.0";
        let name = parse_device_name(agent);
        assert_eq!(name, None);
    }

    #[test]
    fn test_parse_device_name_empty_parens() {
        let agent = "localp2p-rust/1.0.0 ()";
        let name = parse_device_name(agent);
        assert_eq!(name, None);
    }

    #[test]
    fn test_verified_node_without_name() {
        let peer_id = PeerId::random();
        let node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );
        assert_eq!(node.name, None);
        assert_eq!(node.display_name(), peer_id.to_string());
    }

    #[test]
    fn test_verified_node_with_name() {
        let peer_id = PeerId::random();
        let node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0 (测试设备)".to_string(),
        );
        assert_eq!(node.name, Some("测试设备".to_string()));
        // display_name 应该是 "测试设备 (peer_id)" 的格式
        assert!(node.display_name().starts_with("测试设备 ("));
        assert!(node.display_name().ends_with(")"));
    }

    #[test]
    fn test_node_manager_config_build_agent_version() {
        let config = NodeManagerConfig::new()
            .with_device_name("我的设备".to_string());
        assert_eq!(config.build_agent_version(), "localp2p-rust/1.0.0 (我的设备)");
    }

    #[test]
    fn test_node_manager_config_build_agent_version_without_name() {
        let config = NodeManagerConfig::new();
        assert_eq!(config.build_agent_version(), "localp2p-rust/1.0.0");
    }

    #[tokio::test]
    async fn test_add_and_get_node() {
        let manager = NodeManager::with_default_config();
        let peer_id = PeerId::random();
        let node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        manager.add_or_update_node(node).await;
        assert!(manager.is_node_verified(&peer_id).await);

        let retrieved = manager.get_node(&peer_id).await;
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().peer_id, peer_id);
    }

    #[tokio::test]
    async fn test_remove_node() {
        let manager = NodeManager::with_default_config();
        let peer_id = PeerId::random();
        let node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        manager.add_or_update_node(node).await;
        assert!(manager.is_node_verified(&peer_id).await);

        manager.remove_node(&peer_id).await;
        assert!(!manager.is_node_verified(&peer_id).await);
    }

    #[test]
    fn test_node_timeout() {
        let peer_id = PeerId::random();
        let mut node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        assert!(!node.is_timeout(Duration::from_secs(10)));

        // 模拟时间流逝
        node.first_seen = Instant::now() - Duration::from_secs(100);
        node.last_seen = Instant::now() - Duration::from_secs(100);

        assert!(node.is_timeout(Duration::from_secs(10)));
    }

    #[tokio::test]
    async fn test_mark_node_offline_and_online() {
        let peer_id = PeerId::random();
        let config = NodeManagerConfig::default();
        let manager = NodeManager::new(config);

        // 添加节点
        let node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        manager.add_or_update_node(node).await;
        assert!(manager.is_node_verified(&peer_id).await);

        // 标记为离线
        let marked = manager.mark_node_offline(&peer_id, "测试离线").await;
        assert!(marked);

        // 验证节点仍然存在
        assert!(manager.is_node_verified(&peer_id).await);

        // 检查节点状态为离线
        let all_nodes = manager.list_all_nodes().await;
        let node = &all_nodes[0];
        assert_eq!(node.status, NodeStatus::Offline);
        assert_eq!(node.offline_reason.as_ref().unwrap(), "测试离线");

        // 标记为在线
        manager.mark_node_online(&peer_id).await;

        // 检查节点状态恢复为在线
        let all_nodes = manager.list_all_nodes().await;
        let node = &all_nodes[0];
        assert_eq!(node.status, NodeStatus::Online);
        assert!(node.offline_since.is_none());
    }

    #[tokio::test]
    async fn test_list_online_nodes_filters_offline() {
        let peer_id1 = PeerId::random();
        let peer_id2 = PeerId::random();
        let config = NodeManagerConfig::default();
        let manager = NodeManager::new(config);

        // 添加两个节点
        let node1 = VerifiedNode::new(
            peer_id1,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        let node2 = VerifiedNode::new(
            peer_id2,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        manager.add_or_update_node(node1).await;
        manager.add_or_update_node(node2).await;

        // 两个节点都应该在线
        let online_nodes = manager.list_online_nodes().await;
        assert_eq!(online_nodes.len(), 2);

        // 将一个节点标记为离线
        manager.mark_node_offline(&peer_id1, "测试").await;

        // 在线节点列表应该只包含一个节点
        let online_nodes = manager.list_online_nodes().await;
        assert_eq!(online_nodes.len(), 1);
        assert_eq!(online_nodes[0].peer_id, peer_id2);

        // 所有节点列表应该包含两个节点
        let all_nodes = manager.list_all_nodes().await;
        assert_eq!(all_nodes.len(), 2);
    }

    #[tokio::test]
    async fn test_mark_node_offline_idempotent() {
        let peer_id = PeerId::random();
        let config = NodeManagerConfig::default();
        let manager = NodeManager::new(config);

        // 添加节点
        let node = VerifiedNode::new(
            peer_id,
            vec![],
            "/localp2p/1.0.0".to_string(),
            "localp2p-rust/1.0.0".to_string(),
        );

        manager.add_or_update_node(node).await;

        // 多次标记为离线应该返回 false（第一次除外）
        assert!(manager.mark_node_offline(&peer_id, "第一次").await);
        assert!(!manager.mark_node_offline(&peer_id, "第二次").await);
        assert!(!manager.mark_node_offline(&peer_id, "第三次").await);
    }
}
