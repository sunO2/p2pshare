# mDNS 广播测试指南

本文档包含用于测试 localp2p 应用 mDNS 发现功能的命令。

## 前置准备

### 安装工具

```bash
# Ubuntu/Debian
sudo apt-get install avahi-utils tcpdump

# Fedora
sudo dnf install avahi-tools tcpdump

# Arch Linux
sudo pacman -S avahi tcpdump
```

---

## 一、扫描/接收广播命令

### 1.1 浏览所有 localp2p 服务

```bash
# 基本浏览
avahi-browse -r _localp2p._tcp

# 详细模式（显示 TXT 记录）
avahi-browse -r _localp2p._tcp -v

# 解析模式（显示完整信息）
avahi-browse -a _localp2p._tcp --resolve
```

### 1.2 监听 mDNS 流量（推荐）

```bash
# 监听所有 mDNS 流量（端口 5353）
sudo tcpdump -i any port 5353 -vv

# 只显示 localp2p 相关的流量
sudo tcpdump -i any port 5353 -vv | grep localp2p

# 保存到文件用于分析
sudo tcpdump -i any port 5353 -vv -w mdns_capture.pcap

# 实时显示 + 保存
sudo tcpdump -i any port 5353 -vv -w mdns_capture.pcap | tee mdns_log.txt
```

### 1.3 使用 mdns-scan 工具（可选）

```bash
# 安装
sudo apt-get install mdns-scan

# 扫描局域网 mDNS 服务
sudo mdns-scan
```

---

## 二、模拟发送广播命令

### 2.1 基本广播模拟

```bash
# 格式: avahi-publish -s "服务名" _服务类型._协议 端口 "TXT记录"
avahi-publish -s "TestDevice-Android" _localp2p._tcp 37845 "peer=12D3KooWABC123"
```

### 2.2 模拟不同设备

```bash
# Android 设备
avahi-publish -s "Android-Phone" _localp2p._tcp 37845 "peer=12D3KooWAndroid123"

# iOS 设备
avahi-publish -s "iPhone-Test" _localp2p._tcp 37845 "peer=12D3KooWiOSTest456"

# Linux 设备
avahi-publish -s "Linux-Desktop" _localp2p._tcp 37845 "peer=12D3KooWLinux789"
```

### 2.3 带 protocol_version 的广播（完整模拟）

```bash
# localp2p 实际格式
avahi-publish -s "TestDevice" _localp2p._tcp 37845 \
  "peer=12D3KooWTestPeerId123456" \
  "protocol_version=/localp2p/1.0.0"
```

### 2.4 后台持续广播

```bash
# 在后台运行，关闭终端继续广播
nohup avahi-publish -s "TestDevice" _localp2p._tcp 37845 "peer=12D3KooWTest" > /dev/null 2>&1 &

# 查看进程
ps aux | grep avahi-publish

# 停止广播
pkill avahi-publish
```

---

## 三、完整测试流程

### 3.1 场景一：测试 App 接收广播

```bash
# 终端 1: 启动 mDNS 流量监控
sudo tcpdump -i any port 5353 -vv | grep localp2p

# 终端 2: 启动服务浏览
avahi-browse -r _localp2p._tcp --resolve

# 终端 3: 发送模拟广播（启动 App 后执行）
avahi-publish -s "TestDevice-Linux" _localp2p._tcp 37845 "peer=12D3KooWTestDevice123"
```

### 3.2 场景二：多设备同时测试

```bash
# 终端 1-3: 启动多个模拟设备
avahi-publish -s "Device-1" _localp2p._tcp 37845 "peer=12D3KooWDevice1111" &
avahi-publish -s "Device-2" _localp2p._tcp 37846 "peer=12D3KooWDevice2222" &
avahi-publish -s "Device-3" _localp2p._tcp 37847 "peer=12D3KooWDevice3333" &

# 观察是否能发现多个设备
avahi-browse -r _localp2p._tcp --resolve
```

### 3.3 场景三：验证广播 TTL

```bash
# 发送广播并观察持续时长
timeout 30 avahi-publish -s "TempDevice" _localp2p._tcp 37845 "peer=12D3KooWTemp"

# 在另一个终端持续浏览
watch -n 1 'avahi-browse -r _localp2p._tcp | grep TempDevice'
```

---

## 四、调试技巧

### 4.1 检查 Avahi 服务状态

```bash
# 检查 avahi-daemon 是否运行
systemctl status avahi-daemon

# 启动/重启服务
sudo systemctl start avahi-daemon
sudo systemctl restart avahi-daemon

# 查看日志
journalctl -u avahi-daemon -f
```

### 4.2 网络接口检查

```bash
# 查看所有网络接口
ip addr show

# 只查看 mDNS 相关接口
avahi-browse -a | grep -E "Interface|eth0|wlan0"

# 指定接口浏览
avahi-browse -r _localp2p._tcp -i wlan0
```

### 4.3 故障排查

```bash
# 检查防火墙（UDP 5353）
sudo ufw status
sudo iptables -L -n | grep 5353

# 如果被阻止，允许 mDNS 流量
sudo ufw allow 5353/udp
```

---

## 五、常用命令速查

| 命令 | 功能 |
|------|------|
| `avahi-browse -r _localp2p._tcp` | 浏览 localp2p 服务 |
| `avahi-browse -a _localp2p._tcp --resolve` | 浏览并解析详细信息 |
| `sudo tcpdump -i any port 5353 -vv` | 监听 mDNS 流量 |
| `avahi-publish -s "名" _localp2p._tcp 端口 "peer=xxx"` | 发布模拟广播 |
| `pkill avahi-publish` | 停止所有模拟广播 |
| `systemctl status avahi-daemon` | 检查 mDNS 服务状态 |

---

## 六、真实设备广播示例

```
服务名: Android-a3f2c1d4
类型: _localp2p._tcp
端口: 37845
TXT 记录:
  peer=12D3KooWQmZnF8jKpVxG3hR9dY2sT7nB4vC6xM1pL2
  protocol_version=/localp2p/1.0.0
```

用命令模拟：

```bash
avahi-publish -s "Android-a3f2c1d4" _localp2p._tcp 37845 \
  "peer=12D3KooWQmZnF8jKpVxG3hR9dY2sT7nB4vC6xM1pL2" \
  "protocol_version=/localp2p/1.0.0"
```
