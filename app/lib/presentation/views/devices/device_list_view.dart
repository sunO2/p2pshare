import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../widgets/device_card.dart';
import '../../../widgets/unified_app_bar.dart';
import '../../../p2p_manager.dart';
import '../../../bridge/bridge.dart';
import '../../../core/theme/app_theme.dart';
import '../../controllers/device_controller.dart';

/// 设备列表视图 - GetX 版本
///
/// 基于 screens/device_list_screen.dart 转换
/// 功能：设备列表、搜索、刷新、服务状态、广播信息
class DeviceListView extends GetView<DeviceController> {
  const DeviceListView({super.key});

  @override
  Widget build(BuildContext context) {
    // 首次布局后计算 info 按钮位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.calculateInfoButtonPosition();
    });

    return Stack(
      key: controller.stackKey,
      children: [
        // 主内容 - 不使用 SafeArea，直接让 Column 从顶部开始
        Column(
          children: [
            // 导航头 - 使用与 UnifiedAppBar 相同的高度计算
            _buildTopBar(context),

            // 扩展内容区域（服务状态、搜索、在线设备标题）
            _buildExtendedContent(context),

            // 内容区域
            Expanded(
              child: Obx(() {
                if (controller.filteredNodes.isEmpty) {
                  return _buildEmptyState(context);
                }
                return _buildDeviceList();
              }),
            ),
          ],
        ),
        // 广播信息悬浮浮层
        Obx(() {
          if (controller.showBroadcastInfoPopup.value) {
            return _buildBroadcastInfoPopup(context);
          }
          return const SizedBox.shrink();
        }),
        // Info 按钮（Positioned 放在 Stack 末尾，z-index 最高）
        Obx(() {
          if (controller.infoButtonPosition.value != null) {
            return _buildPositionedInfoButton(context);
          }
          return const SizedBox.shrink();
        }),
      ],
    );
  }

  /// 构建顶部导航栏（与 UnifiedAppBar 相同的高度）
  Widget _buildTopBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final totalHeight = 70.0 + topPadding;

    return Container(
      height: totalHeight,
      padding: EdgeInsets.only(
        top: topPadding,
        left: 24,
        right: 24,
        bottom: 16,
      ),
      decoration: const BoxDecoration(color: Color(0xFFF8F8F6)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('我的设备', style: context.appTextTheme.appBarTitle),
              const SizedBox(height: 4),
              Obx(() => Text(
                '发现 ${controller.nodes.length} 个设备',
                style: context.appTextTheme.bodyMedium,
              )),
            ],
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
                onTap: () {
                  // 切换到设置tab
                  final homeController = Get.find(tag: 'home');
                  if (homeController != null) {
                    // This would need HomeController to have changeTab method accessible
                  }
                },
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

  /// 构建扩展内容区域（服务状态、搜索、在线设备标题）
  Widget _buildExtendedContent(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F8F6),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // 服务状态显示
          _buildServiceStatusSection(context),
          const SizedBox(height: 16),

          // 搜索栏
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCCCCC)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    onChanged: controller.updateSearchQuery,
                    decoration: const InputDecoration(
                      hintText: '搜索设备...',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF9C9B99),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 在线设备标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('在线设备', style: context.appTextTheme.displaySmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusIndicator(context),
                  const SizedBox(width: 12),
                  // 刷新按钮
                  Obx(() => InkWell(
                    onTap: controller.isRefreshing.value ? null : controller.refreshDevices,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: controller.isRefreshing.value
                            ? Colors.grey[300]
                            : const Color(0xFFC8F0D8).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: controller.isRefreshing.value
                              ? Colors.grey[400]!
                              : const Color(0xFF3D8A5A).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 16,
                            color: controller.isRefreshing.value
                                ? Colors.grey[500]
                                : const Color(0xFF3D8A5A),
                          ),
                          if (controller.isRefreshing.value) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.grey[500]!,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFC8F0D8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF3D8A5A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '在线',
            style: context.appTextTheme.labelSmall?.copyWith(color: const Color(0xFF3D8A5A)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Obx(() => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            controller.searchQuery.value.isEmpty ? '正在扫描局域网内的设备...' : '未找到匹配的设备',
            style: const TextStyle(fontSize: 15, color: Color(0xFF6D6C6A)),
          ),
        ],
      ),
    ));
  }

  Widget _buildDeviceList() {
    return Obx(() => ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: controller.filteredNodes.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final node = controller.filteredNodes[index];
        return DeviceCard(
          node: node,
          onTap: () => controller.openChat(node),
          onAvatarTap: () => controller.openDeviceDetail(node),
          onChatTap: () => controller.openChat(node),
        );
      },
    ));
  }

  /// 构建服务状态显示组件
  Widget _buildServiceStatusSection(BuildContext context) {
    return Obx(() {
      if (controller.serviceStatus.isEmpty) {
        return const SizedBox.shrink();
      }

      final mdnsStatus = controller.serviceStatus['mDNS'];
      final connectionStatus = controller.serviceStatus['Connection'];

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_ethernet, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  '服务状态',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                // Info 按钮占位符（用于定位）
                SizedBox(
                  key: controller.infoPlaceholderKey,
                  width: 28,
                  height: 28,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 服务状态卡片
            Row(
              children: [
                if (mdnsStatus != null)
                  Expanded(
                    child: _buildServiceStatusCard(
                      context,
                      title: 'mDNS',
                      status: mdnsStatus,
                    ),
                  ),
                if (mdnsStatus != null && connectionStatus != null)
                  const SizedBox(width: 12),
                if (connectionStatus != null)
                  Expanded(
                    child: _buildServiceStatusCard(
                      context,
                      title: '连接',
                      status: connectionStatus,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }

  /// 构建单个服务状态卡片
  Widget _buildServiceStatusCard(
    BuildContext context, {
    required String title,
    required ServiceStatusData status,
  }) {
    // 根据健康状态选择颜色
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (!status.isRunning) {
      statusColor = const Color(0xFFD32F2F); // Red
      statusText = '未运行';
      statusIcon = Icons.error_outline;
    } else {
      switch (status.health) {
        case 'healthy':
          statusColor = const Color(0xFF3D8A5A); // Green
          statusText = '正常';
          statusIcon = Icons.check_circle_outline;
          break;
        case 'degraded':
          statusColor = const Color(0xFFF57C00); // Orange
          statusText = '降级';
          statusIcon = Icons.warning_outlined;
          break;
        case 'unhealthy':
          statusColor = const Color(0xFFD32F2F); // Red
          statusText = '异常';
          statusIcon = Icons.error_outline;
          break;
        default:
          statusColor = const Color(0xFF9E9E9E); // Grey
          statusText = '未知';
          statusIcon = Icons.help_outline;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (status.message != null) ...[
            const SizedBox(height: 2),
            Text(
              status.message!,
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// 构建广播信息悬浮浮层（无蒙层，从按钮缩放展开）
  Widget _buildBroadcastInfoPopup(BuildContext context) {
    return Obx(() {
      final info = controller.broadcastInfo.value;
      // 如果没有广播信息，显示加载中
      if (info == null) {
        return const Positioned(child: SizedBox.shrink());
      }

      // 获取 Stack 和占位符的 RenderBox
      final RenderBox? stackBox =
          controller.stackKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? placeholderBox =
          controller.infoPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;

      if (stackBox == null || placeholderBox == null) {
        return const Positioned(child: SizedBox.shrink());
      }

      // 获取占位符相对于 Stack 的位置（使用 globalToLocal 转换）
      final placeholderGlobalPosition = placeholderBox.localToGlobal(Offset.zero);
      final placeholderLocalPosition = stackBox.globalToLocal(placeholderGlobalPosition);
      final placeholderSize = placeholderBox.size;

      const popupWidth = 320.0;

      return AnimatedBuilder(
        animation: controller.popupAnimationController,
        builder: (context, child) {
          return Positioned(
            // 位置：往右 16，往上 16
            left: placeholderLocalPosition.dx + placeholderSize.width - popupWidth + 16,
            top: placeholderLocalPosition.dy - 16,
            child: Transform.scale(
              scale: controller.scaleAnimation.value,
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: popupWidth,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题栏
                      Row(
                        children: [
                          Icon(Icons.wifi_tethering, color: const Color(0xFF3D8A5A), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            '广播信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Peer ID
                      _buildInfoRow(
                        icon: Icons.fingerprint,
                        label: 'Peer ID',
                        value: info.peerId,
                        isLast: false,
                      ),
                      const SizedBox(height: 12),
                      // 设备名称
                      _buildInfoRow(
                        icon: Icons.router,
                        label: '设备名称',
                        value: info.deviceName,
                        isLast: false,
                      ),
                      const SizedBox(height: 12),
                      // 端口信息（区分 IPv4 和 IPv6）
                      _buildPortsSection(info.addresses),
                      const SizedBox(height: 12),
                      // IP 地址列表（区分 IPv4 和 IPv6，支持换行）
                      _buildIPsSection(info.addresses),
                      const SizedBox(height: 12),
                      // 提示信息
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3D8A5A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: const Color(0xFF3D8A5A)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'mDNS 广播用于发现同一网络中的其他设备',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF3D8A5A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  /// 构建信息行
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF3D8A5A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF3D8A5A)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建端口信息区域（区分 IPv4 和 IPv6）
  Widget _buildPortsSection(List<String> addresses) {
    final (ipv4Ports, ipv6Ports) = _DeviceListViewHelper._extractPorts(addresses);

    // 如果都没有端口，显示未知
    if (ipv4Ports.isEmpty && ipv6Ports.isEmpty) {
      return _buildInfoRow(
        icon: Icons.settings_ethernet,
        label: '监听端口',
        value: '未知',
        isLast: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 端口标题行
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3D8A5A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.settings_ethernet, size: 16, color: Color(0xFF3D8A5A)),
            ),
            const SizedBox(width: 12),
            Text(
              '监听端口',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // IPv4 端口
        if (ipv4Ports.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Text(
                    'IPv4',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ipv4Ports.map((p) => p.toString()).join(', '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (ipv6Ports.isNotEmpty) const SizedBox(height: 4),
        ],
        // IPv6 端口
        if (ipv6Ports.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'IPv6',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ipv6Ports.map((p) => p.toString()).join(', '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 构建 IP 地址信息区域（区分 IPv4 和 IPv6，支持换行）
  Widget _buildIPsSection(List<String> addresses) {
    final (ipv4Addresses, ipv6Addresses) = _DeviceListViewHelper._extractIPs(addresses);

    // 如果都没有 IP 地址，显示未知
    if (ipv4Addresses.isEmpty && ipv6Addresses.isEmpty) {
      return _buildInfoRow(
        icon: Icons.router,
        label: 'IP 地址',
        value: '未知',
        isLast: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // IP 地址标题行
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3D8A5A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.router, size: 16, color: Color(0xFF3D8A5A)),
            ),
            const SizedBox(width: 12),
            Text(
              'IP 地址',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // IPv4 地址
        if (ipv4Addresses.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ipv4Addresses.map((ip) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Text(
                        'IPv4',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ip,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF333333),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          if (ipv6Addresses.isNotEmpty) const SizedBox(height: 4),
        ],
        // IPv6 地址（支持换行）
        if (ipv6Addresses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ipv6Addresses.map((ip) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.purple.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'IPv6',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ip,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF333333),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  /// 构建 Positioned 的 Info 按钮（z-index 最高）
  Widget _buildPositionedInfoButton(BuildContext context) {
    return Obx(() {
      final position = controller.infoButtonPosition.value;
      if (position == null) {
        return const Positioned(child: SizedBox.shrink());
      }

      return Positioned(
        left: position.dx,
        top: position.dy,
        child: InkWell(
          onTap: controller.toggleBroadcastInfoPopup,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 28,
            height: 28,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.info_outline,
              size: 16,
              color: Colors.grey,
            ),
          ),
        ),
      );
    });
  }
}

/// 辅助类：静态工具方法
class _DeviceListViewHelper {
  /// 从地址列表中提取端口信息
  ///
  /// 地址格式示例：
  /// - IPv4: /ip4/192.168.1.100/tcp/12345
  /// - IPv6: /ip6/::1/tcp/23456
  ///
  /// 返回: (IPv4 端口列表, IPv6 端口列表)
  static (List<int>, List<int>) _extractPorts(List<String> addresses) {
    final ipv4Ports = <int>[];
    final ipv6Ports = <int>[];

    for (final addr in addresses) {
      // 解析 multiaddr 格式: /ip4/xxx/tcp/port 或 /ip6/xxx/tcp/port
      final parts = addr.split('/');
      if (parts.length >= 5) {
        final protocol = parts[1]; // ip4 或 ip6
        final transport = parts[3]; // tcp 或 udp
        final portStr = parts[4]; // 端口号

        if (transport == 'tcp') {
          final port = int.tryParse(portStr);
          if (port != null && port > 0) {
            if (protocol == 'ip4') {
              if (!ipv4Ports.contains(port)) {
                ipv4Ports.add(port);
              }
            } else if (protocol == 'ip6') {
              if (!ipv6Ports.contains(port)) {
                ipv6Ports.add(port);
              }
            }
          }
        }
      }
    }

    // 排序以便显示
    ipv4Ports.sort();
    ipv6Ports.sort();

    return (ipv4Ports, ipv6Ports);
  }

  /// 从地址列表中提取 IP 地址
  ///
  /// 地址格式示例：
  /// - IPv4: /ip4/192.168.1.100/tcp/12345
  /// - IPv6: /ip6/::1/tcp/23456 或 /ip6/fe80::1/tcp/23456
  ///
  /// 返回: (IPv4 地址列表, IPv6 地址列表)
  static (List<String>, List<String>) _extractIPs(List<String> addresses) {
    final ipv4Addresses = <String>[];
    final ipv6Addresses = <String>[];

    for (final addr in addresses) {
      // 解析 multiaddr 格式: /ip4/xxx/tcp/port 或 /ip6/xxx/tcp/port
      final parts = addr.split('/');
      if (parts.length >= 2) {
        final protocol = parts[1]; // ip4 或 ip6

        if (protocol == 'ip4' && parts.length > 2) {
          final ip = parts[2];
          if (ip.isNotEmpty && !ipv4Addresses.contains(ip)) {
            ipv4Addresses.add(ip);
          }
        } else if (protocol == 'ip6' && parts.length > 2) {
          final ip = parts[2];
          if (ip.isNotEmpty && !ipv6Addresses.contains(ip)) {
            ipv6Addresses.add(ip);
          }
        }
      }
    }

    // 排序以便显示
    ipv4Addresses.sort();
    ipv6Addresses.sort();

    return (ipv4Addresses, ipv6Addresses);
  }
}
