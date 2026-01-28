import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../p2p_manager.dart';
import '../services/log_service.dart';

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
      if (mounted) {
        setState(() {
          _localPeerId = localPeerId;
          _deviceName = deviceName;
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
    return Scaffold(
      body: Column(
        children: [
          // Header
          _buildHeader(),

          // Content
          Expanded(child: _buildContent(_deviceName, _localPeerId)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '设置',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 26,
              fontWeight: FontWeight.normal,
              color: Color(0xFF1A1918),
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {},
                child: const Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: Color(0xFF6D6C6A),
                ),
              ),
            ),
          ),
        ],
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
            onTap: () => _showEditDialog('设备名称', _deviceName),
          ),
          _buildDivider(),
          _buildSettingsRow(
            '昵称',
            '未设置',
            onTap: () => _showEditDialog('昵称', ''),
          ),
          _buildDivider(),
          _buildSettingsRow('状态', '在线', showArrow: false),
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
          _buildSettingsRow('导出日志', '导出所有日志', onTap: _exportLogs),
          _buildDivider(),
          _buildSettingsRow('查看日志', '最近 500 条', onTap: _showLogs),
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

  void _showEditDialog(String title, String currentValue) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              // TODO: Save the value
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$title 已更新')));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 导出日志
  Future<void> _exportLogs() async {
    try {
      final logs = await LogService.instance.getAllLogs();

      if (logs.isEmpty || logs == '日志文件不存在') {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('没有可导出的日志')));
        }
        return;
      }

      // 使用 share_plus 分享日志
      await Share.share(logs, subject: 'LocalP2P Logs');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日志已导出')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  /// 查看日志
  Future<void> _showLogs() async {
    try {
      final logs = await LogService.instance.getRecentLogs(lines: 500);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => _LogsViewerScreen(logs: logs)),
      );

      // 刷新日志大小
      _loadLogInfo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取日志失败: $e')));
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

/// 日志查看器页面
class _LogsViewerScreen extends StatefulWidget {
  final String logs;

  const _LogsViewerScreen({required this.logs});

  @override
  State<_LogsViewerScreen> createState() => _LogsViewerScreenState();
}

class _LogsViewerScreenState extends State<_LogsViewerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareLogs,
            tooltip: '分享',
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF1E1E1E),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            widget.logs,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFD4D4D4),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareLogs() async {
    try {
      await Share.share(widget.logs, subject: 'LocalP2P Logs');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
      }
    }
  }
}
