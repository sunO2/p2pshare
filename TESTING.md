# 功能测试指南

## 快速测试步骤

### 1. 准备测试环境

在局域网内准备 2-3 台设备（或使用同一台设备运行多个实例）：
```bash
# 终端 1
cd /home/hezhihu89/develop/rust/program/localp2p/app
flutter run -d linux

# 终端 2 (另一台设备或同一设备)
flutter run -d linux
```

### 2. 验证基础功能

**设备发现测试**:
1. 启动两个应用实例
2. 检查"我的设备"页面是否显示发现的设备数量
3. 验证设备列表显示正确

**设备信息显示**:
- 检查设备卡片是否显示设备名称
- 验证 Peer ID 是否正确显示（缩短格式）
- 确认"在线"状态指示器显示

### 3. 测试用户信息同步

**设置不同的设备名称**:
```dart
// 在 home_screen.dart 中修改设备名称
await P2PManager.instance.init('客厅电视');
await P2PManager.instance.init('卧室 NAS');
await P2PManager.instance.init('我的开发机');
```

**验证显示**:
- 设备卡片应显示设置的设备名称
- 而不是默认的"我的设备"

### 4. 测试聊天功能

**发送消息**:
1. 在设备列表中点击一个设备的聊天按钮
2. 进入聊天界面
3. 输入消息并点击发送
4. 验证消息是否出现在右侧（蓝色气泡）
5. 检查对方设备是否收到消息（左侧气泡）

**消息历史**:
- 发送多条消息
- 验证消息按时间顺序显示
- 确认发送和接收消息的样式区分

### 5. 测试节点离线

**模拟离线**:
1. 关闭其中一个应用实例
2. 在另一个应用中观察设备列表
3. 验证离线设备是否从列表中移除（或状态变化）

**重新上线**:
1. 重新启动被关闭的应用
2. 验证设备是否重新出现在列表中

## 预期行为

### 正常启动流程

```
应用启动
    ↓
显示 "正在初始化..." 加载动画
    ↓
初始化 P2P 模块
    ↓
创建 Tokio 运行时
    ↓
创建节点管理器
    ↓
创建发现器 (ManagedDiscovery)
    ↓
启用聊天功能 (enable_chat)
    ↓
启动 mDNS 扫描
    ↓
显示主界面（设备列表）
```

### 设备发现流程

```
设备 A 启动                          设备 B 启动
     ↓                                      ↓
  mDNS 广播                          mDNS 广播
     ↓                                      ↓
  发现设备 B                          发现设备 A
     ↓                                      ↓
  自动连接                              自动连接
     ↓                                      ↓
  Identify 验证                        Identify 验证
     ↓                                      ↓
  交换用户信息                        交换用户信息
     ↓                                      ↓
  显示设备 B                          显示设备 A
```

### 用户信息交换

```
连接建立
    ↓
发送用户信息请求
    ↓
┌─────────────────────────────────┐
│ UserInfoResponse                 │
│ {                               │
│   "device_name": "客厅电视",     │
│   "nickname": "电视",             │
│   "status": "在线",               │
│   "avatar_url": null              │
│ }                               │
└─────────────────────────────────┘
    ↓
更新全局用户信息缓存
    ↓
触发 UserInfoReceivedEvent (type=5)
    ↓
Flutter 端接收事件
    ↓
更新 UI 显示昵称和状态
```

## 故障排查

### 问题: 无法发现设备

**检查清单**:
1. 确认设备在同一局域网（同一网段）
2. 检查防火墙是否允许 UDP 5353 端口
3. 验证协议版本是否一致（应该都是 `/localp2p/1.0.0`）
4. 查看日志输出

**Linux 防火墙配置**:
```bash
# 允许 mDNS 流量
sudo ufw allow 5353/udp

# 或使用 iptables
sudo iptables -A INPUT -p udp --dport 5353 -j ACCEPT
```

### 问题: 消息发送失败

**可能原因**:
1. 目标设备已离线
2. 网络连接不稳定
3. P2P 连接断开

**解决方案**:
1. 检查设备是否仍在线
2. 查看控制台日志
3. 尝试重新发送

### 问题: UI 不更新

**可能原因**:
1. 事件轮询停止
2. setState 未调用
3. UI 线程问题

**解决方案**:
1. 检查 `p2p_poll_events()` 是否定期调用
2. 验证事件监听器是否正确设置
3. 热重启应用

## 日志查看

### 启用详细日志

```dart
// 在 main.dart 中
import 'package:flutter/foundation.dart';

void main() {
  // 启用详细日志
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runApp(MyApp());
}
```

### 查看日志输出

```bash
# 运行应用时显示日志
flutter run -d linux -v

# 查看特定标签的日志
flutter run -d linux 2>&1 | grep -E "(P2P|MDNS|Chat)"
```

## 性能监控

### 内存使用

```dart
import 'package:flutter/material.dart';

void checkMemory() {
  // 查看设备数量
  final nodes = await P2PManager.instance.getVerifiedNodes();
  print('设备数量: ${nodes.length}');

  // 查看事件队列大小
  final events = P2PBridge.instance.api.localp2PFfiBridgeP2PPollEvents();
  print('待处理事件: ${events.length}');
}
```

### CPU 使用

事件轮询间隔为 100ms，这会占用一定的 CPU 资源。如果需要降低 CPU 占用，可以考虑：
1. 增加轮询间隔（如 200-500ms）
2. 使用 Stream 方式替代轮询
3. 在应用进入后台时暂停轮询

## 下一步

完成基础测试后，可以尝试：
1. 修改设备名称和状态
2. 测试文件传输功能（待实现）
3. 测试群聊功能（待实现）
4. 测试离线重连
