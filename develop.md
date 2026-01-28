# Local P2P mDNS 项目文档

## 目录

1. [项目概述](#项目概述)
2. [快速开始](#快速开始)
3. [项目结构](#项目结构)
4. [架构设计](#架构设计)
5. [核心模块](#核心模块)
6. [TUI 应用](#tui-应用)
7. [API 参考](#api-参考)
8. [配置说明](#配置说明)
9. [使用示例](#使用示例)
10. [故障排查](#故障排查)
11. [日志系统](#日志系统)
12. [Flutter 应用](#flutter-应用)

---

## 项目概述

本项目是一个基于 libp2p 的局域网 P2P 服务发现和节点管理系统，具有以下特性：

- **mDNS 服务发现**: 自动发现局域网内的 libp2p 节点
- **Identify 身份验证**: 通过协议版本和代理版本验证节点
- **用户信息交换**: 通过自定义 request_response 协议交换用户信息（设备名、昵称、头像等）
- **设备名称支持**: 支持设置友好的设备名称，便于识别
- **自过滤机制**: 自动过滤掉自己的信息，防止误加入管理器
- **Ping 心跳检测**: 自动维护节点连接健康
- **即时离线检测**: 通过连接状态跟踪快速检测节点离线
- **节点管理器**: 集中管理验证通过的节点，支持超时清理
- **事件去重**: 智能去重重复的发现和验证事件
- **日志系统**: 支持文件和控制台双重输出，按天滚动
- **TUI 图形界面**: 基于 ratatui 的现代化终端用户界面，支持三面板焦点切换
- **P2P 聊天功能**: 局域网内点对点聊天，支持一对一和一对多群聊，消息左右分栏显示

### 技术栈

| 组件 | 版本 | 用途 |
|------|------|------|
| Rust | 2021 Edition | 编程语言 |
| libp2p | 0.56.0 | P2P 网络库 |
| tokio | 1.x | 异步运行时 |
| tracing | 0.1 | 日志记录 |
| tracing-appender | 0.2 | 日志文件输出 |
| ratatui | 0.29 | TUI 框架 |
| crossterm | 0.28 | 终端后端 |

---

## 快速开始

### 安装与运行

```bash
# 克隆/进入项目目录
cd localp2p

# 运行（需要安装 Rust 1.70+）
# 需要提供设备名称作为参数
cargo run -- "我的设备"
```

### 命令行参数

```bash
# 查看帮助
cargo run -- --help

# 控制台模式运行
cargo run -- "客厅电视"
cargo run -- "卧室 NAS"
cargo run -- "我的开发机"

# TUI 模式运行
cargo run -- "客厅电视" --tui
cargo run -- "卧室 NAS" -t
```

### 运行多个实例

在局域网内运行多个实例，它们会自动发现彼此：

```bash
# 终端 1
cargo run -- "设备A"

# 终端 2（在另一台机器或同一台机器上）
cargo run -- "设备B"
```

### 预期输出

```
Local P2P mDNS 节点管理示例（带心跳）
====================================
设备名称: 设备A
✓ 后台清理任务已启动
✓ 心跳配置: 10秒间隔，3次失败离线
  注意：libp2p ping 会自动对所有已连接节点发送周期性心跳
本地 Peer ID: 12D3kooW...
协议版本: /localp2p/1.0.0
代理版本: localp2p-rust/1.0.0 (设备A)

开始扫描局域网内的对等节点...

🔍 发现节点: 12D3KooX... at /ip4/192.168.1.100/tcp/50001
   等待 identify 验证...
✅ 节点验证通过
   显示名称: 设备B (12D3KooX...)
   设备名称: 设备B
   Peer ID: 12D3KooX...
   协议版本: /localp2p/1.0.0
   代理版本: localp2p-rust/1.0.0 (设备B)
   地址: [/ip4/192.168.1.100/tcp/50001, ...]

当前验证通过的节点数: 1
```

---

## 项目结构

```
localp2p/
├── Cargo.toml              # Workspace 配置
├── develop.md              # 开发文档（本文件）
├── study.md                # 开发历史记录
├── logs/                   # 日志文件目录（自动创建）
│   └── localp2p.YYYY-MM-DD.log  # 按天滚动的日志文件
├── src/
│   ├── main.rs             # 示例程序入口
│   └── logging.rs          # 日志配置模块
└── crates/
    ├── mdns/               # mdns crate（独立库）
    │   ├── Cargo.toml      # mdns crate 配置
    │   └── src/
    │       ├── lib.rs                  # 库入口
    │       ├── config.rs               # 配置模块
    │       ├── discovery.rs            # 基础服务发现
    │       ├── publisher.rs            # 服务发布
    │       ├── node.rs                 # 节点管理
    │       ├── user_info.rs            # 用户信息协议
    │       ├── managed_discovery.rs    # 管理式服务发现（核心）
    │       └── chat/                   # 聊天模块
    │           ├── mod.rs              # 模块入口
    │           ├── message.rs          # 消息类型定义
    │           ├── traits.rs           # ChatExtension trait
    │           ├── manager.rs          # ChatManager
    │           └── codec.rs            # ChatCodec
    └── tui-app/            # TUI 应用 crate
        ├── Cargo.toml      # tui-app crate 配置
        └── src/
            ├── lib.rs                  # 库入口
            ├── app.rs                  # 主应用逻辑
            ├── event.rs                # 事件处理
            ├── ui.rs                   # UI 渲染
            └── components/
                ├── mod.rs              # 组件模块
                ├── node_list.rs        # 节点列表组件
                ├── chat_panel.rs       # 聊天面板组件
                └── file_picker.rs      # 文件选择组件（占位）
```

### Workspace 配置

```toml
[workspace]
members = ["crates/mdns", "crates/tui-app"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"
```

---

## 架构设计

### 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                      Application Layer                          │
│                    (src/main.rs 示例程序)                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    ManagedDiscovery                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Swarm<ManagedBehaviour>                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │  │
│  │  │  mDNS    │  │ Identify │  │   Ping   │  │Request  │ │  │
│  │  │  发现    │  │  验证    │  │  心跳    │  │Response │ │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    状态跟踪                                │  │
│  │  - active_connections: HashMap<PeerId, u32>               │  │
│  │  - health_status: HashMap<PeerId, NodeHealth>             │  │
│  │  - peer_user_info: HashMap<PeerId, UserInfo>              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                              │ 验证通过
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      NodeManager                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │        HashMap<PeerId, VerifiedNode>                       │  │
│  │  - 存储验证通过的节点                                       │  │
│  │  - 自动清理超时节点 (5分钟)                                 │  │
│  │  - 后台清理任务 (60秒间隔)                                  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 事件流程

```
┌────────────────────────────────────────────────────────────────┐
│                        节点发现与验证                            │
└────────────────────────────────────────────────────────────────┘

1. mDNS 发现节点
   └─> DiscoveryEvent::Discovered(peer_id, addr)
       └─> 主动连接 swarm.dial(addr)

2. 连接建立（首个连接）
   └─> ConnectionEstablished
       ├─> 增加连接计数
       └─> 发送用户信息请求（仅首个连接）

3. Identify 验证
   └─> IdentifyEvent::Received { peer_id, info, .. }
       ├─> 检查是否是自己（peer_id == local_peer_id）
       │   └─> 是 → 跳过，不添加到管理器（自过滤）
       ├─> 验证 protocol_version
       ├─> 验证 agent_version（包括设备名称解析）
       └─> 验证通过 → 添加到 NodeManager

4. 用户信息交换（request_response）
   └─> 用户信息请求
       └─> 返回本地 UserInfo（设备名、昵称、状态等）
       └─> 存储到 peer_user_info（首次收到才触发事件）

┌────────────────────────────────────────────────────────────────┐
│                        节点离线检测                              │
└────────────────────────────────────────────────────────────────┘

1. 对方程序关闭
   └─> libp2p 检测到连接断开

2. ConnectionClosed 事件
   └─> 减少连接计数
       └─> 计数为 0？
           └─> 是 → 立即判定离线，从管理器移除
```

### 事件去重机制

由于多网卡环境会产生多个连接，系统实现了智能去重：

1. **Identify 验证去重**
   - 首次验证：记录日志并返回 `Verified` 事件
   - 后续验证：静默更新，不返回事件

2. **用户信息去重**
   - 首次收到：记录日志并返回 `UserInfoReceived` 事件
   - 后续收到：静默更新，不返回事件

3. **用户信息请求去重**
   - 仅在首个连接建立时发送请求
   - 后续连接不重复发送

这样避免了一个节点被多次发现导致的事件泛滥。

### 自过滤机制

由于 mDNS 是广播协议，每个节点都会收到包括自己在内的广播。为了防止节点将自己加入管理器，系统实现了自过滤机制：

```rust
// 在 identify 验证时检查
if peer_id == self.local_peer_id() {
    tracing::debug!("跳过自己: {}", peer_id);
    continue;  // 不添加到管理器
}
```

**工作原理**：
1. 每个节点有唯一的 Peer ID（由密钥对生成）
2. 在 identify 验证事件中，比较对方 Peer ID 和本地 Peer ID
3. 如果相同，说明是自己收到了自己的 mDNS 广播，跳过处理
4. 只有其他节点的信息才会被添加到节点管理器

---

## 核心模块

### 1. managed_discovery.rs - 管理式服务发现（核心模块）

#### ManagedDiscovery

```rust
pub struct ManagedDiscovery {
    swarm: Swarm<ManagedBehaviour>,
    node_manager: Arc<NodeManager>,
    protocol_version: String,
    agent_version: String,
    health_status: HashMap<PeerId, NodeHealth>,
    health_config: HealthCheckConfig,
    active_connections: HashMap<PeerId, u32>,
}
```

**职责**:
- 集成 mDNS + identify + ping 三种协议
- 跟踪节点连接状态
- 维护节点健康信息
- 处理所有发现和验证事件

**主要方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `new(node_manager, addrs, health_config)` | 创建发现器 | `Result<Self>` |
| `run()` | 运行发现服务 | `Result<DiscoveryEvent>` |
| `local_peer_id()` | 获取本地 Peer ID | `PeerId` |
| `node_manager()` | 获取节点管理器 | `Arc<NodeManager>` |
| `get_health(peer_id)` | 获取节点健康信息 | `Option<&NodeHealth>` |

#### ManagedBehaviour

```rust
#[derive(libp2p::swarm::NetworkBehaviour)]
struct ManagedBehaviour {
    mdns: mdns::tokio::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
    request_response: request_response::Behaviour<user_info::UserInfoCodec>,
}
```

**协议说明**:

| 协议 | 用途 | 配置 |
|------|------|------|
| **mdns** | 局域网服务发现 | `mdns::Config::default()` |
| **identify** | 节点身份验证 | 30秒间隔更新 |
| **ping** | 自动心跳检测 | 默认 15秒间隔 |
| **request_response** | 用户信息交换 | 自定义 UserInfoCodec |

#### DiscoveryEvent

```rust
pub enum DiscoveryEvent {
    Discovered(PeerId, Multiaddr),        // 通过 mDNS 发现节点
    Expired(PeerId),                       // 节点 mDNS 记录过期
    Verified(PeerId),                      // 节点验证通过
    VerificationFailed(PeerId, String),    // 节点验证失败
    NodeRecovered(PeerId, Duration),       // 节点恢复健康
    NodeOffline(PeerId),                   // 节点离线
    UserInfoReceived(PeerId, UserInfo),    // 收到用户信息（新增）
}
```

### 2. node.rs - 节点管理模块

#### VerifiedNode

```rust
pub struct VerifiedNode {
    pub peer_id: PeerId,
    pub addresses: Vec<Multiaddr>,
    pub protocol_version: String,
    pub agent_version: String,
    pub name: Option<String>,              // 设备名称（从 agent_version 解析）
    pub first_seen: Instant,
    pub last_seen: Instant,
    pub attributes: HashMap<String, String>,
}
```

**方法**:

| 方法 | 说明 |
|------|------|
| `new(peer_id, addrs, proto, agent)` | 创建新节点（自动解析设备名称） |
| `display_name()` | 获取显示名称（优先使用设备名称） |
| `update_last_seen()` | 更新最后活跃时间 |
| `is_timeout(duration)` | 检查是否超时 |
| `age()` | 获取存活时长 |
| `idle_time()` | 获取空闲时长 |

**设备名称格式**:

设备名称通过 `agent_version` 传递，格式为：`localp2p-rust/1.0.0 (设备名称)`

示例：
- `localp2p-rust/1.0.0 (客厅电视)` → 设备名称: `客厅电视`
- `localp2p-rust/1.0.0` → 设备名称: `None`

#### NodeManager

```rust
pub struct NodeManager {
    nodes: RwLock<HashMap<PeerId, VerifiedNode>>,
    config: NodeManagerConfig,
}
```

**方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `new(config)` | 创建节点管理器 | `Self` |
| `add_or_update_node(node)` | 添加/更新节点 | `()` |
| `remove_node(peer_id)` | 移除节点 | `Option<VerifiedNode>` |
| `get_node(peer_id)` | 获取节点信息 | `Option<VerifiedNode>` |
| `is_node_verified(peer_id)` | 检查是否已验证 | `bool` |
| `list_nodes()` | 列出所有节点 | `Vec<VerifiedNode>` |
| `node_count()` | 获取节点数量 | `usize` |
| `cleanup_inactive()` | 清理超时节点 | `Vec<PeerId>` |
| `spawn_cleanup_task()` | 启动后台清理 | `JoinHandle<()>` |
| `verify_node_info(proto, agent)` | 验证节点信息 | `Result<()>` |

#### NodeManagerConfig

```rust
pub struct NodeManagerConfig {
    pub node_timeout: Duration,            // 节点超时时间
    pub cleanup_interval: Duration,         // 清理间隔
    pub expected_protocol_version: String,  // 期望的协议版本
    pub expected_agent_prefix: Option<String>, // 期望的代理版本前缀
    pub device_name: Option<String>,        // 本设备名称
}
```

**默认值**:

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `node_timeout` | 300 秒 (5分钟) | 超时未活跃则清理 |
| `cleanup_interval` | 60 秒 (1分钟) | 清理任务执行间隔 |
| `expected_protocol_version` | `/localp2p/1.0.0` | 必须完全匹配 |
| `expected_agent_prefix` | `Some("localp2p-rust/")` | 前缀匹配即可 |
| `device_name` | `None` | 本设备名称（包含在 agent_version 中） |

**Builder 方法**:

```rust
NodeManagerConfig::new()
    .with_protocol_version("/localp2p/1.0.0".to_string())
    .with_agent_prefix(Some("localp2p-rust/".to_string()))
    .with_device_name("我的设备".to_string())  // 设置设备名称
    .with_node_timeout(Duration::from_secs(300))
    .with_cleanup_interval(Duration::from_secs(60));

// build_agent_version() 会根据 device_name 生成:
// "localp2p-rust/1.0.0 (我的设备)" 或 "localp2p-rust/1.0.0"
```

### 3. 健康检查类型

#### NodeHealth

```rust
pub struct NodeHealth {
    pub consecutive_failures: u32,      // 连续失败次数
    pub last_success: Option<Instant>,  // 最后成功时间
    pub last_failure: Option<Instant>,  // 最后失败时间
    pub average_rtt: Option<Duration>,  // 平均往返时间
    pub status: HealthStatus,           // 当前状态
}
```

#### HealthStatus

```rust
pub enum HealthStatus {
    Unknown,    // 未知（尚未检查）
    Healthy,    // 健康（最近有心跳响应）
    Unhealthy,  // 不健康（连续多次失败）
}
```

#### HealthCheckConfig

```rust
pub struct HealthCheckConfig {
    pub heartbeat_interval: Duration,  // 心跳间隔（显示用）
    pub max_failures: u32,             // 连续失败阈值
}
```

**注意**: libp2p ping 自动管理心跳间隔（默认 15 秒），此配置仅用于失败阈值判断。

### 4. user_info.rs - 用户信息交换协议

#### UserInfo

```rust
pub struct UserInfo {
    pub device_name: String,              // 设备名称（如："我的电脑"）
    pub nickname: Option<String>,          // 用户昵称（可选）
    pub avatar_url: Option<String>,        // 头像 URL（可选）
    pub status: Option<String>,            // 用户状态（如："在线"、"忙碌"）
    pub custom_data: HashMap<String, String>,  // 自定义扩展数据
}
```

**方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `new(device_name)` | 创建用户信息 | `Self` |
| `with_nickname(nickname)` | 设置昵称 | `Self` |
| `with_avatar_url(url)` | 设置头像 URL | `Self` |
| `with_status(status)` | 设置状态 | `Self` |
| `with_custom_data(key, value)` | 添加自定义数据 | `Self` |
| `display_name()` | 获取显示名称（优先昵称） | `String` |

#### UserInfoCodec

```rust
pub struct UserInfoCodec;
```

实现了 `request_response::Codec` trait，使用 JSON 序列化和长度前缀分帧。

**特点**:
- 使用 async_trait 支持异步读写
- JSON 序列化（serde_json）
- u32 big endian 长度前缀
- 自动处理请求/响应

**协议格式**:
```
[4 bytes: 长度][JSON 数据: UserInfo/UserInfoRequest]
```

### 5. identity.rs - 密钥持久化模块

密钥持久化模块提供密钥对的保存和加载功能，用于固定 Peer ID。

#### IdentityManager

```rust
pub struct IdentityManager;
```

**主要方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `load_or_none(path)` | 从文件加载密钥对，不存在返回 None | `Result<Option<Keypair>>` |
| `generate_and_save(path)` | 生成新的 ed25519 密钥对并保存 | `Result<Keypair>` |
| `load_or_generate(path)` | 加载或生成密钥对（便捷方法） | `Result<Keypair>` |
| `delete(path)` | 删除密钥文件 | `Result<()>` |

#### 使用示例

```rust
use mdns::IdentityManager;
use std::path::Path;

// 首次启动：生成新密钥对并保存
let keypair = IdentityManager::load_or_generate(Path::new("/path/to/identity.key"))?;
let peer_id = keypair.public().to_peer_id();

// 后续启动：从文件加载相同的密钥对
let keypair = IdentityManager::load_or_generate(Path::new("/path/to/identity.key"))?;
let peer_id = keypair.public().to_peer_id();
// peer_id 将与首次启动时相同
```

#### 密钥格式

- **算法**: ed25519
- **编码**: libp2p Protobuf 格式
- **文件权限**: 0600 (Unix, 仅所有者可读写)
- **特点**: 使用 libp2p 的 `to_protobuf_encoding()` 和 `from_protobuf_encoding()` 进行序列化

#### 在 ManagedDiscovery 中使用

```rust
// 创建发现器并传入密钥对
let discovery = ManagedDiscovery::new(
    node_manager,
    listen_addresses,
    health_config,
    user_info,
    Some(keypair),  // 使用持久化密钥对
).await?;

// 或生成临时密钥对（每次启动会变化）
let discovery = ManagedDiscovery::new(
    node_manager,
    listen_addresses,
    health_config,
    user_info,
    None,  // 生成临时密钥对
).await?;
```

### 6. chat/ - 聊天模块

聊天模块提供局域网内的点对点聊天功能，支持一对一和一对多群聊。

#### ChatMessage - 聊天消息类型

```rust
pub enum ChatMessage {
    Text(TextMessage),           // 文本消息
    TypingIndicator(TypingIndicator),  // 正在输入提示
    Ack(MessageAck),              // 消息确认
}
```

#### TextMessage - 文本消息

```rust
pub struct TextMessage {
    pub id: String,               // 消息唯一 ID（UUID）
    pub sender_peer_id: String,   // 发送者的 Peer ID
    pub content: String,          // 消息内容
    pub timestamp: i64,           // Unix 时间戳（毫秒）
    pub reply_to: Option<String>, // 回复的消息 ID（可选）
}
```

**方法**:
- `ChatMessage::text(content)` - 创建文本消息
- `with_sender(peer_id)` - 设置发送者 Peer ID
- `with_reply_to(message_id)` - 设置为回复消息

#### ChatManager - 聊天管理器

```rust
pub struct ChatManager {
    node_manager: Arc<NodeManager>,
    local_peer_id: PeerId,
    sessions: RwLock<HashMap<PeerId, ChatSession>>,
    event_tx: mpsc::UnboundedSender<ChatEvent>,
}
```

**主要方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `send(target, message)` | 发送消息给单个节点 | `Result<(), ChatError>` |
| `broadcast(targets, message)` | 广播消息给多个节点 | `Result<(), ChatError>` |
| `handle_received_message(from, message)` | 处理收到的消息 | `()` |
| `get_history(peer_id)` | 获取会话的消息历史 | `Vec<ChatMessage>` |
| `available_peers()` | 获取可聊天节点 | `Vec<VerifiedNode>` |

#### ChatExtension - 聊天扩展 Trait

为 `ManagedDiscovery` 提供可选的聊天能力扩展。

```rust
#[async_trait::async_trait]
pub trait ChatExtension {
    /// 启用聊天功能
    async fn enable_chat(&mut self) -> Result<(), ChatError>;

    /// 发送消息给指定节点
    async fn send_message(&mut self, target: PeerId, message: ChatMessage) -> Result<(), ChatError>;

    /// 广播消息给多个节点
    async fn broadcast_message(&mut self, targets: Vec<PeerId>, message: ChatMessage) -> Result<(), ChatError>;

    /// 获取聊天管理器
    fn chat_manager(&self) -> Option<Arc<ChatManager>>;
}
```

**使用示例**:

```rust
use mdns::{ManagedDiscovery, ChatExtension, ChatMessage};

// 启用聊天功能
discovery.enable_chat().await?;

// 发送消息
let peer_id: PeerId = "12D3KooW...".parse()?;
let message = ChatMessage::text("Hello!".to_string());
discovery.send_message(peer_id, message).await?;

// 广播消息（一对多）
let targets = vec![peer_id1, peer_id2];
discovery.broadcast_message(targets, message).await?;
```

#### ChatEvent - 聊天事件

```rust
pub enum ChatEvent {
    MessageReceived { from: PeerId, message: ChatMessage },
    MessageSent { to: PeerId, message_id: String },
    MessageAcknowledged { from: PeerId, message_id: String },
    PeerTyping { from: PeerId, is_typing: bool },
    MessageFailed { to: PeerId, message_id: String, error: String },
    SessionEstablished { peer_id: PeerId },
    SessionClosed { peer_id: PeerId },
}
```

---

## TUI 应用

### TUI 界面布局

TUI 应用采用三面板布局，同时显示三个功能区域：

```
┌─────────────────────────────────────────────────────────┐
│ Header: Local P2P - 设备名称                            │
├─────────────┬──────────────────────────┬────────────────┤
│ [1] 设备列表 │ [2] 聊天                 │ [3] 文件选择   │
│ (上列表)    │                          │                │
│ (下信息)    │                          │                │
│             │                          │                │
├─────────────┴──────────────────────────┴────────────────┤
│ [Tab] 切换焦点 | 当前焦点: 设备列表 | [q] 退出           │
└─────────────────────────────────────────────────────────┘
```

### 面板功能

| 面板 | 功能 | 操作 |
|------|------|------|
| **[1] 设备列表** | 显示已验证的节点，支持单选/多选 | ↑↓ 选择，Enter 确认，Space 多选 |
| **[2] 聊天** | 与选中节点进行聊天，消息左右分栏显示 | 在面板1选择后切换到面板2即可输入消息 |
| **[3] 文件选择** | 选择文件分享给选中节点（占位） | 待实现 |

### 焦点切换

- 按 `Tab` 键在三个面板间切换焦点
- 焦点面板显示绿色边框和 `*` 标记
- 非焦点面板显示灰色边框
- 方向键仅在焦点在面板1时有效

### TuiApp 结构

```rust
pub struct TuiApp {
    node_manager: Arc<NodeManager>,
    node_list_state: NodeListState,
    user_info_map: HashMap<PeerId, UserInfo>,
    device_name: String,
    local_peer_id: PeerId,
    current_tab: AppTab,      // 当前焦点面板
    running: bool,
}
```

### AppTab 枚举

```rust
pub enum AppTab {
    Panel1,     // 设备列表
    Panel2,     // 聊天
    Panel3,     // 文件选择
}
```

### 组件说明

#### NodeList - 节点列表组件

```rust
pub struct NodeList<'a> {
    pub state: &'a NodeListState,
    pub title: String,
    pub detailed: bool,
    pub border_style: Style,
}
```

**方法**:
- `new(state)` - 创建列表
- `title(title)` - 设置标题
- `detailed(bool)` - 是否显示详细信息
- `border_style(style)` - 设置边框样式

#### ChatComponent - 聊天组件（占位）

```rust
pub struct ChatComponent<'a> {
    pub message: &'a str,
    pub title: String,
    pub border_style: Style,
}
```

#### FilePickerComponent - 文件选择组件（占位）

```rust
pub struct FilePickerComponent<'a> {
    pub message: &'a str,
    pub title: String,
    pub border_style: Style,
}
```

### 运行 TUI 模式

```bash
# 启动 TUI 界面
cargo run -- "设备名称" --tui

# 或使用简写
cargo run -- "设备名称" -t
```

### TUI 依赖

```toml
[dependencies]
# 依赖 mdns crate
mdns = { path = "../mdns" }

# libp2p
libp2p = { version = "0.56", features = ["identify"] }

# TUI 相关依赖
ratatui = "0.29"
crossterm = { version = "0.28", features = ["event-stream"] }

# 异步运行时
tokio = { version = "1", features = ["full"] }
futures = "0.3"

# 日志
tracing = "0.1"

# 其他依赖
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
```

---

## API 参考

### lib.rs 公共导出

```rust
// 节点管理
pub use node::{VerifiedNode, NodeManager, NodeManagerConfig};

// 用户信息
pub use user_info::UserInfo;

// 管理式服务发现
pub use managed_discovery::{
    ManagedDiscovery,
    DiscoveryEvent as ManagedDiscoveryEvent,
    NodeHealth,
    HealthStatus,
    HealthCheckConfig,
};

// 基础类型（可选使用）
pub use config::{MdnsConfig, ServiceInfo};
pub use discovery::{MdnsDiscovery, DiscoveredPeer, DiscoveredEvent};
pub use publisher::MdnsPublisher;

// 错误类型
pub enum MdnsError {
    Io(std::io::Error),
    SwarmBuild(String),
    Stopped,
}
```

### 依赖说明

#### mdns crate 依赖

```toml
[dependencies]
libp2p = { version = "0.56.0", features = [
    "mdns",             # mDNS 服务发现
    "tokio",            # 异步运行时
    "tcp",              # TCP 传输
    "noise",            # 加密协议
    "yamux",            # 多路复用
    "identify",         # 身份验证
    "ping",             # 心跳检测
    "macros",           # Behaviour 组合宏
    "request-response", # 请求-响应协议
    "cbor",             # CBOR 编码支持
] }
tokio = { version = "1", features = ["full"] }
futures = "0.3"
thiserror = "2.0"
tracing = "0.1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"      # JSON 序列化
async-trait = "0.1"     # async trait
```

#### 主项目依赖

```toml
[dependencies]
mdns = { path = "crates/mdns" }
tui-app = { path = "crates/tui-app" }
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
tracing-subscriber = "0.3"
tracing-appender = "0.2"  # 日志文件输出
```

---

## 配置说明

### 默认配置汇总

| 配置项 | 默认值 | 位置 | 说明 |
|--------|--------|------|------|
| 节点超时 | 300秒 | NodeManagerConfig | 超时未活跃则清理 |
| 清理间隔 | 60秒 | NodeManagerConfig | 后台清理任务间隔 |
| 协议版本 | `/localp2p/1.0.0` | NodeManagerConfig | 必须完全匹配 |
| 代理前缀 | `localp2p-rust/` | NodeManagerConfig | 前缀匹配即可 |
| Ping 失败阈值 | 3次 | HealthCheckConfig | 连续失败后标记不健康 |
| Identify 更新间隔 | 30秒 | identify::Config | 定期刷新节点信息 |

### 环境适配建议

| 环境 | node_timeout | cleanup_interval | 说明 |
|------|--------------|------------------|------|
| 开发 | 60-120秒 | 30秒 | 快速测试超时逻辑 |
| 测试 | 180秒 | 60秒 | 平衡速度和稳定性 |
| 生产 | 300-600秒 | 60秒 | 标准配置 |

---

## 使用示例

### 示例 1: 基础用法（带用户信息交换）

```rust
use mdns::{ManagedDiscovery, NodeManager, NodeManagerConfig, ManagedDiscoveryEvent, UserInfo};
use std::sync::Arc;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 初始化日志（输出到文件和控制台）
    logging::init_logging_with_console(logging::LogLevel::Info)?;

    // 从命令行获取设备名称
    let device_name = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "未命名设备".to_string());

    // 创建用户信息
    let user_info = UserInfo::new(device_name.clone())
        .with_status("在线".to_string());

    // 创建节点管理器
    let config = NodeManagerConfig::new()
        .with_protocol_version("/localp2p/1.0.0".to_string())
        .with_agent_prefix(Some("localp2p-rust/".to_string()))
        .with_device_name(device_name);

    let node_manager = Arc::new(NodeManager::new(config));
    node_manager.clone().spawn_cleanup_task();

    // 创建发现器（传入用户信息）
    let health_config = HealthCheckConfig {
        heartbeat_interval: Duration::from_secs(10),
        max_failures: 3,
    };

    let mut discovery = ManagedDiscovery::new(
        node_manager,
        vec!["/ip4/0.0.0.0/tcp/0".parse()?],
        health_config,
        user_info,
    ).await?;

    println!("本地 Peer ID: {}", discovery.local_peer_id());

    // 处理事件
    loop {
        match discovery.run().await? {
            ManagedDiscoveryEvent::Verified(peer_id) => {
                println!("✅ 节点验证通过: {}", peer_id);
            }
            ManagedDiscoveryEvent::UserInfoReceived(peer_id, user_info) => {
                println!("📝 收到用户信息: {}", user_info.display_name());
                println!("   设备名: {}", user_info.device_name);
                if let Some(ref status) = user_info.status {
                    println!("   状态: {}", status);
                }
            }
            ManagedDiscoveryEvent::NodeOffline(peer_id) => {
                println!("💔 节点离线: {}", peer_id);
            }
            _ => {}
        }
    }
}
```

### 示例 2: 自定义验证规则

```rust
let config = NodeManagerConfig::new()
    .with_protocol_version("/my-app/v2".to_string())
    .with_agent_prefix(Some("my-app-rust/"))
    .with_device_name("我的服务器".to_string())  // 设置设备名称
    .with_node_timeout(Duration::from_secs(600));  // 10分钟超时
```

### 示例 3: 查询节点状态

```rust
// 检查节点是否存在
if node_manager.is_node_verified(&peer_id).await {
    if let Some(node) = node_manager.get_node(&peer_id).await {
        println!("存活时间: {:?}", node.age());
        println!("空闲时间: {:?}", node.idle_time());
        println!("地址: {:?}", node.addresses);
    }
}

// 列出所有节点
let nodes = node_manager.list_nodes().await;
println!("当前节点数: {}", nodes.len());
for node in nodes {
    println!("  - {}", node.peer_id);
}
```

### 示例 4: 手动清理

```rust
// 清理超时节点
let removed = node_manager.cleanup_inactive().await;
for peer_id in removed {
    println!("移除超时节点: {}", peer_id);
}

// 手动移除特定节点
if let Some(node) = node_manager.remove_node(&peer_id).await {
    println!("已移除节点: {}", node.peer_id);
}
```

### 示例 5: 健康状态查询

```rust
// 获取节点健康信息
if let Some(health) = discovery.get_health(&peer_id) {
    println!("状态: {:?}", health.status);
    println!("连续失败: {}", health.consecutive_failures);
    if let Some(rtt) = health.average_rtt {
        println!("平均 RTT: {:?}", rtt);
    }
}
```

### 示例 6: TUI 模式运行

```bash
# 启动 TUI 界面
cargo run -- "我的设备" --tui
```

**TUI 操作说明**:
- `Tab` - 切换焦点到下一个面板
- `↑↓` - 在设备列表中移动光标（仅在面板1有效）
- `Enter` - 确认选择（仅在面板1有效）
- `Space` - 多选切换（仅在面板1有效）
- `q` 或 `Ctrl+C` - 退出

**面板说明**:
- 面板1（设备列表）：显示已验证的节点，上部分显示列表，下部分显示当前选中节点的详细信息
- 面板2（聊天）：与选中节点进行聊天（占位，功能待实现）
- 面板3（文件选择）：选择文件分享给选中节点（占位，功能待实现）

---

## 故障排查

### 问题 1: 无法发现其他节点

**可能原因**:
1. 防火墙阻止 mDNS 流量（UDP 5353）
2. 节点不在同一局域网
3. 协议版本或代理前缀不匹配

**解决方法**:

```bash
# Linux: 允许 mDNS 流量
sudo ufw allow 5353/udp

# 或使用 iptables
sudo iptables -A INPUT -p udp --dport 5353 -j ACCEPT

# Windows: 允许应用通过防火墙
# macOS: 通常默认允许 mDNS
```

**验证配置**:
```rust
// 确保所有节点使用相同配置
let config = NodeManagerConfig::new()
    .with_protocol_version("/localp2p/1.0.0".to_string())  // 必须相同
    .with_agent_prefix(Some("localp2p-rust/"));            // 前缀必须相同
```

### 问题 2: 节点验证失败

**日志**:
```
✗ 节点 12D3... 验证失败: 协议版本不匹配
```

**解决方法**:

检查所有节点的配置是否一致：
```rust
// 所有节点必须使用相同的协议版本
.with_protocol_version("/localp2p/1.0.0".to_string())

// 所有节点必须使用相同的代理前缀
.with_agent_prefix(Some("localp2p-rust/".to_string()))
```

### 问题 3: IPv6 地址错误

**错误**:
```
Error: UnknownProtocolString("ip6::")
```

**原因**: IPv6 通配符地址格式错误

**解决方法**:

```rust
// 移除 IPv6 监听
let listen_addresses = vec![
    "/ip4/0.0.0.0/tcp/0".parse()?,
];

// 或使用正确的 IPv6 格式（三个斜杠）
let listen_addresses = vec![
    "/ip4/0.0.0.0/tcp/0".parse()?,
    "/ip6:///tcp/0".parse()?,
];
```

### 问题 4: 节点被频繁清理

**原因**: `node_timeout` 设置过短

**解决方法**:

```rust
.with_node_timeout(Duration::from_secs(600))  // 增加到 10 分钟
```

### 问题 5: 编译错误

**常见错误**:

| 错误 | 原因 | 解决方法 |
|------|------|----------|
| `NetworkBehaviour not found` | 缺少 macros feature | 添加 `"macros"` 到 features |
| `with_keep_alive not found` | API 已变更 | 使用 `Config::default()` |
| 模式匹配错误 | Event 类型变更 | 查看最新 API 文档 |

**确保依赖版本正确**:
```toml
libp2p = { version = "0.56.0", features = ["mdns", "tokio", "tcp", "noise", "yamux", "identify", "ping", "macros"] }
```

---

## 常见问题

### Q: 如何设置设备名称？

A: 通过 `UserInfo::new()` 创建用户信息，然后传递给 `ManagedDiscovery::new()`。系统会通过 request_response 协议自动交换用户信息。

### Q: 为什么要自过滤？

A: mDNS 是广播协议，每个节点都会收到包括自己在内的广播。如果没有自过滤，节点会将自己也加入管理器，导致显示错误。自过滤通过比较 Peer ID 来跳过自己的信息。

### Q: 为什么有重复的发现和验证事件？

A: 多网卡环境下，同一节点可能在多个网络接口上被多次发现。系统已实现事件去重机制，确保每个节点只触发一次 `Verified` 和 `UserInfoReceived` 事件。

### Q: mDNS 过期需要多久？

A: mDNS 记录的 TTL 通常为 2-5 分钟，但我们使用 `ConnectionClosed` 事件进行即时检测，无需等待 TTL 过期。

### Q: Ping 心跳间隔是多少？

A: libp2p ping 默认 15 秒发送一次，这是 libp2p 内部管理，无需手动配置。

### Q: 如何调整离线检测速度？

A: 离线检测通过 `ConnectionClosed` 事件即时完成，无需调整。如需调整失败阈值，修改 `HealthCheckConfig.max_failures`。

### Q: 日志文件存放在哪里？

A: 日志文件默认存放在 `logs/` 目录，文件名格式为 `localp2p.YYYY-MM-DD.log`，按天自动滚动。

### Q: 如何只输出日志到文件？

A: 使用 `logging::init_logging()` 或 `logging::init_logging_with_level()`，这些函数只会输出到文件，不会输出到控制台。

### Q: 支持跨网段发现吗？

A: mDNS 仅支持同一局域网（L2 网段）。如需跨网段，需要配置 mDNS 反射器或使用其他发现机制。

### Q: 如何验证节点是否真的在线？

A: 系统使用三种方式综合判断：
1. libp2p 自动 ping（15 秒间隔）
2. 连接状态跟踪（即时检测）
3. 节点管理器超时清理（5 分钟）

---

## Flutter 应用

项目包含一个基于 Flutter 的跨平台 GUI 应用，通过 FFI 与 Rust 核心库交互。

### 项目结构

```
localp2p/
├── app/                          # Flutter 应用
│   ├── lib/
│   │   ├── main.dart            # 主程序入口
│   │   └── native/
│   │       └── p2p_ffi.dart      # FFI 绑定层
│   ├── pubspec.yaml              # 依赖配置
│   ├── linux/                   # Linux 平台
│   ├── android/                 # Android 平台
│   ├── macos/                   # macOS 平台
│   └── windows/                 # Windows 平台
└── crates/
    └── ffi/                     # Rust FFI 层
```

### 功能特性

| 功能 | 说明 |
|------|------|
| 节点发现 | 自动扫描局域网内的 P2P 节点 |
| 实时聊天 | 与发现的节点进行点对点聊天 |
| 消息历史 | 显示聊天记录，支持左右分栏 |
| 设备名称管理 | 首次启动自动生成随机设备名称并持久化 |
| Peer ID 固定 | 使用持久化密钥对，确保重启后 Peer ID 不变 |
| Material Design 3 | 现代化 UI 设计 |
| 跨平台 | 支持 Linux、macOS、Windows、Android |

### 设备名称和 Peer ID 持久化

Flutter 应用实现了以下持久化机制：

#### 1. 设备名称持久化

**首次启动**：
- 自动生成随机设备名称（如"快乐熊猫123"）
- 保存到 SharedPreferences
- 后续启动使用已保存的名称

**实现位置**：`lib/services/storage_service.dart`

```dart
class StorageService {
  static const String _keyDeviceName = 'device_name';

  Future<String> getDeviceName() async {
    String? deviceName = _prefs!.getString(_keyDeviceName);

    if (deviceName == null || deviceName.isEmpty) {
      // 首次启动，生成随机设备名称
      deviceName = _generateRandomDeviceName();
      await setDeviceName(deviceName);
    }

    return deviceName;
  }

  String _generateRandomDeviceName() {
    final adjectives = ['快乐', '幸运', '快速', ...];
    final nouns = ['熊猫', '手机', '电脑', ...];
    final random = Random();
    final adjective = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    final number = random.nextInt(1000);

    return '$adjective$noun$number';
  }
}
```

#### 2. Peer ID 持久化

**首次启动**：
- 生成新的 ed25519 密钥对
- 保存到 `{应用文档目录}/identity.key`
- 使用该密钥对生成 Peer ID

**后续启动**：
- 从文件加载已保存的密钥对
- 使用相同的密钥对生成 Peer ID
- Peer ID 保持不变

**Rust 端实现**：`crates/mdns/src/identity.rs`

**Flutter 端调用**：`lib/screens/home_screen.dart`

```dart
// 获取应用文档目录
final appDocDir = await getApplicationDocumentsDirectory();
final identityPath = '${appDocDir.path}/identity.key';

// 创建 P2P 配置
final config = P2PInitConfig(
  deviceName: deviceName,
  identityPath: identityPath,  // 密钥文件路径
);

await P2PManager.instance.init(config);
```

**Rust 端处理**：`crates/ffi/src/lib.rs`

```rust
pub fn internal_init(device_name: String, identity_path: String) -> Result<(), String> {
    let identity = if !identity_path.is_empty() {
        match IdentityManager::load_or_generate(Path::new(&identity_path)) {
            Ok(keypair) => Some(keypair),
            Err(e) => {
                tracing::warn!("密钥对加载失败，将生成临时密钥对: {}", e);
                None
            }
        }
    } else {
        None
    };

    // 创建发现器，传入密钥对
    ManagedDiscovery::new(
        node_manager,
        listen_addresses,
        health_config,
        user_info,
        identity,
    ).await?;
}
```

#### 3. 初始化顺序修复

修复了服务初始化的竞态条件问题：

**修改前**（有问题）：
```dart
@override
void initState() {
  super.initState();
  _initServices();  // ❌ 没有 await
  _initP2P();       // ❌ 没有 await
}
```

**修改后**（正确）：
```dart
@override
void initState() {
  super.initState();
  _initialize();  // ✅ 正确顺序
}

Future<void> _initialize() async {
  await _initServices();  // ✅ 先初始化存储服务
  await _initP2P();       // ✅ 再初始化 P2P
}
```

这确保了 `StorageService` 在 `P2PManager` 使用前完成初始化。

#### 4. 应用恢复状态同步

修复了应用从后台恢复时的状态同步问题：

```dart
Future<void> _syncP2PState() async {
  if (P2PManager.instance.isInitialized) {
    // ✅ 从存储服务获取设备名称（确保使用正确的名称）
    final deviceName = await StorageService.instance.getDeviceName();
    final localPeerId = P2PManager.instance.getLocalPeerId();

    setState(() {
      _deviceName = deviceName;  // 使用持久化的设备名称
      _localPeerId = localPeerId;
    });
  }
}
```

### 项目结构

### 构建和运行

#### 1. 编译 Rust 库

```bash
# 编译 Rust FFI 库
cargo build -p localp2p-ffi --release

# 输出文件位置
# Linux: target/release/liblocalp2p_ffi.so
# macOS: target/release/liblocalp2p_ffi.dylib
# Windows: target/release/localp2p_ffi.dll
```

#### 2. 复制库文件到 Flutter 项目

```bash
# Linux
cp target/release/liblocalp2p_ffi.so app/linux/

# macOS
cp target/release/liblocalp2p_ffi.dylib app/macos/

# Windows
cp target/release/localp2p_ffi.dll app/windows/

# Android (需要交叉编译)
cp target/aarch64-linux-android/release/liblocalp2p_ffi.so app/android/src/main/jniLibs/arm64-v8a/
```

#### 3. 运行 Flutter 应用

```bash
cd app

# 安装依赖
flutter pub get

# 运行应用（Linux）
flutter run -d linux

# 运行应用（macOS）
flutter run -d macos

# 运行应用（Windows）
flutter run -d windows

# 运行应用（Android）
flutter run -d android
```

### 界面布局

```
┌─────────────────────────────────────────────────────────┐
│ Header: Local P2P - 设备名称                    [刷新] │
├─────────────────────────────────────────────────────────┤
│                    节点列表 (1/3)                      │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 📱 设备A                          💬            │ │
│  │ 📱 设备B                          💬            │ │
│  │ 📱 设备C                          💬            │ │
│  └───────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│                    聊天消息 (2/3)                      │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 设备A: 你好！                                   │ │
│  │                                    我很好！      │ │
│  │ 设备B: 有人吗？                                 │ │
│  └───────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ [输入消息...]                                [发送]   │
└─────────────────────────────────────────────────────────┘
```

### Dart FFI 绑定

FFI 绑定位于 `lib/native/p2p_ffi.dart`，包含以下组件：

#### 主要类型

| 类型 | 说明 |
|------|------|
| `P2PService` | P2P 服务主类 |
| `P2PHandle` | P2P 句柄 |
| `P2PEventData` | 事件数据结构 |
| `NodeInfoData` | 节点信息数据类 |
| `P2PEvent` | 事件基类 |

#### 事件类型

| 事件 | 说明 |
|------|------|
| `NodeDiscoveredEvent` | 发现新节点 |
| `NodeVerifiedEvent` | 节点验证通过 |
| `NodeOfflineEvent` | 节点离线 |
| `MessageReceivedEvent` | 收到消息 |
| `MessageSentEvent` | 消息已发送 |

#### 使用示例

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'native/p2p_ffi.dart';

// 创建 P2P 服务
final lib = ffi.DynamicLibrary.open(_getLibraryPath());
final p2p = P2PService(lib);

// 初始化
p2p.init('Flutter Device');

// 启动服务
p2p.start();

// 监听事件
p2p.eventStream.listen((event) {
  if (event is NodeVerifiedEvent) {
    print('节点验证通过: ${event.peerId}');
  } else if (event is MessageReceivedEvent) {
    print('收到消息: ${event.message}');
  }
});

// 发送消息
p2p.sendMessage(targetPeerId, 'Hello!');

// 清理资源
p2p.cleanup();
```

### 事件传输机制（flutter_rust_bridge Stream 模式）

项目使用 **flutter_rust_bridge (FRB)** 的 **Stream 模式** 实现 Rust 后台线程到 Flutter UI 线程的事件推送，相比传统的轮询模式具有更低的延迟和更好的性能。

#### 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                         Rust 后台线程                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Discovery/Chat Event Source                  │  │
│  │  - mDNS 发现事件                                         │  │
│  │  - 节点验证事件                                         │  │
│  │  - 消息收发事件                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↓                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              send_event_to_stream(event)                  │  │
│  │  - 将事件推送到 StreamSink                               │  │
│  │  - 同时推送到队列（向后兼容）                            │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    flutter_rust_bridge                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              StreamSink<P2PBridgeEvent>                   │  │
│  │  - 线程安全的事件推送通道                                 │  │
│  │  - 自动序列化事件到 Dart                                 │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter UI 线程                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │           p2pSetEventStream() -> Stream                   │  │
│  │  - 返回 Dart Stream                                      │  │
│  │  - 自动接收 Rust 推送的事件                              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↓                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              _eventStreamSubscription                     │  │
│  │  - 订阅 Stream 接收事件                                  │  │
│  │  - 转发到 _eventController.broadcast()                    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↓                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  _handleEvent(event)                      │  │
│  │  - 解析事件 JSON 数据                                    │  │
│  │  - 转换为 Dart 事件对象                                   │  │
│  │  - 发送到 eventStream                                     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### Stream 模式 vs 轮询模式

| 特性 | Stream 模式（当前） | 轮询模式（旧版） |
|------|-------------------|----------------|
| **延迟** | 毫秒级实时推送 | 100ms 轮询间隔 |
| **CPU 使用** | 事件驱动，空闲时零消耗 | 定期轮询，持续消耗 |
| **电池消耗** | 低 | 较高 |
| **网络效率** | 即时响应 | 平均 50ms 延迟 |
| **实现复杂度** | 中等（需处理线程安全） | 简单 |

#### Rust 端实现

**关键文件**: `crates/ffi/src/lib.rs`

```rust
use flutter_rust_bridge::StreamSink;

// 全局 StreamSink（用于 FRB Stream 模式）
static GLOBAL_STREAM_SINK: Mutex<Option<frb_generated::StreamSink<
    bridge::P2PEvent,
    flutter_rust_bridge::for_generated::SseCodec
>>> = Mutex::new(None);

/// 设置事件流接收器（用于 Stream 模式）
pub fn set_event_stream_sink(
    stream_sink: frb_generated::StreamSink<
        bridge::P2PEvent,
        flutter_rust_bridge::for_generated::SseCodec
    >
) -> Result<(), String> {
    let mut sink = GLOBAL_STREAM_SINK.lock()
        .map_err(|e| format!("Failed to lock stream sink: {:?}", e))?;
    *sink = Some(stream_sink);
    Ok(())
}

/// 发送事件到 StreamSink（如果已设置）
fn send_event_to_stream(event: bridge::P2PEvent) {
    if let Ok(sink) = GLOBAL_STREAM_SINK.lock() {
        if let Some(ref sink) = *sink {
            // 将事件添加到 Stream，忽略错误
            let _: Result<(), flutter_rust_bridge::Rust2DartSendError> = sink.add(event);
        }
    }
}
```

**关键文件**: `crates/ffi/src/bridge.rs`

```rust
use flutter_rust_bridge::frb;
use crate::frb_generated::StreamSink;

/// 设置事件流接收器（用于 Stream 模式）
#[frb(sync)]
pub fn p2p_set_event_stream(
    stream_sink: StreamSink<P2PBridgeEvent>
) -> Result<(), String> {
    crate::set_event_stream_sink(stream_sink)
}
```

**事件发送示例**（在发现线程中）:

```rust
DiscoveryEvent::Discovered(peer_id, addr) => {
    let event = bridge::P2PEvent {
        event_type: 1,  // NodeDiscovered
        data: format!(r#"{{"peer_id":"{}","addr":"{}"}}"#, peer_id, addr),
    };
    // 同时发送到 Stream 和队列（兼容模式）
    send_event_to_stream(event.clone());
    let mut queue = FRB_EVENT_QUEUE.lock().unwrap();
    queue.push(event);
}
```

#### Flutter 端实现

**关键文件**: `app/lib/p2p_manager.dart`

```dart
class P2PManager {
  StreamSubscription<P2PBridgeEvent>? _eventStreamSubscription;

  /// 启动事件 Stream 订阅（Stream 模式）
  void _startEventStream() {
    // 取消之前的订阅（如果有）
    _eventStreamSubscription?.cancel();

    // 获取事件 Stream
    final eventStream = RustLib.instance.api.localp2PFfiBridgeP2PSetEventStream();

    // 订阅 Stream
    _eventStreamSubscription = eventStream.listen(
      (event) {
        _log.t('收到 Stream 事件，类型: ${event.eventType}');
        _handleEvent(event);
      },
      onError: (error) {
        _log.e('Stream 错误: $error');
      },
      onDone: () {
        _log.w('Stream 结束');
      },
    );
  }

  void _handleEvent(P2PBridgeEvent event) {
    switch (event.eventType) {
      case 1: // NodeDiscovered
        final peerId = _extractPeerId(event.data);
        if (peerId != null) {
          _eventController.add(NodeDiscoveredEvent(peerId));
        }
        break;
      case 6: // MessageReceived
        final from = _extractFrom(event.data);
        final content = _extractContent(event.data);
        if (from != null && content != null) {
          _eventController.add(MessageReceivedEvent(from, content, timestamp));
        }
        break;
      // ... 其他事件类型
    }
  }
}
```

#### 事件类型映射

| event_type | 事件名称 | Dart 类 |
|------------|----------|---------|
| 1 | NodeDiscovered | `NodeDiscoveredEvent` |
| 2 | NodeExpired | `NodeExpiredEvent` |
| 3 | NodeVerified | `NodeVerifiedEvent` |
| 4 | NodeOffline | `NodeOfflineEvent` |
| 5 | UserInfoReceived | `UserInfoReceivedEvent` |
| 6 | MessageReceived | `MessageReceivedEvent` |
| 7 | MessageSent | `MessageSentEvent` |
| 8 | PeerTyping | `PeerTypingEvent` |

#### 数据格式

所有事件数据以 JSON 字符串形式传输：

```json
// NodeDiscovered (event_type = 1)
{"peer_id":"12D3kooW...","addr":"/ip4/192.168.1.100/tcp/50001"}

// NodeVerified (event_type = 3)
{"peer_id":"12D3kooW...","display_name":"客厅电视"}

// MessageReceived (event_type = 6)
{"from":"12D3kooW...","content":"你好！","timestamp":1706357845123}
```

#### 线程安全保证

1. **Rust 端**: 使用 `Mutex<Option<StreamSink>>` 保护全局 StreamSink
2. **FRB 框架**: StreamSink 内部已实现线程安全的跨线程通信
3. **Flutter 端**: Stream 监听在 UI 线程执行，无需额外同步

#### 向后兼容性

为保持向后兼容，事件同时推送到：
- **StreamSink**（推荐，实时推送）
- **事件队列**（已弃用，轮询使用）

旧代码仍可通过 `p2p_poll_events()` 获取事件。

#### 相关文件

| 文件 | 说明 |
|------|------|
| `crates/ffi/src/lib.rs` | Rust FFI 实现，包含 StreamSink 管理 |
| `crates/ffi/src/bridge.rs` | FRB API 定义，包含 `p2p_set_event_stream()` |
| `crates/ffi/src/frb_generated.rs` | FRB 自动生成的代码（包含 Stream 类型） |
| `app/lib/p2p_manager.dart` | Flutter P2P 管理器，包含 Stream 订阅逻辑 |
| `app/lib/frb_generated.dart` | Dart 自动生成的代码 |
| `frb_config.yaml` | FRB 配置文件 |

### 平台特定配置

#### Linux

- 库文件: `liblocalp2p_ffi.so`
- 放置位置: `app/linux/`

#### macOS

- 库文件: `liblocalp2p_ffi.dylib`
- 放置位置: `app/macos/`

#### Windows

- 库文件: `localp2p_ffi.dll`
- 放置位置: `app/windows/`

#### Android

需要为不同架构编译库文件：

```bash
# ARM64
cargo build --target aarch64-linux-android --release

# ARMv7
cargo build --target armv7-linux-androideabi --release

# x86_64
cargo build --target x86_64-linux-android --release
```

库文件放置位置：
- `app/android/src/main/jniLibs/arm64-v8a/`
- `app/android/src/main/jniLibs/armeabi-v7a/`
- `app/android/src/main/jniLibs/x86_64/`

### 依赖配置

`app/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

### 故障排查

#### 问题 1：SIGABRT 崩溃 - nested async runtime

**错误信息**:
```
Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid xxx
#10 pc 00000000001ad7c0 (frb_pde_ffi_dispatcher_sync+24)
```

**原因**: 在 `async fn` 中调用 `runtime.block_on()` 导致嵌套异步运行时冲突

**解决方法**:
将需要使用 `block_on()` 的函数从 async 改为 sync，并使用 `#[frb(sync)]` 标记

**修改前**:
```rust
// ❌ 错误：async 函数中不能使用 block_on
pub async fn internal_get_nodes() -> Result<Vec<NodeInfo>, String> {
    let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
    let nodes = runtime.block_on(async {  // 崩溃！
        node_manager.list_nodes().await
    })?;
    Ok(nodes)
}
```

**修改后**:
```rust
// ✅ 正确：分离 sync 和 async 版本
fn internal_get_nodes_sync() -> Result<Vec<NodeInfo>, String> {
    let runtime = RUNTIME.as_ref().ok_or("No runtime")?;
    let nodes = runtime.block_on(async {
        node_manager.list_nodes().await
    })?;
    Ok(nodes)
}

pub async fn internal_get_nodes() -> Result<Vec<NodeInfo>, String> {
    tokio::task::spawn_blocking(|| {
        internal_get_nodes_sync()
    }).await.map_err(|e| format!("Join error: {:?}", e))?
}
```

**相关文件**:
- `crates/ffi/src/lib.rs` - 添加 sync 版本的函数
- `crates/ffi/src/bridge.rs` - 使用 `#[frb(sync)]` 标记

---

#### 问题 2：Content hash 不匹配

**错误信息**:
```
Bad state: Content hash on Dart side (-1696354102) is different from Rust side (-2061748452)
```

**原因**:
1. JNI 库输出路径配置错误
2. 旧版本的 .so 文件被加载

**解决方法**:

1. **修复构建脚本路径** (`scripts/build-android-ndk.sh`):
```bash
# ❌ 错误路径
ANDROID_JNI_DIR="$PROJECT_ROOT/app/android/src/main/jniLibs"

# ✅ 正确路径
ANDROID_JNI_DIR="$PROJECT_ROOT/app/android/app/src/main/jniLibs"
```

2. **清理并重新构建**:
```bash
# 清理旧的构建产物
flutter clean
cargo clean -p localp2p-ffi

# 重新构建原生库
export ANDROID_NDK_HOME=/path/to/ndk
bash scripts/build-android-ndk.sh

# 重新构建 APK
flutter build apk --release
```

3. **卸载旧版本**:
```bash
adb uninstall com.suno2.localp2p.localp2p_app
adb install app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

#### 问题 3：无法加载动态库

**原因**: 库文件路径不正确或文件不存在

**解决方法**:
1. 确保已编译 Rust 库
2. 检查库文件是否复制到正确的平台目录
3. 使用绝对路径测试

```dart
// 调试：打印当前工作目录
print('Current directory: ${Directory.current.path}');
```

---

#### 问题 4：FFI 回调未被触发

**原因**: 回调函数被垃圾回收

**解决方法**: 确保 `_callbackPointer` 被正确保存，不会被 GC 回收

---

#### 问题 5：节点列表为空

**原因**:
1. 没有其他节点在运行
2. 防火墙阻止了 mDNS 流量
3. 节点不在同一局域网

**解决方法**:
1. 启动多个实例进行测试
2. 允许防火墙通过 UDP 5353 端口
3. 确保设备在同一网络

---

#### 问题 6：后台恢复后 mDNS 发现失效

**症状**:
应用退入后台后再恢复，无法发现新设备，`_isRustRunning()` 返回 `false`

**原因**:
`internal_is_running()` 检查 `DISCOVERY_RESOURCES.is_some()`，但 `internal_start()` 使用 `.take()` 移出了资源，导致检查永远返回 `false`

**相关代码** (`crates/ffi/src/lib.rs`):
```rust
// 问题代码
pub fn internal_is_running() -> bool {
    unsafe {
        // ❌ 错误：检查 DISCOVERY_RESOURCES 是否存在
        DISCOVERY_RESOURCES.is_some()
    }
}

pub fn internal_start() -> Result<(), String> {
    unsafe {
        // 这里 .take() 会移出资源，导致 DISCOVERY_RESOURCES 变为 None
        let discovery = resources.discovery.take();
        // ...
    }
}
```

**解决方法**:
使用专门的运行标志而不是依赖资源状态：

```rust
// ✅ 正确：添加专门的运行标志
static mut P2P_IS_RUNNING: bool = false;

pub fn internal_is_running() -> bool {
    unsafe { P2P_IS_RUNNING }
}

pub fn internal_start() -> Result<(), String> {
    unsafe {
        // ... 启动逻辑 ...

        // 设置运行标志
        P2P_IS_RUNNING = true;
        Ok(())
    }
}

pub fn internal_stop() -> Result<(), String> {
    unsafe {
        // ... 停止逻辑 ...

        // 清除运行标志
        P2P_IS_RUNNING = false;
        Ok(())
    }
}

pub fn internal_cleanup() {
    unsafe {
        P2P_IS_RUNNING = false;
        // ... 其他清理 ...
    }
}
```

**相关文件**:
- `crates/ffi/src/lib.rs:59-62` - 定义 `P2P_IS_RUNNING` 标志
- `crates/ffi/src/lib.rs:1348-1353` - 修复 `internal_is_running()` 实现
- `crates/ffi/src/lib.rs:1189` - 在 `internal_start()` 中设置标志
- `crates/ffi/src/lib.rs:1314` - 在 `internal_stop()` 中清除标志
- `crates/ffi/src/lib.rs:1325` - 在 `internal_cleanup()` 中清除标志

---

## 日志系统

### 概述

项目实现了完整的日志系统，用于调试和问题排查。所有 Rust 与 Flutter 交互的细节都会被记录到日志文件中，方便开发者追踪问题。

**重要**: 所有节点（无论是 Rust 端还是 Flutter 端）都必须输出日志，这是开发和调试的强制要求。

### 日志架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter 应用                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    LogService                              │  │
│  │  - 文件输出: logs/localp2p_YYYY-MM-DD.log                │  │
│  │  - 日志级别: TRACE, DEBUG, INFO, WARN, ERROR, FATAL      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↑                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   P2PLogHelper                             │  │
│  │  - 🔴 Rust Call / 🟢 Rust Return / 🔴 Rust Error        │  │
│  │  - 📡 Event / 📱 Node / 💬 Message                       │  │
│  │  - 🔄 State Change / ⚡ Performance                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↑                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    P2PManager                              │  │
│  │  - 所有 Rust FFI 调用都记录详细日志                        │  │
│  │  - 记录参数、返回值、性能数据                              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Rust FFI 层                              │
│  - 所有 P2P 操作都会被 Flutter 端记录                           │
│  - 事件轮询、节点发现、消息收发都有日志                          │
└─────────────────────────────────────────────────────────────────┘
```

### 日志格式

```
[YYYY-MM-DD HH:MM:SS.mmm] [LEVEL] 消息内容
```

**示例**:
```
[2026-01-27 10:30:45.123] [INFO  ] ═══════════════════════════════════════════════════════════
[2026-01-27 10:30:45.124] [INFO  ] 应用启动 - 2026-01-27 10:30:45.124
[2026-01-27 10:30:45.125] [INFO  ] 日志文件: /path/to/logs/localp2p_2026-01-27.log
[2026-01-27 10:30:45.126] [INFO  ] ═══════════════════════════════════════════════════════════
[2026-01-27 10:30:45.234] [DEBUG ] 🔴 Rust Call: init | params: {deviceName: 我的设备}
[2026-01-27 10:30:45.256] [DEBUG ] flutter_rust_bridge 初始化成功
[2026-01-27 10:30:45.301] [DEBUG ] 🟢 Rust Return: init | result: initialized=true
[2026-01-27 10:30:45.301] [DEBUG ] ⚡ Performance: init took 201ms
[2026-01-27 10:30:45.402] [DEBUG ] 🔴 Rust Call: start
[2026-01-27 10:30:45.423] [DEBUG ] 🟢 Rust Return: start | result: started
[2026-01-27 10:30:45.424] [INFO  ] 📱 Node discovered: 12D3KooW...
[2026-01-27 10:30:45.525] [INFO  ] 📱 Node verified: 12D3KooW... | {displayName: 客厅电视}
[2026-01-27 10:30:46.123] [DEBUG ] 💬 Message SENT: 12D3KooW... | "你好，这是测试消息"
```

### Flutter 日志 API

#### LogService - 日志管理器

```dart
import '../services/log_service.dart';

// 初始化日志服务（在应用启动时调用）
await LogService.instance.init();

// 基础日志方法
LogService.instance.t('Trace 级别日志');
LogService.instance.d('Debug 级别日志');
LogService.instance.i('Info 级别日志');
LogService.instance.w('Warning 级别日志');
LogService.instance.e('Error 级别日志', error, stackTrace);

// 获取日志内容
String allLogs = await LogService.instance.getAllLogs();
String recentLogs = await LogService.instance.getRecentLogs(lines: 500);

// 获取日志文件大小
int fileSize = await LogService.instance.getLogFileSize();

// 清空日志
await LogService.instance.clearLogs();

// 获取所有日志文件
List<File> logFiles = await LogService.instance.getAllLogFiles();
```

#### P2PLogHelper - P2P 专用日志助手

```dart
import '../services/log_service.dart';

final _log = P2PLogHelper();

// Rust 交互日志
_log.rustCall('init', params: {'deviceName': '我的设备'});
_log.rustReturn('init', result: 'initialized=true');
_log.rustError('sendMessage', error, stackTrace);

// 事件日志
_log.event('NodeDiscovered', data: {'peerId': '12D3...'});

// 节点操作日志
_log.node('discovered', peerId, details: {'displayName': '客厅电视'});
_log.node('offline', peerId);
_log.node('verified', peerId, details: {'displayName': '卧室电视'});

// 消息日志
_log.message('SEND', peerId, '你好！');
_log.message('RECEIVED', peerId, '收到！');

// 状态变化日志
_log.stateChange('未初始化', '已初始化');

// 性能日志
_log.performance('init', Duration(milliseconds: 201));
```

### 日志文件位置

| 平台 | 日志目录 |
|------|----------|
| Linux | `~/.local/share/localp2p_app/logs/` |
| macOS | `~/Library/Application Support/localp2p_app/logs/` |
| Windows | `%APPDATA%\localp2p_app\logs\` |
| Android | `/data/data/com.suno2.localp2p.localp2p_app/files/logs/` |

日志文件命名格式: `localp2p_YYYY-MM-DD.log`

### 设置页面日志功能

Flutter 应用的设置页面提供以下日志管理功能：

| 功能 | 说明 |
|------|------|
| 日志文件大小 | 显示当前日志文件大小 |
| 导出日志 | 分享所有日志内容 |
| 查看日志 | 查看最近 500 条日志 |
| 清空日志 | 清空当前日志文件 |

**访问路径**: 设置 → 调试板块

### 开发规范要求

#### 1. 强制日志要求

**所有节点都必须输出日志**，包括但不限于：

- ✅ **Rust FFI 调用**: 每次调用 Rust 函数必须记录
  ```dart
  _log.rustCall('functionName', params: {...});
  // ... Rust 调用 ...
  _log.rustReturn('functionName', result: ...);
  ```

- ✅ **事件处理**: 每个事件必须记录
  ```dart
  _log.event('EventTypeName', data: {...});
  ```

- ✅ **节点操作**: 节点发现、验证、离线必须记录
  ```dart
  _log.node('discovered', peerId);
  _log.node('verified', peerId, details: {...});
  _log.node('offline', peerId);
  ```

- ✅ **消息收发**: 每条消息必须记录
  ```dart
  _log.message('SEND', peerId, message);
  _log.message('RECEIVED', peerId, message);
  ```

- ✅ **状态变化**: 重要的状态变化必须记录
  ```dart
  _log.stateChange('oldState', 'newState');
  ```

- ✅ **性能数据**: 关键操作必须记录性能
  ```dart
  final stopwatch = Stopwatch()..start();
  // ... 操作 ...
  _log.performance('operationName', stopwatch.elapsed);
  ```

- ✅ **错误信息**: 所有错误必须记录
  ```dart
  try {
    // ... 操作 ...
  } catch (e, stackTrace) {
    _log.e('操作失败: $e', e, stackTrace);
  }
  ```

#### 2. 日志级别使用规范

| 级别 | 用途 | 示例 |
|------|------|------|
| TRACE | 非常详细的调试信息 | 变量值、详细流程 |
| DEBUG | 调试信息 | Rust 调用、返回值 |
| INFO | 重要信息 | 节点发现、状态变化 |
| WARNING | 警告信息 | 未知的消息类型 |
| ERROR | 错误信息 | Rust 调用失败 |
| FATAL | 致命错误 | 初始化失败 |

#### 3. 性能要求

- 日志写入必须是**异步**的，不能阻塞主线程
- 日志文件按天自动滚动，单个文件大小不应超过 10MB
- 使用缓冲写入，避免频繁磁盘 I/O

### 调试指南

#### 1. 查看实时日志

```bash
# Linux/macOS
tail -f ~/.local/share/localp2p_app/logs/localp2p_$(date +%Y-%m-%d).log

# Windows PowerShell
Get-Content "$env:APPDATA\localp2p_app\logs\localp2p_$(Get-Date -Format 'yyyy-MM-dd').log" -Wait
```

#### 2. 导出日志

通过设置页面的"导出日志"功能，可以分享日志文件用于问题反馈。

#### 3. 日志分析要点

查找问题的关键日志模式：

```bash
# 查找错误
grep "ERROR" localp2p_*.log

# 查找 Rust 错误
grep "🔴 Rust Error" localp2p_*.log

# 查找节点离线
grep "Node offline" localp2p_*.log

# 查找消息发送
grep "Message SENT" localp2p_*.log

# 查找性能问题
grep "Performance" localp2p_*.log
```

### 依赖包

```yaml
# app/pubspec.yaml
dependencies:
  # 日志库
  logger: ^2.0.0          # 基础日志库
  path_provider: ^2.1.0   # 文件路径
  path: ^1.8.0            # 路径操作
  intl: ^0.18.0           # 日期格式化
  share_plus: ^7.0.0      # 日志分享
```

### 相关文件

| 文件 | 说明 |
|------|------|
| [app/lib/services/log_service.dart](app/lib/services/log_service.dart) | 日志服务实现 |
| [app/lib/p2p_manager.dart](app/lib/p2p_manager.dart) | P2P 管理器（含详细日志） |
| [app/lib/screens/settings_screen.dart](app/lib/screens/settings_screen.dart) | 设置页面（含日志导出） |
| [app/lib/screens/home_screen.dart](app/lib/screens/home_screen.dart) | 主页面（初始化日志服务） |

---

## 相关文档

- [study.md](study.md) - 开发历史记录和问题解决过程
- [FLUTTER_INTEGRATION.md](FLUTTER_INTEGRATION.md) - Flutter FFI 集成详细指南
- [libp2p 官方文档](https://docs.rs/libp2p/latest/libp2p/)
- [libp2p 0.56 CHANGELOG](https://docs.rs/crate/libp2p/latest/source/CHANGELOG.md)
