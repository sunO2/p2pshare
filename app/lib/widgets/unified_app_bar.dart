import 'package:flutter/material.dart';

/// 统一风格的导航头组件
/// 高度: 70px + topPadding (状态栏)
/// 背景色: #F8F8F6
/// 支持返回按钮、标题和可选的状态指示器
class UnifiedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Widget? statusIndicator;
  final List<Widget>? actions;
  final Color backgroundColor;

  const UnifiedAppBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.onBackPressed,
    this.statusIndicator,
    this.actions,
    this.backgroundColor = const Color(0xFFF8F8F6),
  });

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  Widget build(BuildContext context) {
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
      decoration: BoxDecoration(color: backgroundColor),
      child: Row(
        children: [
          // Back button
          if (showBackButton) ...[
            GestureDetector(
              onTap: onBackPressed ?? () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8E8E6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Color(0xFF6D6C6A),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Title with optional status
          Expanded(
            child: Column(
              mainAxisAlignment: statusIndicator != null
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 26,
                    fontWeight: FontWeight.normal,
                    color: Color(0xFF1A1918),
                  ),
                ),
                if (statusIndicator != null) ...[
                  const SizedBox(height: 4),
                  statusIndicator!,
                ],
              ],
            ),
          ),

          // Actions
          ...?actions,
        ],
      ),
    );
  }
}

/// 在线状态指示器组件
class OnlineStatusIndicator extends StatelessWidget {
  final String text;

  const OnlineStatusIndicator({super.key, this.text = '在线'});

  @override
  Widget build(BuildContext context) {
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
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.normal,
              color: Color(0xFF3D8A5A),
            ),
          ),
        ],
      ),
    );
  }
}
