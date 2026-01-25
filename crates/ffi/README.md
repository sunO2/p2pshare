# Local P2P FFI Crate

这是 Local P2P 项目的 FFI 层，提供了 C ABI 兼容的接口，可以与 Flutter、Dart、C/C++、Python 等语言集成。

## 目录结构

```
crates/ffi/
├── include/
│   └── localp2p.h          # C 头文件
├── src/
│   ├── lib.rs              # 主要 FFI 实现
│   ├── types.rs            # 类型定义
│   ├── error.rs            # 错误类型
│   └── callbacks.rs        # 回调管理
├── cbindgen.toml           # cbindgen 配置
├── build.sh                # 构建脚本
└── Cargo.toml              # 包配置
```

## 快速开始

### 1. 编译库文件

使用构建脚本（推荐）：

```bash
# 构建所有平台
./build.sh all

# 只构建当前平台
./build.sh linux    # Linux
./build.sh macos-arm64  # macOS ARM64
./build.sh windows  # Windows（使用 PowerShell）

# 清理并重新构建
./build.sh macos-arm64 clean
```

或手动编译：

```bash
# Linux/macOS
cargo build --release

# 特定目标
cargo build --target x86_64-unknown-linux-gnu --release
cargo build --target aarch64-apple-darwin --release
```

### 2. 输出文件

编译后的库文件位于 `target/` 目录：

| 平台 | 输出文件位置 |
|------|-------------|
| Linux x64 | `target/x86_64-unknown-linux-gnu/release/liblocalp2p_ffi.so` |
| macOS ARM64 | `target/aarch64-apple-darwin/release/liblocalp2p_ffi.dylib` |
| macOS x64 | `target/x86_64-apple-darwin/release/liblocalp2p_ffi.dylib` |
| Windows x64 | `target/x86_64-pc-windows-msvc/release/localp2p_ffi.dll` |
| Android ARM64 | `target/aarch64-linux-android/release/liblocalp2p_ffi.so` |
| iOS ARM64 | `target/aarch64-apple-ios/release/liblocalp2p_ffi.a` |

### 3. 使用 C 头文件

头文件位于 `include/localp2p.h`，包含了所有公共接口的定义。

## API 概览

### 核心函数

| 函数 | 说明 |
|------|------|
| `localp2p_init()` | 初始化 P2P 模块 |
| `localp2p_start()` | 启动服务并设置回调 |
| `localp2p_stop()` | 停止服务 |
| `localp2p_cleanup()` | 清理资源 |

### 查询函数

| 函数 | 说明 |
|------|------|
| `localp2p_get_local_peer_id()` | 获取本地 Peer ID |
| `localp2p_get_device_name()` | 获取设备名称 |
| `localp2p_get_verified_nodes()` | 获取已验证的节点列表 |

### 聊天功能

| 函数 | 说明 |
|------|------|
| `localp2p_send_message()` | 发送消息给单个节点 |
| `localp2p_broadcast_message()` | 广播消息给多个节点 |

### 内存管理

| 函数 | 说明 |
|------|------|
| `localp2p_free_node_list()` | 释放节点列表 |
| `localp2p_free_error()` | 释放错误信息 |

## 类型定义

```c
/** P2P 句柄 */
typedef struct { int32_t _private; } LocalP2P_Handle;

/** 错误代码 */
typedef enum {
    LOCALP2P_SUCCESS = 0,
    LOCALP2P_NOT_INITIALIZED = -1,
    LOCALP2P_INVALID_ARGUMENT = -2,
    LOCALP2P_SEND_FAILED = -3,
    LOCALP2P_NODE_NOT_VERIFIED = -4,
    LOCALP2P_OUT_OF_MEMORY = -5,
    LOCALP2P_UNKNOWN = -99,
} LocalP2P_ErrorCode;

/** 事件类型 */
typedef enum {
    LOCALP2P_EVENT_NODE_DISCOVERED = 1,
    LOCALP2P_EVENT_NODE_VERIFIED = 3,
    LOCALP2P_EVENT_NODE_OFFLINE = 4,
    LOCALP2P_EVENT_MESSAGE_RECEIVED = 6,
    LOCALP2P_EVENT_MESSAGE_SENT = 7,
    LOCALP2P_EVENT_PEER_TYPING = 8,
} LocalP2P_EventType;

/** 事件数据 */
typedef struct {
    LocalP2P_EventType event_type;
    const char *peer_id;
    const char *display_name;
    const char *message;
    const char *message_id;
    bool is_typing;
    int64_t timestamp;
} LocalP2P_EventData;

/** 事件回调类型 */
typedef void (*LocalP2P_EventCallback)(LocalP2P_EventData event, void *user_data);
```

## 使用示例

### C 示例

```c
#include "localp2p.h"
#include <stdio.h>
#include <stdlib.h>

// 事件回调函数
void on_event(LocalP2P_EventData event, void *user_data) {
    switch (event.event_type) {
        case LOCALP2P_EVENT_NODE_VERIFIED:
            printf("Node verified: %s (%s)\n",
                   event.peer_id, event.display_name);
            break;
        case LOCALP2P_EVENT_MESSAGE_RECEIVED:
            printf("Message from %s: %s\n",
                   event.peer_id, event.message);
            break;
        case LOCALP2P_EVENT_NODE_OFFLINE:
            printf("Node offline: %s\n", event.peer_id);
            break;
        default:
            break;
    }
}

int main() {
    char *error = NULL;

    // 1. 初始化
    LocalP2P_Handle handle = localp2p_init("My C Device", &error);
    if (error) {
        fprintf(stderr, "Init failed: %s\n", error);
        localp2p_free_error(error);
        return 1;
    }

    // 2. 启动服务
    if (localp2p_start(handle, on_event, NULL) != LOCALP2P_SUCCESS) {
        fprintf(stderr, "Start failed\n");
        return 1;
    }

    // 3. 获取本地信息
    char peer_id[256];
    localp2p_get_local_peer_id(handle, peer_id, sizeof(peer_id));
    printf("Local Peer ID: %s\n", peer_id);

    // 4. 等待用户输入
    printf("Press Enter to exit...\n");
    getchar();

    // 5. 清理
    localp2p_cleanup(handle);

    return 0;
}
```

### 编译 C 示例

```bash
# Linux
gcc -o example example.c -Ltarget/release -llocalp2p_ffi -lpthread -ldl
LD_LIBRARY_PATH=target/release:$LD_LIBRARY_PATH ./example

# macOS
gcc -o example example.c -Ltarget/release -llocalp2p_ffi
DYLD_LIBRARY_PATH=target/release:$DYLD_LIBRARY_PATH ./example
```

## Dart/Flutter 集成

详细的 Flutter 集成指南请参考：[`FLUTTER_INTEGRATION.md`](../../FLUTTER_INTEGRATION.md)

## 注意事项

1. **线程安全**: FFI 函数不是线程安全的，需要调用者确保同步
2. **内存管理**: 调用者负责释放返回的内存（如节点列表、错误信息）
3. **回调生命周期**: 回调函数中的字符串指针仅在回调期间有效
4. **错误处理**: 每个函数都可能返回错误代码，需要检查返回值

## 调试

启用详细日志：

```bash
RUST_LOG=debug cargo build --release
RUST_LOG=debug ./your_app
```

## 许可证

与主项目相同
