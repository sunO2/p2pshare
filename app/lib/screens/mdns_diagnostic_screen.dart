import 'package:flutter/material.dart';
import '../services/mdns_diagnostic_service.dart';
import '../services/log_service.dart';
import '../widgets/device_card.dart';

/// mDNS 诊断页面
///
/// 用于诊断和排查 mDNS 广播/接收问题
class MdnsDiagnosticScreen extends StatefulWidget {
  const MdnsDiagnosticScreen({super.key});

  @override
  State<MdnsDiagnosticScreen> createState() => _MdnsDiagnosticScreenState();
}

class _MdnsDiagnosticScreenState extends State<MdnsDiagnosticScreen> {
  final _diagnostic = MdnsDiagnosticService.instance;
  final _log = LogService.instance;

  bool _isRunning = false;
  MdnsDiagnosticStatus? _status;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    // 页面加载时自动运行诊断
    _runDiagnostic();
  }

  Future<void> _runDiagnostic() async {
    setState(() => _isRunning = true);

    try {
      final status = await _diagnostic.runFullDiagnostic();
      final suggestions = _diagnostic.getSuggestions();

      setState(() {
        _status = status;
        _suggestions = suggestions;
      });
    } catch (e) {
      _log.e('诊断失败: $e');
      setState(() {
        _status = MdnsDiagnosticStatus.error(e.toString());
      });
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('mDNS 诊断'),
        backgroundColor: const Color(0xFF3D8A5A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRunning ? null : _runDiagnostic,
            tooltip: '重新诊断',
          ),
        ],
      ),
      body: _isRunning
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D8A5A)),
                  ),
                  SizedBox(height: 16),
                  Text('正在诊断...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 诊断状态卡片
                  _buildStatusCard(),

                  const SizedBox(height: 16),

                  // 详细信息
                  _buildDetailsSection(),

                  const SizedBox(height: 16),

                  // 建议部分
                  _buildSuggestionsSection(),

                  const SizedBox(height: 16),

                  // 操作按钮
                  _buildActionButtons(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final isSuccess = _status?.isSuccess ?? false;
    final icon = isSuccess ? Icons.check_circle : Icons.error;
    final color = isSuccess ? const Color(0xFF3D8A5A) : Colors.red;
    final title = isSuccess ? '诊断通过' : '发现问题';
    final message = _status?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSuccess ? const Color(0xFFC8F0D8) : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: color,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    final results = _diagnostic.results;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Color(0xFF6D6C6A)),
                const SizedBox(width: 8),
                Text('详细信息', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...results.entries.map((entry) {
              final isValueTrue = entry.value == true;
              final icon = isValueTrue ? Icons.check : Icons.close;
              final iconColor = isValueTrue ? const Color(0xFF3D8A5A) : Colors.red;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatKey(entry.key),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          Text(
                            entry.value.toString(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 20, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text('建议', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ..._suggestions.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange[700],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.orange[900],
                            ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                _diagnostic.acquireMulticastLock();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已尝试获取 MulticastLock')),
                );
              },
              icon: const Icon(Icons.lock),
              label: const Text('手动获取 MulticastLock'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                _diagnostic.releaseMulticastLock();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已释放 MulticastLock')),
                );
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('释放 MulticastLock'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatKey(String key) {
    // 格式化 key，例如: wifiEnabled -> WiFi 已启用
    final mapping = {
      'isConnected': '网络已连接',
      'multicastLockHeld': 'MulticastLock 已获取',
      'wifiEnabled': 'WiFi 已启用',
      'ssid': 'WiFi 名称',
      'ipAddress': 'IP 地址',
      'frequency': 'WiFi 频率',
      'wifiName': 'WiFi 名称',
      'wifiIP': 'WiFi IP',
      'locationServiceRequired': '需要位置服务',
    };
    return mapping[key] ?? key;
  }
}
