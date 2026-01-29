# P2P Discovery 问题分析与解决方案

## 问题描述

Flutter 应用从后台恢复到前台后，无法发现其他设备，也无法被其他设备发现。

## 设备离线检测机制

系统实现了完整的设备离线检测机制，通过两种方式自动检测设备离线：

### 触发方式

#### 方式一：TCP 连接关闭（立即检测）

当 libp2p 检测到 TCP 连接关闭时：

```rust
libp2p::swarm::SwarmEvent::ConnectionClosed { peer_id, .. } => {
    // 减少该节点的活跃连接计数
    let conn_count = self.active_connections.entry(peer_id).or_insert(0);
    *conn_count -= 1;

    // 如果该节点没有活跃连接了，标记为离线
    if *conn_count == 0 {
        tracing::warn!("💔 节点 {} 的所有连接已关闭，判定为离线", peer_id);
        self.node_manager.remove_node(&peer_id).await;
        return Ok(DiscoveryEvent::NodeOffline(peer_id));
    }
}
```

**特点**：
- ✅ 立即检测（无需等待）
- ✅ 准确判断连接状态
- ⚠️ 依赖 TCP 连接的稳定性

#### 方式二：心跳失败（延迟检测）

当 Ping 心跳连续失败时：

```rust
ping::Event { result: Err(_e), .. } => {
    let health = self.health_status.entry(peer).or_insert_with(|| NodeHealth::new());
    health.record_failure(self.health_config.max_failures);

    if health.is_offline() && was_healthy {
        tracing::warn!("💔 节点 {} 被判定为离线", peer);
        self.node_manager.remove_node(&peer).await;
        return Ok(DiscoveryEvent::NodeOffline(peer));
    }
}
```

**心跳配置**：
```rust
HealthCheckConfig {
    heartbeat_interval: 10秒,   // 每10秒发送一次 ping
    max_failures: 3,           // 连续失败3次判定为离线
}
```

**检测时间**：
- 最快检测时间：10秒 × 3 = **30秒**
- 平均检测时间：15-25秒

### 事件流转流程

```
设备离线/断开
        ↓
┌─────────────────────────────────────────┐
│  方式1: ConnectionClosed                 │
│  - 立即触发                              │
│  - 检查连接数是否为0                     │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│  方式2: Ping 连续失败 3次                │
│  - 延迟触发 (最多30秒)                   │
│  - consecutive_failures >= 3            │
└─────────────────────────────────────────┘
        ↓
DiscoveryEvent::NodeOffline(peer_id)
        ↓
从 NodeManager 移除节点
        ↓
发送到 Flutter (event_type: 4)
        ↓
Flutter UI 重新加载设备列表
        ↓
设备从列表中消失 ✓
```

### 日志示例

**场景1：连接关闭（立即检测）**
```
[INFO] 与 12D3KooW... 的连接关闭
[WARN] 💔 节点 12D3KooW... 的所有连接已关闭，判定为离线
[INFO] 已从管理器中移除离线节点 12D3KooW...
[WARN] [discovery] 节点离线: 12D3KooW...
```

**场景2：心跳失败（30秒后检测）**
```
[WARN] ❤️ 节点 12D3KooW... ping 失败 (1/3)
[INFO] [discovery] 距离上次事件 5.2 秒
[WARN] ❤️ 节点 12D3KooW... ping 失败 (2/3)
[INFO] [discovery] 距离上次事件 15.8 秒
[WARN] ❤️ 节点 12D3KooW... ping 失败 (3/3)
[WARN] 💔 节点 12D3KooW... 被判定为离线
[INFO] 已从管理器中移除离线节点 12D3KooW...
[WARN] [discovery] 节点离线: 12D3KooW...
```

### 相关文件

- `crates/mdns/src/managed_discovery.rs` - 离线检测实现（行 355-375, 398-416）
- `crates/ffi/src/lib.rs` - 事件转发（行 347-364）
- `app/lib/p2p_manager.dart` - Flutter 端处理（行 366-374）
- `app/lib/screens/device_list_screen.dart` - UI 刷新（行 44-48）

## 已知问题和权衡

### ⚠️ 无条件重启的副作用

**问题**：如果在 resume 时无条件重启 discovery，可能会导致：
1. **破坏正常工作的连接**：如果应用在电池优化白名单中，后台 mDNS 可能仍在工作
2. **不必要的连接抖动**：每次 resume 都会断开所有现有连接
3. **设备列表闪烁**：频繁重连会导致 UI 抖动

**场景对比**：
| 场景 | mDNS 状态 | 无条件重启 | 健康检查重启 |
|------|-----------|------------|--------------|
| 后台时间长 | 已停止 | ✅ 重启 | ✅ 重启 |
| 后台时间短 | 可能仍在工作 | ❌ 过度重启 | ✅ 保持 |
| 电池白名单 | 仍在工作 | ❌ 破坏连接 | ✅ 保持 |
| 非白名单 | 已停止 | ✅ 重启 | ✅ 重启 |

**解决方案**：在 resume 时先执行健康检查，只在确认需要时才重启。

## 根本原因

### 1. Android 应用生命周期对 mDNS 的影响

当 Android 应用进入后台时，系统会：
- **暂停网络活动**以节省电量
- **限制后台网络访问**
- 可能**挂起 mDNS 服务**

当应用恢复到前台时：
- mDNS 服务可能**没有自动恢复**
- Discovery 线程可能还活着，但**mDNS 实际已停止工作**
- 无法发现其他设备，也无法被其他设备发现

### 2. 健康检查的复杂性

最初的实现只检查了 **线程是否存活**（通过 Ping 命令），但：
- 线程存活 ≠ mDNS 在工作
- Android 可能暂停了 mDNS 的网络功能
- 需要更复杂的健康检查机制

### 3. 事件时间跟踪的重要性

关键洞察：
- **正常情况**：discovery 会持续收到事件（发现节点、心跳、离线等）
- **异常情况**：mDNS 停止后，**不再有新事件**
- **解决方案**：跟踪最后一次收到事件的时间，如果超过阈值，认为 mDNS 已停止

### 4. mDNS 停止 vs 连接断开

**重要区别**：

| 组件 | 作用 | 后台状态 | 影响 |
|------|------|----------|------|
| **mDNS** | 发现新设备 | ❌ 通常停止 | 无法发现新设备 |
| **TCP 连接** | 维持已有连接 | ⚠️ 可能断开 | 设备可能离线 |
| **Ping 心跳** | 检测连接健康 | ⚠️ 可能失败 | 触发离线事件 |

**设备无法被发现的主要原因**：
1. **mDNS 停止**（主要原因）
   - 无法发现新设备 ✅
   - 无法被其他设备发现 ✅
   - 已建立的连接可能还在 ⚠️

2. **TCP 连接断开**（次要原因，通常是 mDNS 停止的副作用）
   - 已连接的设备断开
   - 触发 `NodeOffline` 事件
   - 设备从列表中消失

**典型流程**：
```
应用进入后台（5-30秒）
    ↓
Android 暂停 mDNS（主要）
    ↓
TCP 连接可能保持（短时间）或断开（长时间）
    ↓
如果连接保持：已发现设备还在，但无法发现新设备
如果连接断开：触发 NodeOffline 事件，设备从列表消失
    ↓
应用恢复前台
    ↓
智能重启 discovery
    ↓
mDNS 恢复，重新发现设备
```

## 解决方案

### 当前实现（已验证有效）

#### 1. 应用生命周期处理（直接重启）

```dart
void resumeEventStream() {
    // 1. 重新订阅 Stream（确保能接收日志）
    _restartEventStream();

    // 2. 立即重启 discovery（无条件）
    RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery();
}
```

**关键点**：
- ✅ 先重新订阅 Stream（确保日志能被接收）
- ✅ 立即重启 discovery（无条件）
- ✅ 快速恢复 mDNS 和设备发现
- ⚠️ 会断开现有连接，但恢复速度快

## 参数调优

### 关键参数

| 参数 | 当前值 | 说明 |
|------|--------|------|
| **节点心跳间隔** | 10 秒 | 节点间心跳检测间隔 |
| **节点心跳失败阈值** | 3 次 | 连续失败 3 次认为节点离线 |

**注意**：
- 已移除智能健康检查，改为直接重启
- 完全依赖应用生命周期事件触发

## 重启流程

### 触发条件

**应用从后台恢复时**：
1. 重新订阅 Stream（确保日志能被接收）
2. 立即触发重启（无条件）

### 重启步骤

```
1. 发送 Stop 命令给现有 discovery 线程
2. 等待线程退出（最多 2 秒）
3. 重新创建 discovery 资源：
   - 使用现有的 node_manager
   - 重新创建 ManagedDiscovery 实例
   - 重新创建命令通道
   - 使用保存的 identity（保持 Peer ID 不变）
4. 启动新的 discovery 线程
5. 立即开始发现设备
```

### 注意事项

✅ **重启会保持相同的 Peer ID**

当前的实现已经在 `P2PInstance` 中保存了 `identity` 字段：
```rust
struct P2PInstance {
    node_manager: Arc<NodeManager>,
    local_peer_id: String,
    device_name: String,
    identity: Option<libp2p::identity::Keypair>, // 保存密钥对
    command_tx: ...,
    discovery_thread: ...,
}
```

在重启时会使用保存的 identity：
```rust
// 从 P2PInstance 获取保存的 identity
let identity = {
    let inst = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
    inst.identity.clone()
};

// 使用保存的 identity 创建新的 discovery
let discovery_result = ManagedDiscovery::new(
    node_manager.clone(),
    listen_addresses,
    health_config,
    user_info,
    identity, // 使用保存的密钥对，保持 Peer ID 不变
).await;
```

这确保了：
- ✅ 每次重启都保持相同的 Peer ID
- ✅ 其他设备无需重新发现
- ✅ 提升用户体验，减少重新发现的延迟

## 日志示例

### 正常情况

```
[INFO] [ffi] Discovery 线程启动
[INFO] [discovery] 发现节点: 12D3KooW...
[INFO] [discovery] 验证节点: 12D3KooW...
[INFO] 📱 Node verified: 12D3KooW...
```

### 检测到问题

```
[INFO] [ffi] 开始 Discovery 健康检查...
[INFO] [ffi] 距离上次事件 12.3 秒
[WARN] [ffi] 距离上次事件已 12.3 秒，超过阈值 10 秒，discovery 可能已停止
[INFO] [ffi] Discovery 健康检查结果: Ping=true 事件时间=false => false
```

### 自动重启

```
[INFO] 定期健康检查: discovery 线程已死，尝试重启...
[INFO] [ffi] 开始重启 Discovery 服务
[INFO] [ffi] 已停止旧 Discovery 服务
[INFO] [ffi] Discovery 服务重启成功
[INFO] [ffi] Discovery 线程启动
[INFO] [discovery] 发现节点: 12D3KooW...
```

## 已实现的改进

### ✅ 1. 智能生命周期处理（已实现）

在 `didChangeAppLifecycleState` 中**先检查后重启**：

```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
        // 调用 resumeEventStream（内部会先检查再决定是否重启）
        resumeEventStream();
    }
}

void resumeEventStream() {
    // 1. 重新订阅 Stream（确保日志能被接收）
    _restartEventStream();

    // 2. 执行健康检查
    final isAlive = _isDiscoveryThreadAlive();

    // 3. 只在需要时才重启
    if (isAlive) {
        // Discovery 健康正常，保持现有连接
    } else {
        // Discovery 已停止，执行重启
        RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery();
    }
}
```

**优势**：
- ✅ 避免破坏正常工作的连接
- ✅ 减少不必要的连接抖动
- ✅ 仍然能够处理需要重启的情况

### ✅ 2. 移除定期健康检查（已实现）

完全移除了定期检查，只依赖生命周期事件：
- 删除了 `Timer? _healthCheckTimer` 字段
- 删除了 `_startHealthCheckTimer()` 和 `_performHealthCheck()` 方法
- 在应用恢复时立即重启，无需等待定时器

### ✅ 3. 保持 Peer ID 稳定（已实现）

在 `P2PInstance` 中保存 identity，重启时重用：

```rust
// 初始化时保存 identity
struct P2PInstance {
    identity: Option<libp2p::identity::Keypair>,
    // ...
}

// 重启时使用保存的 identity
let identity = {
    let inst = P2P_INSTANCE.as_ref().unwrap().lock().unwrap();
    inst.identity.clone()
};

let discovery_result = ManagedDiscovery::new(
    node_manager.clone(),
    listen_addresses,
    health_config,
    user_info,
    identity, // 使用保存的密钥对，Peer ID 保持不变
).await;
```

## 可选的进一步优化

### 降低事件时间阈值

如果未来需要更积极的检测（虽然当前已不需要定期检查），可以将阈值从 10 秒降低到 **5 秒**：

```rust
let is_alive = elapsed.as_secs() < 5;  // 更激进的检测
```

## 总结

### 问题根源
Android 在后台暂停 mDNS 活动，恢复前台后 mDNS 不会自动重启。

### 最终解决方案（已实现）
1. **直接重启**：应用恢复时立即重启 discovery，无需检查
2. **Peer ID 稳定**：重启时使用保存的密钥对，确保 Peer ID 不变
3. **事件流恢复**：重新订阅 Stream 以确保日志和事件能被接收
4. **自动离线检测**：通过连接关闭和心跳失败自动检测设备离线

### 当前状态
✅ 已实现并验证有效
✅ 从后台恢复后立即重启 discovery（快速恢复）
✅ Peer ID 在重启后保持不变
✅ 设备发现正常工作
✅ 日志和事件流正常接收
✅ 自动检测并移除离线设备
⚠️ 每次都会断开并重连现有连接

### 实现细节
- **移除了智能健康检查**：改为直接重启，提高恢复速度
- **直接重启逻辑**：在 `resumeEventStream()` 中无条件重启
- **保存密钥对**：在 `P2PInstance` 中保存 `identity` 字段，重启时重用
- **离线检测机制**：
  - TCP 连接关闭 → 立即移除设备
  - 心跳连续失败 3 次（30秒） → 移除设备

### 已知问题和权衡
⚠️ **电池白名单场景**：如果应用在电池优化白名单中，后台 mDNS 可能仍在工作
- ❌ 直接重启会破坏白名单设备的正常连接
- 💡 可能的改进：检测电池白名单状态，在白名单中时减少重启频率
- 需要：Android API 检测电池优化状态

⚠️ **连接抖动**：每次恢复都会断开并重连
- ❌ 设备列表可能短暂闪烁
- ✅ 但恢复速度快，用户体验总体更好

⚠️ **离线检测延迟**：心跳失败需要 30 秒才判定离线
- ✅ TCP 连接关闭会立即检测
- ⚠️ 心跳失败最多需要 30 秒（3次 × 10秒）
- 💡 可能的优化：降低失败阈值到 2 次（20秒）或 1 次（10秒）

## 问题演化和讨论

### 阶段 1：无条件重启（初期实现）

**实现**：
```dart
void resumeEventStream() {
    _restartEventStream();
    RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery(); // 无条件重启
}
```

**优点**：
- ✅ 简单直接，总是能恢复连接
- ✅ 适用于大多数情况（非白名单设备）

**缺点**：
- ❌ 破坏正常工作的连接（白名单设备）
- ❌ 不必要的连接抖动
- ❌ 设备列表闪烁

### 阶段 2：智能重启（已废弃）

**实现**：
```dart
void resumeEventStream() {
    _restartEventStream();
    final isAlive = _isDiscoveryThreadAlive();
    if (!isAlive) {
        RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery();
    }
}
```

**优点**：
- ✅ 避免破坏正常工作的连接
- ✅ 减少不必要的抖动

**缺点**：
- ❌ 连接恢复慢（需要等待健康检查）
- ❌ 健康检查可能不够准确
- ❌ 用户体验不如直接重启

### 阶段 3：直接重启（当前实现）⭐

**实现**：
```dart
void resumeEventStream() {
    // 1. 重新订阅 Stream（确保能接收日志）
    _restartEventStream();

    // 2. 立即重启 discovery（无条件）
    RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery();
}
```

**优点**：
- ✅ 连接恢复快（立即重启，无需等待）
- ✅ 简单直接，总是能恢复
- ✅ 用户体验好（快速发现设备）

**缺点**：
- ❌ 破坏正常工作的连接（白名单设备）
- ❌ 每次都会断开重连
- ❌ 设备列表可能短暂闪烁

### 讨论点

**1. 事件时间阈值的权衡**
- ⚠️ **已废弃**：当前使用直接重启，不再依赖事件时间阈值
- 历史原因：智能重启阶段使用了此阈值

**2. 是否需要添加用户手动重启选项？**
- 当前：自动重启已足够
- 可选：在 UI 中添加"重新发现"按钮作为备用

**3. 是否需要更精确的 mDNS 健康检查？**
- ⚠️ **已废弃**：直接重启无需健康检查
- 历史原因：智能重启阶段使用了健康检查

**4. 电池白名单场景的优化**
- ⚠️ **当前问题**：直接重启会破坏白名单设备的正常连接
- 可能的改进：检测电池白名单状态，在白名单中时减少重启频率
- 需要：Android API 检测电池优化状态

**5. 离线检测参数的权衡**
- **心跳间隔 10 秒**：当前值，平衡性能和及时性
- **失败阈值 3 次**：30秒判定离线，可能较长
- **选项**：降低到 2 次（20秒）或 1 次（10秒）
- **权衡**：更快的离线检测 vs 更高的误判率（网络抖动）

**6. 连接关闭 vs 心跳失败的优先级**
- 当前：两种方式都会触发离线
- 问题：是否需要区分处理？
  - 连接关闭：立即移除（合理）
  - 心跳失败：等待确认后再移除（避免误判）

## 相关文件

### 核心实现
- `crates/ffi/src/lib.rs` - 核心 FFI 实现（包含 P2PInstance 和 restart 逻辑）
- `crates/ffi/src/bridge.rs` - Bridge API 定义
- `app/lib/p2p_manager.dart` - Flutter 端 P2P 管理器（resumeEventStream）
- `app/lib/screens/home_screen.dart` - 应用生命周期处理

### 离线检测
- `crates/mdns/src/managed_discovery.rs` - 离线检测实现（行 355-375, 398-416）
- `crates/ffi/src/lib.rs` - 事件转发（行 347-364）
- `app/lib/p2p_manager.dart` - Flutter 端处理（行 366-374）
- `app/lib/screens/device_list_screen.dart` - UI 刷新（行 44-48）

