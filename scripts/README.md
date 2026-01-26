# Android FFI 库交叉编译指南

本目录包含用于将 Rust FFI 库交叉编译到 Android 不同 CPU 架构的脚本。

## 目录结构

```
scripts/
├── build-android.sh       # Linux/macOS 标准交叉编译脚本（备用）
├── build-android-ndk.sh   # Linux/macOS 使用 cargo-ndk 的构建脚本（推荐）
├── build-android.ps1      # Windows PowerShell 构建脚本
└── README.md              # 本文档
```

## 环境要求

### 必需工具

| 工具 | 版本要求 | 安装方式 |
|------|---------|----------|
| Rust | 1.70+ | https://rustup.rs/ |
| Cargo | 随 Rust | 随 Rust 安装 |
| cargo-ndk | 4.0+ | `cargo install cargo-ndk` |
| Android NDK | 21+ | Android Studio SDK Manager |

### 环境变量配置

构建脚本需要以下环境变量：

```bash
# Android NDK 路径（必需）
export ANDROID_NDK_HOME=$HOME/develop/android/sdk/ndk/26.3.11579264

# 代理设置（可选，下载慢时使用）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=http://127.0.0.1:7890
```

### 安装 cargo-ndk

```bash
# 安装 cargo-ndk 工具
cargo install cargo-ndk

# 验证安装
cargo ndk --version
```

## 支持的 Android CPU 架构

| 架构 | Rust Target | 目录名 | 说明 | 设备覆盖率 |
|------|-------------|--------|------|------------|
| ARM 64-bit | `aarch64-linux-android` | `arm64-v8a` | 现代设备 | ~85% |
| ARM 32-bit | `armv7-linux-androideabi` | `armeabi-v7a` | 老款设备 | ~10% |
| x86_64 | `x86_64-linux-android` | `x86_64` | 模拟器/平板 | <5% |
| x86 | `i686-linux-android` | `x86` | 老款模拟器 | <1% |

> **注意**：arm64-v8a 和 armeabi-v7a 已经覆盖了绝大多数设备，其他架构主要用于模拟器。

## 快速开始

### 方式一：使用 cargo-ndk（推荐）

```bash
# 1. 设置环境变量
export ANDROID_NDK_HOME=$HOME/develop/android/sdk/ndk/26.3.11579264

# 2. （可选）设置代理
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=http://127.0.0.1:7890

# 3. 运行构建脚本
./scripts/build-android-ndk.sh
```

### 方式二：使用标准交叉编译

```bash
# 1. 设置环境变量
export ANDROID_NDK_HOME=$HOME/develop/android/sdk/ndk/26.3.11579264

# 2. （可选）设置代理
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=http://127.0.0.1:7890

# 3. 给脚本添加执行权限
chmod +x scripts/build-android.sh

# 4. 运行构建脚本
./scripts/build-android.sh
```

### Windows (PowerShell)

```powershell
# 1. 设置环境变量
$env:ANDROID_NDK_HOME="C:\Users\YourName\develop\android\sdk\ndk\26.3.11579264"

# 2. （可选）设置代理
$env:https_proxy="http://127.0.0.1:7890"
$env:http_proxy="http://127.0.0.1:7890"
$env:all_proxy="http://127.0.0.1:7890"

# 3. 允许脚本执行（如果首次运行）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 4. 运行构建脚本
.\scripts\build-android.ps1
```

## 构建流程

### cargo-ndk 方式（推荐）

脚本会自动执行以下步骤：

1. **检查 cargo-ndk** - 验证 cargo-ndk 是否已安装
2. **检查 Android NDK** - 验证 NDK 路径是否配置
3. **清理旧的库文件** - 删除之前的 jniLibs 目录
4. **交叉编译** - 使用 cargo-ndk 为所有架构编译 .so 文件
5. **复制到 jniLibs** - 将编译好的库文件复制到 Android 项目目录

### 标准交叉编译方式

1. **检查编译环境** - 验证 Rust 和 Cargo 是否已安装
2. **安装交叉编译工具链** - 使用 rustup 安装 Android 目标架构
3. **清理旧的库文件** - 删除之前的 jniLibs 目录
4. **交叉编译库文件** - 为每个目标架构编译 .so 文件
5. **复制到 jniLibs** - 将编译好的库文件复制到 Android 项目目录

## 输出位置

编译好的 .so 文件会被复制到：

```
app/android/src/main/jniLibs/
├── arm64-v8a/
│   └── liblocalp2p_ffi.so    (~6.2 MB)
├── armeabi-v7a/
│   └── liblocalp2p_ffi.so    (~4.4 MB)
├── x86_64/
│   └── liblocalp2p_ffi.so    (~6.0 MB)
└── x86/
    └── liblocalp2p_ffi.so    (~6.0 MB)
```

## 构建 APK

编译完 .so 文件后，可以构建 Android APK：

```bash
cd app

# 安装 Flutter 依赖（首次运行）
flutter pub get

# 构建 Debug APK（用于测试）
flutter build apk --debug

# 构建 Release APK（按架构分离，推荐）
flutter build apk --split-per-abi --release

# 构建 App Bundle（用于 Google Play 上架）
flutter build appbundle --release
```

生成的 APK 文件位置：

- **Debug**: `app/build/outputs/apk/debug/app-debug.apk`
- **Release**: `app/build/outputs/apk/release/app-arm64-v8a-release.apk` 等

## 构建参考

### 实际构建结果示例

```
========================================
  Android FFI 库编译 (cargo-ndk)
========================================

[1/3] 检查 cargo-ndk...
✓ cargo-ndk 已安装

[2/3] 检查 Android NDK...
✓ NDK 路径: /home/hezhihu89/develop/android/sdk/ndk/26.3.11579264

[3/3] 编译库文件...

开始编译...
    Building arm64-v8a (aarch64-linux-android)
    Finished `release` profile [optimized] target(s) in 21.18s
    Building armeabi-v7a (armv7-linux-androideabi)
    Finished `release` profile [optimized] target(s) in 18.51s
    Building x86_64 (x86_64-linux-android)
    Finished `release` [optimized] target(s) in 17.95s
    Building x86 (i686-linux-android)
    Finished `release` [optimized] target(s) in 19.19s

✓ 编译完成

生成的库文件:
  ✓ arm64-v8a/liblocalp2p_ffi.so (6.2M)
  ✓ armeabi-v7a/liblocalp2p_ffi.so (4.4M)
  ✓ x86_64/liblocalp2p_ffi.so (6.0M)
  ✓ x86/liblocalp2p_ffi.so (6.0M)

========================================
  构建完成！
========================================

库文件已生成到: /home/hezhihu89/develop/rust/program/localp2p/app/android/src/main/jniLibs
```

## 常见问题

### 1. cargo-ndk 未安装

**错误信息:**
```
错误: 未找到 cargo-ndk
请安装 cargo-ndk:
    cargo install cargo-ndk
```

**解决方案:**
```bash
cargo install cargo-ndk
```

---

### 2. Android NDK 路径未配置

**错误信息:**
```
错误: 未找到 Android NDK
```

**解决方案:**

方式一：设置环境变量
```bash
export ANDROID_NDK_HOME=$HOME/develop/android/sdk/ndk/26.3.11579264
```

方式二：确保 NDK 已安装
```bash
# Android Studio
Tools > SDK Manager > SDK Tools > Android NDK
```

---

### 3. 下载速度慢

**解决方案:**

设置代理加速下载：
```bash
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=http://127.0.0.1:7890
```

---

### 4. 缺少 Rust 目标架构

**错误信息:**
```
error: can't find crate for `core`
note: the `aarch64-linux-android` target may not be installed
```

**解决方案:**
```bash
rustup target add aarch64-linux-android \
  armv7-linux-androideabi \
  i686-linux-android \
  x86_64-linux-android
```

---

### 5. macOS 上的签名问题

**错误信息:**
```
cannot execute binary file
```

**解决方案:**

确保使用 Rosetta 2 运行 ARM64 工具链，或使用原生 ARM64 Rust。

---

### 6. Windows 上找不到 rustup

**错误信息:**
```
cargo: command not found
```

**解决方案:**

确保 Rust 已添加到系统 PATH 环境变量中：
1. 打开"系统属性" > "高级" > "环境变量"
2. 编辑 `Path` 变量，添加 Rust bin 路径（通常为 `%USERPROFILE%\.cargo\bin`）
3. 重启 PowerShell 或命令提示符

---

### 7. 编译警告

**警告信息:**
```
warning: field `event_tx` is never read
warning: creating a shared reference to mutable static
```

**说明:** 这些是正常的编译警告，不影响功能。可以忽略或在后续版本中修复。

---

### 8. Flutter 构建错误

**错误信息:**
```
Could not find liblocalp2p_ffi.so
```

**解决方案:**

1. 确认 .so 文件已正确生成到 `app/android/src/main/jniLibs/` 目录
2. 清理 Flutter 缓存：`flutter clean`
3. 重新获取依赖：`flutter pub get`
4. 重新构建：`flutter build apk`

## 脚本对比

| 特性 | build-android-ndk.sh | build-android.sh / .ps1 |
|------|---------------------|----------------------|
| 工具 | cargo-ndk | 原生 cargo |
| 速度 | 快 | 慢 |
| 难度 | 简单 | 复杂 |
| 推荐度 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 平台 | Linux/macOS | Linux/macOS/Windows |

**推荐使用 `build-android-ndk.sh`**，因为它更简单、更可靠。

## 高级用法

### 仅编译特定架构

```bash
# 仅编译 ARM 64 位
cargo ndk --target arm64-v8a --platform 21 -o app/android/src/main/jniLibs --manifest-path crates/ffi/Cargo.toml -- build

# 仅编译 ARM 32 位
cargo ndk --target armeabi-v7a --platform 21 -o app/android/src/main/jniLibs --manifest-path crates/ffi/Cargo.toml -- build

# 编译模拟器架构
cargo ndk --target x86_64 --target x86 --platform 21 -o app/android/src/main/jniLibs --manifest-path crates/ffi/Cargo.toml -- build
```

### 使用不同的 API Level

```bash
# 使用 API 28
cargo ndk --target arm64-v8a --platform 28 -o app/android/src/main/jniLibs --manifest-path crates/ffi/Cargo.toml -- build
```

## 相关链接

- [Rust Cross-Compilation](https://rust-lang.github.io/rustup/cross-compilation.html)
- [Android NDK](https://developer.android.com/ndk)
- [cargo-ndk](https://github.com/burtonageo/cargo-ndk)
- [Flutter FFI](https://docs.flutter.dev/development/platform-integration/platform-channels)
- [libp2p Documentation](https://docs.rs/libp2p/)

## 更新日志

- **v1.1** - 添加 cargo-ndk 支持，优化构建流程
- **v1.0** - 初始版本，支持标准交叉编译
