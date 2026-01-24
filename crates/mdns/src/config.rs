//! mDNS 配置模块

use libp2p::Multiaddr;

/// mDNS 配置
#[derive(Debug, Clone)]
pub struct MdnsConfig {
    /// 监听地址列表
    pub listen_addresses: Vec<Multiaddr>,

    /// 服务查询间隔
    pub query_interval: std::time::Duration,

    /// 服务信息
    pub service_info: Option<ServiceInfo>,
}

impl Default for MdnsConfig {
    fn default() -> Self {
        Self {
            listen_addresses: vec![
                "/ip4/0.0.0.0/tcp/0".parse().unwrap(),
                "/ip6/::/tcp/0".parse().unwrap(),
            ],
            query_interval: std::time::Duration::from_secs(5),
            service_info: None,
        }
    }
}

impl MdnsConfig {
    /// 创建新的配置
    pub fn new() -> Self {
        Self::default()
    }

    /// 设置监听地址
    pub fn with_listen_addresses(mut self, addrs: Vec<Multiaddr>) -> Self {
        self.listen_addresses = addrs;
        self
    }

    /// 设置查询间隔
    pub fn with_query_interval(mut self, interval: std::time::Duration) -> Self {
        self.query_interval = interval;
        self
    }

    /// 设置服务信息
    pub fn with_service_info(mut self, info: ServiceInfo) -> Self {
        self.service_info = Some(info);
        self
    }
}

/// 服务信息
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServiceInfo {
    /// 服务名称
    pub name: String,

    /// 服务类型
    pub service_type: String,

    /// 服务端口
    pub port: u16,

    /// 自定义属性
    pub attributes: Vec<(String, String)>,
}

impl ServiceInfo {
    /// 创建新的服务信息
    pub fn new(name: String, service_type: String, port: u16) -> Self {
        Self {
            name,
            service_type,
            port,
            attributes: Vec::new(),
        }
    }

    /// 添加自定义属性
    pub fn with_attribute(mut self, key: String, value: String) -> Self {
        self.attributes.push((key, value));
        self
    }
}
