import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../p2p_manager.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../widgets/unified_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _autoScanEnabled = false;
  String _localPeerId = '';
  String _deviceName = '';
  String _nickname = '';
  String _status = '在线';
  int _logFileSize = 0;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _loadLogInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final localPeerId = P2PManager.instance.getLocalPeerId();
      final deviceName = P2PManager.instance.getDeviceName();

      // 从存储服务读取昵称和状态
      final nickname = StorageService.instance.getNickname() ?? '未设置';
      final status = StorageService.instance.getStatus() ?? '在线';

      if (mounted) {
        setState(() {
          _localPeerId = localPeerId;
          _deviceName = deviceName;
          _nickname = nickname;
          _status = status;
        });
      }
    } catch (e) {
      debugPrint('Failed to load device info: $e');
    }
  }

  Future<void> _loadLogInfo() async {
    final size = await LogService.instance.getLogFileSize();
    if (mounted) {
      setState(() {
        _logFileSize = size;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header - use UnifiedAppBar
              const UnifiedAppBar(title: '设置', showBackButton: false),

              // Content
              Expanded(child: _buildContent(_deviceName, _localPeerId)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(String deviceName, String peerId) {
    return Container(
      color: const Color(0xFFF8F8F6),
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          // Profile Card
          _buildProfileCard(deviceName, peerId),
          const SizedBox(height: 20),

          // Device Settings
          Text('设备设置', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildDeviceSettingsCard(),
          const SizedBox(height: 20),

          // User Profile Settings
          Text('用户资料', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildUserProfileCard(),
          const SizedBox(height: 20),

          // App Settings
          Text('应用设置', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildAppSettingsCard(),
          const SizedBox(height: 20),

          // Debug Settings
          Text('调试', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildDebugCard(),
        ],
      ),
    );
  }

  Widget _buildProfileCard(String deviceName, String peerId) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF3D8A5A),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _shortenPeerId(peerId),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildSettingsRow(
            '设备名称',
            _deviceName,
            onTap: () =>
                _showEditDialog('设备名称', _deviceName, isDeviceName: true),
          ),
          _buildDivider(),
          _buildSettingsRow(
            'Peer ID',
            _shortenPeerId(_localPeerId),
            showArrow: false,
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfileCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildSettingsRow(
            '昵称',
            _nickname,
            onTap: () => _showEditDialog(
              '昵称',
              _nickname == '未设置' ? '' : _nickname,
              isNickname: true,
            ),
          ),
          _buildDivider(),
          _buildSettingsRow('状态', _status, onTap: () => _showStatusDialog()),
        ],
      ),
    );
  }

  Widget _buildAppSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildToggleRow(
            '通知',
            _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
            },
          ),
          _buildDivider(),
          _buildToggleRow(
            '自动扫描设备',
            _autoScanEnabled,
            onChanged: (value) {
              setState(() => _autoScanEnabled = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDebugCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildSettingsRow(
            '日志文件大小',
            _formatFileSize(_logFileSize),
            showArrow: false,
          ),
          _buildDivider(),
          _buildSettingsRow('查看日志', '按日期查看日志', onTap: _showLogs),
          _buildDivider(),
          _buildSettingsRow('清空日志', '清空所有日志', onTap: _clearLogs),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(
    String label,
    String value, {
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(16),
        bottom: Radius.circular(16),
      ),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: label == '状态'
                    ? const Color(0xFF3D8A5A)
                    : const Color(0xFF6D6C6A),
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 12),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFA8A7A5),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(
    String label,
    bool value, {
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value
                    ? const Color(0xFF3D8A5A)
                    : const Color(0xFFEDECEA),
                borderRadius: BorderRadius.circular(100),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 18),
      color: const Color(0xFFE5E4E1),
    );
  }

  String _shortenPeerId(String peerId) {
    if (peerId.length > 12) {
      return '${peerId.substring(0, 10)}...';
    }
    return peerId;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  void _showEditDialog(
    String title,
    String currentValue, {
    bool isDeviceName = false,
    bool isNickname = false,
  }) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: title == '昵称' ? '请输入昵称（可选）' : '请输入$title',
          ),
          maxLength: title == '设备名称' ? 20 : 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final newValue = controller.text.trim();
              Navigator.pop(context);

              // 验证输入
              if (isDeviceName && newValue.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('设备名称不能为空')));
                }
                return;
              }

              try {
                if (isDeviceName) {
                  // 保存设备名称
                  await StorageService.instance.setDeviceName(newValue);
                  if (mounted) {
                    setState(() {
                      _deviceName = newValue;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('设备名称已更新，重启应用后生效')),
                    );
                  }
                } else if (isNickname) {
                  // 保存昵称
                  if (newValue.isEmpty) {
                    await StorageService.instance.setNickname(null);
                    if (mounted) {
                      setState(() {
                        _nickname = '未设置';
                      });
                    }
                  } else {
                    await StorageService.instance.setNickname(newValue);
                    if (mounted) {
                      setState(() {
                        _nickname = newValue;
                      });
                    }
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('昵称已更新')));
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showStatusDialog() {
    final statuses = ['在线', '忙碌', '离开', '隐身'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择状态'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses.map((status) {
            return ListTile(
              title: Text(status),
              trailing: _status == status
                  ? const Icon(Icons.check, color: Color(0xFF3D8A5A))
                  : null,
              onTap: () async {
                Navigator.pop(context);
                try {
                  await StorageService.instance.setStatus(status);
                  if (mounted) {
                    setState(() {
                      _status = status;
                    });
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('状态已更改为: $status')));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                  }
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 查看日志
  Future<void> _showLogs() async {
    try {
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LogsViewerScreen()),
      );

      // 刷新日志大小
      _loadLogInfo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开日志页面失败: $e')));
      }
    }
  }

  /// 清空日志
  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有日志吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LogService.instance.clearLogs();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('日志已清空')));
          _loadLogInfo();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('清空失败: $e')));
        }
      }
    }
  }
}

/// 日志查看器页面 - 按日期选择，实时读取
class LogsViewerScreen extends StatefulWidget {
  const LogsViewerScreen({super.key});

  @override
  State<LogsViewerScreen> createState() => _LogsViewerScreenState();
}

class _LogsViewerScreenState extends State<LogsViewerScreen> {
  String _selectedDate = '';
  List<String> _availableDates = [];
  List<LogLine> _logLines = []; // 🔥 使用 LogLine 而不是分别存储 Flutter/Rust
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();
  bool _showFlutterLogs = true;
  bool _showRustLogs = true;
  bool _isRealtimeWatching = false; // 🔥 是否正在实时监听
  StreamSubscription<LogLine>? _realtimeSubscription; // 🔥 实时日志流订阅

  @override
  void initState() {
    super.initState();
    _initDates();
  }

  @override
  void dispose() {
    _stopRealtimeWatch();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initDates() async {
    try {
      final dates = await LogService.instance.getAvailableDates();
      if (mounted) {
        setState(() {
          _availableDates = dates;
          if (dates.isNotEmpty) {
            _selectedDate = dates.first;
          }
        });
        if (_selectedDate.isNotEmpty) {
          await _loadInitialLogs();
          _startRealtimeWatch();
        }
      }
    } catch (e) {
      debugPrint('Failed to load dates: $e');
    }
  }

  /// 🔥 加载初始日志（历史日志）
  Future<void> _loadInitialLogs() async {
    if (_selectedDate.isEmpty) return;

    try {
      final flutterLogs = await LogService.instance.getLogsByDate(_selectedDate, LogType.flutter);
      final rustLogs = await LogService.instance.getLogsByDate(_selectedDate, LogType.rust);

      if (mounted) {
        setState(() {
          _logLines = [
            ...flutterLogs.map((log) => LogLine(
                  content: log,
                  type: LogType.flutter,
                  timestamp: DateTime.now(),
                )),
            ...rustLogs.map((log) => LogLine(
                  content: log,
                  type: LogType.rust,
                  timestamp: DateTime.now(),
                )),
          ];
          // 按时间戳排序
          _logLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        });

        // 滚动到底部
        if (_autoScroll) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Failed to load logs: $e');
    }
  }

  /// 🔥 开始实时监听日志
  void _startRealtimeWatch() {
    if (_isRealtimeWatching) return;

    _isRealtimeWatching = true;

    // 启动 LogService 的实时监听
    LogService.instance.startRealtimeWatch(_selectedDate);

    // 订阅实时日志流
    _realtimeSubscription = LogService.instance.realtimeLogStream.listen(
      (logLine) {
        if (!mounted) return;

        // 根据过滤条件决定是否添加
        if (logLine.type == LogType.flutter && !_showFlutterLogs) return;
        if (logLine.type == LogType.rust && !_showRustLogs) return;

        setState(() {
          _logLines.add(logLine);
        });

        // 如果启用了自动滚动，滚动到底部
        if (_autoScroll) {
          _scrollToBottom();
        }
      },
      onError: (error) {
        debugPrint('Realtime log stream error: $error');
      },
    );
  }

  /// 🔥 停止实时监听
  void _stopRealtimeWatch() {
    _isRealtimeWatching = false;
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    LogService.instance.stopRealtimeWatch();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('日志查看'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: [
            // 🔥 实时监听开关（绿色=正在监听，灰色=已暂停）
            IconButton(
              icon: Icon(_isRealtimeWatching ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  if (_isRealtimeWatching) {
                    _stopRealtimeWatch();
                  } else {
                    _startRealtimeWatch();
                  }
                });
              },
              tooltip: _isRealtimeWatching ? '暂停监听' : '开始监听',
              color: _isRealtimeWatching ? const Color(0xFF3D8A5A) : Colors.grey,
            ),
            // 自动滚动开关
            IconButton(
              icon: Icon(_autoScroll ? Icons.arrow_downward : Icons.arrow_downward_outlined),
              onPressed: () {
                setState(() {
                  _autoScroll = !_autoScroll;
                  if (_autoScroll) _scrollToBottom();
                });
              },
              tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
              color: _autoScroll ? const Color(0xFF3D8A5A) : Colors.grey,
            ),
            // 日志类型过滤
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              tooltip: '过滤',
              onSelected: (value) {
                setState(() {
                  if (value == 'flutter') {
                    _showFlutterLogs = !_showFlutterLogs;
                  } else if (value == 'rust') {
                    _showRustLogs = !_showRustLogs;
                  }
                });
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'flutter',
                  checked: _showFlutterLogs,
                  child: const Text('Flutter 日志'),
                ),
                CheckedPopupMenuItem(
                  value: 'rust',
                  checked: _showRustLogs,
                  child: const Text('Rust 日志'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // 日期选择器
            _buildDateSelector(),
            // 日志内容
            Expanded(
              child: _buildLogsContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 20, color: Color(0xFF3D8A5A)),
          const SizedBox(width: 12),
          const Text('选择日期:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDate,
                isExpanded: true,
                items: _availableDates.map((date) {
                  return DropdownMenuItem<String>(
                    value: date,
                    child: Text(date, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value != null && value != _selectedDate) {
                    // 🔥 切换日期时，先停止实时监听
                    _stopRealtimeWatch();

                    setState(() {
                      _selectedDate = value;
                      _logLines.clear(); // 清空当前日志
                    });

                    // 加载新日期的日志
                    await _loadInitialLogs();

                    // 重新启动实时监听
                    _startRealtimeWatch();
                  }
                },
              ),
            ),
          ),
          if (_availableDates.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () async {
                // 🔥 刷新时重新加载日志
                _stopRealtimeWatch();
                setState(() {
                  _logLines.clear();
                });
                await _loadInitialLogs();
                _startRealtimeWatch();
              },
              tooltip: '刷新',
            ),
        ],
      ),
    );
  }

  Widget _buildLogsContent() {
    // 🔥 过滤日志行
    final filteredLogs = _logLines.where((logLine) {
      if (logLine.type == LogType.flutter && !_showFlutterLogs) return false;
      if (logLine.type == LogType.rust && !_showRustLogs) return false;
      return true;
    }).toList();

    if (filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _availableDates.isEmpty ? '没有可用的日志文件' : '没有日志内容',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: filteredLogs.length,
        itemBuilder: (context, index) {
          final logLine = filteredLogs[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              logLine.content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: logLine.type == LogType.flutter
                    ? const Color(0xFF7CB9E8) // Flutter 日志用蓝色
                    : const Color(0xFFD4D4D4), // Rust 日志用灰色
              ),
            ),
          );
        },
      ),
    );
  }
}
