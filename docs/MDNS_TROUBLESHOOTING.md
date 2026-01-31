# mDNS 广播故障排查指南

## 问题现象
部分 Android 设备上 mDNS 广播无法发送或接收。

---

## 一、常见原因

### 1. 缺少 MulticastLock（最常见）

mDNS 使用 UDP 组播（224.0.0.251:5353），Android 需要显式获取 `MulticastLock` 才能发送/接收组播流量。

**症状**：
- `tcpdump` 看不到任何 mDNS 包
- App 日志显示注册成功，但其他设备无法发现
- 某些厂商手机（小米、华为）更容易出现

**检查方法**：
```bash
# 检查是否持有 MulticastLock
adb shell dumpsys wifi | grep -A5 "MulticastLock"
```

### 2. 厂商 ROM 限制

| 厂商 | 限制类型 | 解决方案 |
|------|----------|----------|
| **小米 (MIUI)** | 后台网络限制 | 设置 → 应用管理 → localp2p → 省电策略 → 无限制 |
| **华为 (EMUI)** | mDNS 被安全策略拦截 | 设置 → 应用 → 应用启动管理 → localp2p → 自动管理（关闭） |
| **OPPO/OnePlus** | ColorOS 限制 | 设置 → 电池 → 耗电详情 → localp2p → 允许后台运行 |
| **Vivo** | FuntouchOS 限制 | 设置 → 电池 → 后台耗电管理 → localp2p → 允许 |
| **三星** | Knox 安全策略 | 可能需要设备管理员权限 |

### 3. WiFi 睡眠策略

**症状**：屏幕关闭后 mDNS 停止工作

**检查**：
```bash
adb shell settings get global wifi_sleep_policy
# 0=始终休眠, 1=充电时休眠, 2=永不休眠
```

**解决**：引导用户设置 WiFi 始终保持开启

### 4. VPN 干扰

**症状**：VPN 开启后 mDNS 失效

**原因**：VPN 会劫持所有网络流量，mDNS 组播被拦截

**检测**：
```bash
adb shell settings list global | grep vpn
adb shell dumpsys connectivity | grep -i vpn
```

### 5. 飞行模式 + WiFi

某些手机在飞行模式+WiFi开启状态下会禁用 mDNS。

### 6. Android 版本差异

| Android 版本 | mDNS 行为 |
|--------------|-----------|
| Android 8.x  | 部分设备需要 MulticastLock |
| Android 9+   | 后台限制更严格，需要前台服务 |
| Android 10+  | 需要 `ACCESS_FINE_LOCATION` 权限才能扫描 mDNS |
| Android 12+  | 需要 `ACCESS_NEARBY_DEVICES` 权限 |

---

## 二、诊断步骤

### 步骤 1: 验证权限

```dart
// 在 Flutter 中检查权限
import 'package:permission_handler/permission_handler.dart';

Future<void> checkPermissions() async {
  // Android 10+ 需要位置权限
  if (await Permission.location.isDenied) {
    await Permission.location.request();
  }

  // Android 12+ 需要附近设备权限
  if (await Permission.nearbyDevices.isDenied) {
    await Permission.nearbyDevices.request();
  }

  // 检查 WiFi 状态
  if (await Permission.location.serviceStatus.isDisabled) {
    // 必须开启位置服务才能使用 mDNS
    openAppSettings();
  }
}
```

### 步骤 2: 检查 MulticastLock

创建原生 Android 代码获取锁：

```kotlin
// MulticastLockManager.kt
package com.example.localp2p

import android.content.Context
import android.net.wifi.WifiManager
import android.os.PowerManager

class MulticastLockManager(private val context: Context) {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    fun acquire() {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        multicastLock = wifiManager.createMulticastLock("localp2p_mdns").apply {
            setReferenceCounted(true)
            acquire()
        }

        // 可选：保持 CPU 唤醒
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "localp2p:wake"
        ).apply {
            acquire(10*60*1000L) // 10分钟
        }
    }

    fun release() {
        multicastLock?.release()
        wakeLock?.release()
    }
}
```

### 步骤 3: 添加详细日志

```dart
class FlutterMdnsService {
  Future<bool> registerService({...}) async {
    try {
      _log.i('[mDNS] ===== 开始注册服务 =====');
      _log.i('[mDNS] 设备信息:');
      _log.i('[mDNS]   - 名称: $name');
      _log.i('[mDNS]   - 端口: $port');
      _log.i('[mDNS]   - 类型: $serviceType');

      // 检查网络状态
      final connectivityResult = await Connectivity().checkConnectivity();
      _log.i('[mDNS] 网络状态: $connectivityResult');

      if (connectivityResult.isEmpty) {
        _log.e('[mDNS] ❌ 无网络连接！');
        return false;
      }

      // 注册服务...
      _registration = await nsd_pkg.register(service);

      _log.i('[mDNS] ===== 注册成功 =====');

      // 验证：尝试自己发现自己
      _log.i('[mDNS] 开始自我验证（尝试发现自己）...');
      // ... 自我发现逻辑

      return true;
    } catch (e, stackTrace) {
      _log.e('[mDNS] ===== 注册失败 =====');
      _log.e('[mDNS] 错误: $e');
      return false;
    }
  }
}
```

### 步骤 4: 使用 tcpdump 验证

```bash
# 在测试设备上（需要 root）
adb root
adb shell tcpdump -i any port 5353 -vv | grep localp2p

# 如果没有输出，说明广播没有发出
# 如果有输出但其他设备收不到，说明是接收端问题
```

---

## 三、解决方案

### 方案 A: 添加原生 MulticastLock

修改 `MainActivity.kt`：

```kotlin
package com.example.localp2p

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.net.wifi.WifiManager
import android.content.Context

class MainActivity: FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 获取 MulticastLock
        acquireMulticastLock()
    }

    private fun acquireMulticastLock() {
        val wifiManager = getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("localp2p_mdns").apply {
            setReferenceCounted(true)
            acquire()
        }
    }

    override fun onDestroy() {
        multicastLock?.release()
        super.onDestroy()
    }
}
```

### 方案 B: 使用前台服务

对于 Android 9+，建议使用前台服务：

```xml
<!-- AndroidManifest.xml -->
<service
    android:name=".MdnsForegroundService"
    android:enabled="true"
    android:exported="false"
    android:foregroundServiceType="connectedDevice" />
```

### 方案 C: 回退到 Rust mDNS

如果 Flutter mDNS 在某些设备上不可靠，可以完全依赖 Rust 端的 mDNS（libmdns/mdns-sd），因为它在原生层运行，限制更少。

---

## 四、用户引导文案

在 App 设置中添加诊断页面：

```
mDNS 发现功能需要以下条件：

✓ WiFi 已连接
✓ 位置服务已开启（Android 要求）
✓ App 已授予位置权限
✓ App 未被省电优化限制

常见问题：
• 小米/红米手机：设置 → 应用管理 → 本应用 → 省电策略 → 无限制
• 华为手机：设置 → 应用 → 应用启动管理 → 本应用 → 关闭自动管理
• OPPO/Vivo：设置 → 电池 → 耗电保护 → 允许后台运行

诊断按钮：[测试 mDNS] [查看详细日志]
```

---

## 五、快速诊断脚本

```bash
#!/bin/bash
# mdns_diagnose.sh

echo "=== mDNS 诊断 ==="

echo "1. 检查 WiFi 状态"
adb shell dumpsys wifi | grep "Wi-Fi is enabled"

echo "2. 检查 MulticastLock"
adb shell dumpsys wifi | grep -A2 "MulticastLock"

echo "3. 检查位置服务"
adb shell settings get secure location_mode

echo "4. 检查 VPN"
adb shell settings list global | grep vpn

echo "5. 监听 mDNS 流量（10秒）"
timeout 10 adb shell tcpdump -i any port 5353 -vv 2>/dev/null | grep -i local || echo "未检测到 mDNS 流量"
```

---

## 六、建议的改进优先级

| 优先级 | 改进项 | 影响 |
|--------|--------|------|
| 🔴 高 | 添加 MulticastLock | 修复大部分问题 |
| 🔴 高 | 检查位置权限 | Android 10+ 必需 |
| 🟡 中 | 添加诊断页面 | 用户自助排查 |
| 🟡 中 | 前台服务 | Android 9+ 后台稳定性 |
| 🟢 低 | 用户引导文档 | 减少支持压力 |
