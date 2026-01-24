# Local P2P mDNS 开发历史记录

本文档记录了项目从初始创建到最终实现完整功能的完整开发历程，包括遇到的问题、解决方案和技术决策。

## 目录

1. [项目初始化](#项目初始化)
2. [第一阶段：基础 mDNS 模块](#第一阶段基础-mdns-模块)
3. [第二阶段：libp2p 0.54 → 0.56 升级](#第二阶段libp2p-054--056-升级)
4. [第三阶段：节点验证机制](#第三阶段节点验证机制)
5. [第四阶段：NodeManager 实现](#第四阶段nodemanager-实现)
6. [第五阶段：心跳/健康检查](#第五阶段心跳健康检查)
7. [关键问题与解决方案](#关键问题与解决方案)

---

## 项目初始化

### 创建 Workspace 项目

**时间**: 早期

**目标**: 创建一个基于 libp2p 的局域网 P2P 服务发现系统

**决策**:
- 使用 Cargo workspace 管理 crate
- 创建独立的 `mdns` crate 作为可复用库
- 主项目依赖 `mdns` crate

**初始结构**:
```
localp2p/
├── Cargo.toml          # workspace 配置
├── src/main.rs         # 示例程序
└── crates/mdns/        # mdns crate
    ├── Cargo.toml
    └── src/
        ├── lib.rs
        ├── config.rs
        ├── discovery.rs
        └── publisher.rs
```

---

## 第一阶段：基础 mDNS 模块

### libp2p 0.53 初始实现

**初始依赖**:
```toml
libp2p = { version = "0.53", features = ["mdns", "tokio", "tcp", "noise", "yamux"] }
```

**问题 1: SwarmBuilder API 变化**

**错误**:
```
error[E0599]: no function or associated item named `with_existing_identity`
```

**原因**: libp2p 0.53 的 SwarmBuilder API 与文档不符

**解决方案**: 更新到 libp2p 0.54

---

## 第二阶段：libp2p 0.54 → 0.56 升级

### 升级到 libp2p 0.54

**更新依赖**:
```toml
libp2p = { version = "0.54", features = ["mdns", "tokio", "tcp", "noise", "yamux"] }
```

**问题 2: with_other_network 不存在**

**错误**:
```
error[E0599]: no method named `with_other_network` found
```

**原因**: libp2p 0.54 移除了 `with_other_network`，改用 `with_tcp`

**解决方案**:
```rust
// 旧代码（错误）
SwarmBuilder::with_existing_identity(key)
    .with_other_network(|_| { /* ... */ })

// 新代码（正确）
SwarmBuilder::with_existing_identity(key)
    .with_tokio()
    .with_tcp(
        libp2p::tcp::Config::default(),
        libp2p::noise::Config::new,
        libp2p::yamux::Config::default,
    )
```

### 升级到 libp2p 0.56

**用户主动升级**:
```toml
libp2p = { version = "0.56.0", features = ["mdns", "tokio", "tcp", "noise", "yamux", "identify", "macros"] }
```

**问题 3: NetworkBehaviour 宏位置**

**错误**:
```
error[E0433]: failed to resolve: could not find `NetworkBehaviour` in `swarm`
```

**原因**: 0.56 版本需要 `macros` feature，且宏路径改变

**解决方案**:
```rust
// 添加 macros feature
libp2p = { version = "0.56.0", features = ["...", "macros"] }

// 使用正确的宏路径
#[derive(libp2p::swarm::NetworkBehaviour)]
struct ManagedBehaviour {
    mdns: mdns::tokio::Behaviour,
    identify: identify::Behaviour,
}
```

**问题 4: Identify 事件模式匹配**

**错误**:
```
error[E0027]: pattern does not mention fields
```

**原因**: identify::Event::Received 需要忽略更多字段

**解决方案**:
```rust
// 旧代码（错误）
identify::Event::Received { peer_id, info } => { /* ... */ }

// 新代码（正确）
identify::Event::Received { peer_id, info, .. } => { /* ... */ }
```

**问题 5: identify::Info 字段访问**

**错误**: 尝试调用 `info.protocol_version()` 作为方法

**原因**: libp2p 0.56 中 `identify::Info` 的字段是公开的，不是方法

**解决方案**:
```rust
// 旧代码（错误）
info.protocol_version()
info.agent_version()
info.listen_addrs()

// 新代码（正确）
info.protocol_version
info.agent_version
info.listen_addrs
```

---

## 第三阶段：节点验证机制

### 需求背景

**问题**: mDNS 发现的节点可能是其他应用，如何验证是同一个应用？

### 方案选择

**方案 1**: 使用自定义协议层验证
- ❌ 复杂，需要额外实现

**方案 2**: 使用 mDNS 服务类型过滤
- ❌ libp2p mDNS 不支持自定义服务类型

**方案 3**: 使用 libp2p identify 协议 ✅
- ✅ 简单，libp2p 原生支持
- ✅ 可验证 protocol_version 和 agent_version

### Identify 协议实现

**配置**:
```rust
identify::Config::new(
    "/localp2p/1.0.0".to_string(),  // protocol_version
    key.public()
)
.with_agent_version("localp2p-rust/1.0.0".to_string())
.with_interval(Duration::from_secs(30))
```

**验证逻辑**:
```rust
pub fn verify_node_info(&self, protocol_version: &str, agent_version: &str) -> Result<()> {
    // 验证协议版本
    if protocol_version != self.expected_protocol_version {
        return Err(MdnsError::VerificationFailed(
            format!("协议版本不匹配: 期望 {}, 得到 {}", self.expected_protocol_version, protocol_version)
        ));
    }

    // 验证代理版本前缀
    if let Some(prefix) = &self.expected_agent_prefix {
        if !agent_version.starts_with(prefix) {
            return Err(MdnsError::VerificationFailed(
                format!("代理版本不匹配: 期望前缀 {}, 得到 {}", prefix, agent_version)
            ));
        }
    }

    Ok(())
}
```

---

## 第四阶段：NodeManager 实现

### 需求

需要一个集中管理器来：
1. 存储验证通过的节点
2. 自动清理超时节点
3. 提供查询 API

### VerifiedNode 结构

**初始尝试**:
```rust
#[derive(Serialize, Deserialize)]
pub struct VerifiedNode {
    pub peer_id: PeerId,
    // ...
}
```

**问题**: PeerId 和 Instant 不支持 Deserialize

**解决方案**: 移除 Serialize/Deserialize derives

### NodeManager 实现

**核心结构**:
```rust
pub struct NodeManager {
    nodes: RwLock<HashMap<PeerId, VerifiedNode>>,
    config: NodeManagerConfig,
}
```

**后台清理任务**:
```rust
pub fn spawn_cleanup_task(self: Arc<Self>) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(self.config.cleanup_interval);
        loop {
            interval.tick().await;
            self.cleanup_inactive().await;
        }
    })
}
```

---

## 第五阶段：心跳/健康检查

### 问题：mDNS TTL 延迟

**现象**: 节点离线后，mDNS 记录需要 2-5 分钟才过期

**日志证据**:
```
14:03:10 - 节点验证通过
14:09:07 - 清理超时节点（5分钟超时）
14:09:10 - mDNS 记录过期
```

### 方案：集成 Ping 协议

**初始设计**: 创建独立的 `HeartbeatManager`
```rust
pub struct HeartbeatManager {
    ping: ping::Behaviour,
    health_status: HashMap<PeerId, NodeHealth>,
    // ...
}
```

**问题**: ping behaviour 需要 Swarm 才能工作，不能独立存在

**最终方案**: 将 ping 集成到 `ManagedBehaviour`

### libp2p 0.56 Ping API

**问题 6: ping::Config API 变化**

**错误**:
```
error[E0599]: no method named `with_keep_alive` found for struct `libp2p::libp2p_ping::Config`
```

**原因**: libp2p 0.56 移除了 `with_keep_alive` 方法

**解决方案**:
```rust
// 旧代码（错误）
let ping = ping::Behaviour::new(ping::Config::new().with_keep_alive(false));

// 新代码（正确）
let ping = ping::Behaviour::new(ping::Config::default());
```

**问题 7: ping::Event 是结构体不是枚举**

**错误**:
```
error[E0223]: ambiguous associated type
ping::Event::Result { peer_id, result } => { /* ... */ }
```

**原因**: libp2p 0.56 中 `ping::Event` 是结构体，不是枚举

**解决方案**:
```rust
// 正确的模式匹配
let ping::Event { peer, connection: _, result } = event;
match result {
    Ok(rtt) => { /* ping 成功 */ }
    Err(_e) => { /* ping 失败 */ }
}
```

### 问题：连接断开检测

**问题**: 关闭对方程序后，没有看到 ping 失败事件

**原因**:
1. 程序关闭时，libp2p 发送 `ConnectionClosed` 事件
2. 连接断开后，ping 无法工作（没有连接）
3. ping 只在连接存在时检测超时

**解决方案：跟踪连接数**

```rust
pub struct ManagedDiscovery {
    // ...
    active_connections: HashMap<PeerId, u32>,
}

// ConnectionEstablished - 增加计数
*self.active_connections.entry(peer_id).or_insert(0) += 1;

// ConnectionClosed - 减少计数，为0时标记离线
if *conn_count == 0 {
    tracing::warn!("💔 节点 {} 的所有连接已关闭，判定为离线", peer_id);
    // 从管理器移除节点
}
```

---

## 关键问题与解决方案

### 问题汇总表

| 问题 | 版本 | 错误信息 | 解决方案 |
|------|------|----------|----------|
| SwarmBuilder API | 0.53 | `with_existing_identity` 不存在 | 升级到 0.54 |
| with_other_network | 0.54 | 方法不存在 | 改用 `with_tcp()` |
| NetworkBehaviour 宏 | 0.56 | 找不到宏 | 添加 `macros` feature，使用 `libp2p::swarm::NetworkBehaviour` |
| Identify 事件匹配 | 0.56 | 模式不完整 | 添加 `..` 忽略其他字段 |
| identify::Info 访问 | 0.56 | 方法不存在 | 直接访问字段 |
| Ping Config API | 0.56 | `with_keep_alive` 不存在 | 使用 `Config::default()` |
| ping::Event 类型 | 0.56 | 模式匹配错误 | 使用结构体解构 |
| PeerId 序列化 | - | 不支持 Deserialize | 移除 Serialize/Deserialize |
| IPv6 地址格式 | - | `UnknownProtocolString("ip6::")` | 移除 IPv6 监听或使用 `/ip6:///` |
| mDNS 过期延迟 | - | 2-5分钟延迟 | 使用 ConnectionClosed 事件检测 |
| Ping 不触发 | - | 连接断开后无 ping 事件 | 跟踪活跃连接数 |

### libp2p 版本选择建议

| 版本 | 稳定性 | 功能 | 推荐度 |
|------|--------|------|--------|
| 0.53 | ⚠️ API 不稳定 | 基础功能 | ❌ 不推荐 |
| 0.54 | ✅ API 稳定 | 基础功能 | ⚠️ 可用 |
| 0.56 | ✅ API 完善 | 最新功能 | ✅ 强烈推荐 |

### 开发经验总结

1. **版本锁定**: 使用 libp2p 时，明确指定版本，不同版本 API 差异较大
2. **宏路径**: NetworkBehaviour 宏路径是 `libp2p::swarm::NetworkBehaviour`
3. **事件处理**: 使用 `..` 忽略不需要的事件字段
4. **字段访问**: identify::Info 字段直接访问，不是方法调用
5. **Ping 行为**: libp2p ping 自动在所有连接上发送，无需手动触发
6. **离线检测**: ConnectionClosed 事件比 mDNS TTL 更快

### 最终架构

```
┌─────────────────────────────────────────────────────────────┐
│                   ManagedDiscovery                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Swarm<ManagedBehaviour>                            │   │
│  │  - mdns: 服务发现                                    │   │
│  │  - identify: 身份验证                                │   │
│  │  - ping: 自动心跳                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  连接状态跟踪                                         │   │
│  │  - active_connections: HashMap<PeerId, u32>          │   │
│  │  - health_status: HashMap<PeerId, NodeHealth>        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
                              ↓ 验证通过
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      NodeManager                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  HashMap<PeerId, VerifiedNode>                      │   │
│  │  - 存储验证通过的节点                                 │   │
│  │  - 自动清理超时节点                                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 事件流程

```
节点启动
    ↓
mDNS DiscoveryEvent::Discovered
    ↓
主动连接 (swarm.dial)
    ↓
ConnectionEstablished (增加连接计数)
    ↓
Identify Event::Received
    ↓
验证 protocol_version & agent_version
    ↓
    ├─ 验证通过 → 添加到 NodeManager
    └─ 验证失败 → 记录日志

节点离线
    ↓
ConnectionClosed (减少连接计数)
    ↓
连接数 == 0？
    ↓ 是
从 NodeManager 移除节点
```

---

## 参考资源

### libp2p 官方文档

- [libp2p 0.56.0 CHANGELOG](https://docs.rs/crate/libp2p/latest/source/CHANGELOG.md)
- [libp2p::ping::Behaviour](https://docs.rs/libp2p/latest/libp2p/ping/struct.Behaviour.html)
- [libp2p::ping::Event](https://docs.rs/libp2p/latest/libp2p/ping/struct.Event.html)
- [libp2p::identify](https://docs.rs/libp2p/latest/libp2p/identify/index.html)

### 关键 API

**SwarmBuilder 模式 (libp2p 0.56)**:
```rust
SwarmBuilder::with_existing_identity(key)
    .with_tokio()
    .with_tcp(tcp::Config::default(), noise::Config::new, yamux::Config::default)
    .with_behaviour(|key| Ok(ManagedBehaviour { /* ... */ }))
    .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
    .build()
```

**NetworkBehaviour 组合**:
```rust
#[derive(libp2p::swarm::NetworkBehaviour)]
struct ManagedBehaviour {
    mdns: mdns::tokio::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
}
```
