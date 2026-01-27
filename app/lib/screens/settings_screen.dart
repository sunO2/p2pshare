import 'package:flutter/material.dart';
import '../p2p_manager.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
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
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E4E1))),
      ),
      child: Center(
        child: Text('设置', style: Theme.of(context).textTheme.displayMedium),
      ),
    );
  }

  Widget _buildContent(String deviceName, String peerId) {
    return Container(
      color: const Color(0xFFF5F4F1),
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
}
