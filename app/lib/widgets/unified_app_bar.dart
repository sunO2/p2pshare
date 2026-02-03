import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// 统一风格的导航头组件
///
/// ### 布局结构
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │ [状态栏 - 系统自动处理]                                 │
/// ├─────────────────────────────────────────────────────────┤
/// │  ◀ 返回按钮 │  主标题 (26px)          │ [Actions]     │
/// │             │  子标题/状态指示器      │               │
/// ├─────────────────────────────────────────────────────────┤
/// │  内容区域                                               │
/// └─────────────────────────────────────────────────────────┘
/// ```
///
/// ### 返回按钮控制
/// - `showBackButton` 为 `null`（默认）：自动判断能否返回
/// - `showBackButton` 为 `true`：强制显示返回按钮
/// - `showBackButton` 为 `false`：强制隐藏返回按钮
///
/// ### 子标题支持
/// - `subtitle` 传入文字：自动使用在线状态指示器样式
/// - `subtitleWidget` 传入自定义组件：完全自定义
///
/// ### 使用示例
/// ```dart
/// // 首页（自动隐藏返回按钮）
/// UnifiedAppBar(title: '我的设备')
///
/// // 子页面（自动显示返回按钮）
/// UnifiedAppBar(title: '聊天')
///
/// // 强制显示返回按钮
/// UnifiedAppBar(title: '设置', showBackButton: true)
///
/// // 强制隐藏返回按钮
/// UnifiedAppBar(title: '首页', showBackButton: false)
///
/// // 带子标题
/// UnifiedAppBar(
///   title: '张三',
///   subtitle: '在线',  // 或 subtitleWidget
/// )
/// ```
class UnifiedAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 主标题（必填）
  final String title;

  /// 返回按钮控制
  /// - `null`：自动判断能否返回（默认）
  /// - `true`：强制显示
  /// - `false`：强制隐藏
  final bool? showBackButton;

  /// 返回按钮点击事件（可选）
  final VoidCallback? onBackPressed;

  /// 子标题文字（自动使用状态指示器样式）
  final String? subtitle;

  /// 自定义子标题组件（优先级高于 subtitle）
  final Widget? subtitleWidget;

  /// 右侧操作按钮
  final List<Widget>? actions;

  /// 导航栏背景色
  final Color backgroundColor;

  const UnifiedAppBar({
    super.key,
    required this.title,
    this.showBackButton,
    this.onBackPressed,
    this.subtitle,
    this.subtitleWidget,
    this.actions,
    this.backgroundColor = const Color(0xFFF8F8F6),
  });

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final totalHeight = 70.0 + topPadding;

    // 判断是否显示返回按钮
    final shouldShowBack = _shouldShowBackButton(context);

    // 获取子标题组件
    final childWidget = subtitleWidget ?? _buildSubtitleWidget();

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
          if (shouldShowBack) ...[
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

          // Title with optional subtitle
          Expanded(
            child: Column(
              mainAxisAlignment: childWidget != null
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.appBarTitle.copyWith(
                    color: const Color(0xFF1A1918),
                  ),
                ),
                if (childWidget != null) ...[
                  const SizedBox(height: 4),
                  childWidget!,
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

  /// 判断是否显示返回按钮
  bool _shouldShowBackButton(BuildContext context) {
    if (showBackButton != null) {
      // 强制控制
      return showBackButton!;
    }
    // 自动判断：能否返回到上一页
    return Navigator.canPop(context);
  }

  /// 构建子标题组件（从文字生成）
  Widget? _buildSubtitleWidget() {
    if (subtitle == null) return null;

    return OnlineStatusIndicator(text: subtitle!);
  }
}

/// 在线状态指示器组件（用于导航栏子标题）
class OnlineStatusIndicator extends StatelessWidget {
  final String text;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? dotColor;

  const OnlineStatusIndicator({
    super.key,
    this.text = '在线',
    this.backgroundColor,
    this.textColor,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? const Color(0xFFC8F0D8);
    final txtColor = textColor ?? const Color(0xFF3D8A5A);
    final dtColor = dotColor ?? const Color(0xFF3D8A5A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dtColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.normal,
              color: txtColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 离线状态指示器（用于导航栏子标题）
class OfflineStatusIndicator extends StatelessWidget {
  final String text;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? dotColor;

  const OfflineStatusIndicator({
    super.key,
    this.text = '离线',
    this.backgroundColor,
    this.textColor,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return OnlineStatusIndicator(
      text: text,
      backgroundColor: backgroundColor ?? const Color(0xFFFFEBEE),
      textColor: textColor ?? const Color(0xFFD32F2F),
      dotColor: dotColor ?? const Color(0xFFD32F2F),
    );
  }
}
