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

### 5. chat/ - 聊天模块

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

## 相关文档

- [study.md](study.md) - 开发历史记录和问题解决过程
- [libp2p 官方文档](https://docs.rs/libp2p/latest/libp2p/)
- [libp2p 0.56 CHANGELOG](https://docs.rs/crate/libp2p/latest/source/CHANGELOG.md)
