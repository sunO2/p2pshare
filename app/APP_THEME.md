# LocalP2P UI 设计规范

> 版本: 1.0.0
> 更新时间: 2025-02-03

本文档定义了 LocalP2P 应用的统一 UI 设计规范，所有开发人员必须严格遵循。

---

## 📐 目录

- [颜色规范](#颜色规范)
- [字体规范](#字体规范)
- [间距规范](#间距规范)
- [圆角规范](#圆角规范)
- [组件规范](#组件规范)
- [布局规范](#布局规范)
- [动画规范](#动画规范)
- [代码示例](#代码示例)

---

## 🎨 颜色规范

### 主色调

| 颜色名称 | 色值 | 用途 | 代码引用 |
|---------|------|------|---------|
| Primary Green | `#3D8A5A` | 主品牌色、主要按钮、选中状态 | `AppTheme.primaryGreen` |
| Light Green | `#C8F0D8` | 在线状态背景 | - |
| Dark Green | `#2D5A3A` | 深色模式主色 | - |

### 中性色

| 颜色名称 | 色值 | 用途 | 代码引用 |
|---------|------|------|---------|
| Background Light | `#F8F8F6` | 浅色模式背景 | `AppTheme.backgroundLight` |
| Background Dark | `#1A1A1A` | 深色模式背景 | `AppTheme.backgroundDark` |
| Text Primary | `#1A1A1A` | 主要文字 | `AppTheme.textPrimary` |
| Text Secondary | `#6D6C6A` | 次要文字 | `AppTheme.textSecondary` |
| Text Tertiary | `#9C9B99` | 辅助文字 | `AppTheme.textTertiary` |
| Divider | `#E5E4E1` | 分隔线 | `AppTheme.dividerColor` |
| Border | `#CCCCCC` | 边框 | `AppTheme.dividerBorderColor` |

### 功能色

| 颜色名称 | 色值 | 用途 |
|---------|------|------|
| Success | `#3D8A5A` | 成功状态 |
| Error | `#D32F2F` | 错误状态 |
| Error BG | `#FFEBEE` | 错误背景 |
| Warning | `#F57C00` | 警告状态 |
| Info | `#2196F3` | 信息提示 |

### 使用规则

```dart
// ✅ 正确 - 使用主题定义的颜色
Container(color: AppTheme.primaryGreen)

// ❌ 错误 - 硬编码颜色值
Container(color: Color(0xFF3D8A5A))
```

---

## 🔤 字体规范

### 字体大小

| 样式名称 | 大小 | 粗细 | 行高 | 用途 | 代码引用 |
|---------|------|------|------|------|---------|
| **AppBar Title** | 26px | Regular | 1.2 | 导航栏标题 | `AppTheme.appBarTitle` |
| **Display Large** | 18px | w600 | 1.3 | 页面大标题 | `context.textTheme.displayLarge` |
| **Display Medium** | 16px | w600 | 1.3 | 中等标题 | `context.textTheme.displayMedium` |
| **Display Small** | 16px | w600 | 1.3 | 区块标题 | `context.textTheme.displaySmall` |
| **Title Large** | 15px | Regular | 1.4 | 列表项标题 | `context.textTheme.titleLarge` |
| **Title Medium** | 14px | Regular | 1.4 | 次级标题 | `context.textTheme.titleMedium` |
| **Title Small** | 14px | Regular | 1.4 | 小标题 | `context.textTheme.titleSmall` |
| **Body Large** | 15px | Regular | 1.5 | 正文内容 | `context.textTheme.bodyLarge` |
| **Body Medium** | 14px | Regular | 1.5 | 次要正文 | `context.textTheme.bodyMedium` |
| **Body Small** | 12px | Regular | 1.4 | 辅助文字 | `context.textTheme.bodySmall` |
| **Label Large** | 15px | w500 | - | 按钮文字 | `context.textTheme.labelLarge` |
| **Label Medium** | 14px | w500 | - | 标签文字 | `context.textTheme.labelMedium` |
| **Label Small** | 12px | w500 | - | 小标签 | `context.textTheme.labelSmall` |

### 字体使用场景

#### 导航栏标题 (AppBar Title - 26px)
```dart
// UnifiedAppBar 导航栏标题（特殊大标题）
Text('聊天', style: AppTheme.appBarTitle)
```

#### 页面标题 (Display Large - 18px)
```dart
// AppBar 标题、页面主标题
Text('设备列表', style: context.textTheme.displayLarge)
```

#### 区块标题 (Display Small - 16px)
```dart
// 列表上方的分类标题
Text('设备设置', style: context.textTheme.displaySmall)
```

#### 列表项 (Title Large - 15px)
```dart
// 列表中的主要文字
Text('iPhone 15 Pro', style: context.textTheme.titleLarge)
```

#### 正文内容 (Body Large/Medium - 15px/14px)
```dart
// 消息内容、描述文字
Text('这是一条消息', style: context.textTheme.bodyLarge)
Text('次要信息', style: context.textTheme.bodyMedium)
```

#### 辅助文字 (Body Small - 12px)
```dart
// 时间戳、提示文字
Text('2分钟前', style: context.textTheme.bodySmall)
```

### 行高规范

| 字体大小 | 行高 | 行高值 |
|---------|------|--------|
| 26px | 1.2 | 31.2px |
| 18px | 1.3 | 23.4px |
| 16px | 1.3 | 20.8px |
| 15px | 1.4/1.5 | 21px/22.5px |
| 14px | 1.4/1.5 | 19.6px/21px |
| 12px | 1.4 | 16.8px |

### 使用规则

```dart
// ✅ 正确 - 使用主题文字样式
Text('标题', style: context.textTheme.displayLarge)

// ❌ 错误 - 硬编码字体大小
Text('标题', style: TextStyle(fontSize: 18))

// ❌ 错误 - 使用 Material 3 默认样式（字体更大）
Text('标题', style: Theme.of(context).textTheme.headlineMedium)
```

---

## 📏 间距规范

### 基础间距单位

使用 4px 基础单位，所有间距必须是 4 的倍数：

| 单位 | 值 | 用途 |
|------|-----|------|
| xs | 4px | 极小间距 |
| sm | 8px | 小间距 |
| md | 12px | 中等间距 |
| lg | 16px | 标准间距 |
| xl | 20px | 大间距 |
| xxl | 24px | 超大间距 |
| 3xl | 32px | 区块间距 |

### 常用间距场景

| 场景 | 间距值 |
|------|--------|
| 列表项内边距 | 18px (水平) |
| 列表项高度 | 56px |
| 列表项间距 | 8px (separator) |
| 卡片内边距 | 18px / 24px |
| 卡片圆角 | 16px |
| 页面边距 | 24px |
| 区块间距 | 20px |
| 图标与文字 | 12px |
| 按钮内边距 | 12px (垂直) |

### EdgeInsets 常量

```dart
// 定义在 AppTheme 中
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets page = EdgeInsets.all(24);
  static const EdgeInsets card = EdgeInsets.all(18);
  static const EdgeInsets listTile = EdgeInsets.symmetric(horizontal: 18);
  static const EdgeInsets button = EdgeInsets.symmetric(horizontal: 24, vertical: 12);
}
```

---

## ⭕ 圆角规范

| 组件 | 圆角值 | 用途 |
|------|--------|------|
| 按钮圆形 | 100% | 圆形按钮、状态标签 |
| 卡片 | 16px | 卡片容器 |
| 对话框 | 16px | Dialog、BottomSheet |
| 输入框 | 8px | TextField |
| 按钮 | 8px | 矩形按钮 |
| 头像方形 | 12px | 方形头像 |
| 小组件 | 8px | Badge、Chip |

---

## 🧩 组件规范

### 按钮

#### 主要按钮 (Filled Button)
```dart
Container(
  width: 52,
  height: 52,
  decoration: const BoxDecoration(
    color: AppTheme.primaryGreen,
    shape: BoxShape.circle,
  ),
  child: const Icon(Icons.send, size: 20, color: Colors.white),
)
```

#### 次要按钮 (Outlined Button)
```dart
Container(
  height: 40,
  padding: AppSpacing.button,
  decoration: BoxDecoration(
    border: Border.all(color: AppTheme.primaryGreen),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text('取消', style: context.textTheme.labelLarge),
)
```

#### 开关按钮 (Toggle)
```dart
Container(
  width: 48,
  height: 28,
  padding: const EdgeInsets.all(2),
  decoration: BoxDecoration(
    color: isEnabled ? AppTheme.primaryGreen : Color(0xFFEDECEA),
    borderRadius: BorderRadius.circular(100),
  ),
  child: AnimatedAlign(
    duration: const Duration(milliseconds: 200),
    alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    ),
  ),
)
```

### 卡片

```dart
Container(
  padding: AppSpacing.card,
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('标题', style: context.textTheme.displaySmall),
      SizedBox(height: AppSpacing.lg),
      Text('内容', style: context.textTheme.bodyMedium),
    ],
  ),
)
```

### 列表项

```dart
Container(
  height: 56,
  padding: AppSpacing.listTile,
  child: Row(
    children: [
      Text('标题', style: context.textTheme.titleLarge),
      Spacer(),
      Text('值', style: context.textTheme.bodyLarge),
    ],
  ),
)
```

### 输入框

```dart
TextField(
  decoration: InputDecoration(
    hintText: '请输入...',
    hintStyle: context.textTheme.bodyLarge?.copyWith(
      color: AppTheme.textTertiary,
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppTheme.primaryGreen),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppTheme.primaryGreen),
      borderRadius: BorderRadius.circular(8),
    ),
  ),
)
```

### 状态指示器

```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: isOnline ? Color(0xFFC8F0D8) : Color(0xFFFFEBEE),
    borderRadius: BorderRadius.circular(100),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: isOnline ? AppTheme.primaryGreen : Color(0xFFD32F2F),
          shape: BoxShape.circle,
        ),
      ),
      SizedBox(width: 6),
      Text(
        isOnline ? '在线' : '离线',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: isOnline ? AppTheme.primaryGreen : Color(0xFFD32F2F),
        ),
      ),
    ],
  ),
)
```

### 对话框

```dart
Dialog(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),
  child: Container(
    padding: EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('标题', style: context.textTheme.displaySmall),
        SizedBox(height: 16),
        Text('内容', style: context.textTheme.bodyMedium),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _buildCancelButton()),
            SizedBox(width: 12),
            Expanded(child: _buildConfirmButton()),
          ],
        ),
      ],
    ),
  ),
)
```

### 头像

```dart
// 圆形头像
Container(
  width: 40,
  height: 40,
  decoration: BoxDecoration(
    color: AppTheme.primaryGreen,
    shape: BoxShape.circle,
  ),
  child: Center(
    child: Text(
      'A',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  ),
)

// 方形头像
Container(
  width: 40,
  height: 40,
  decoration: BoxDecoration(
    color: AppTheme.primaryGreen,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Center(
    child: Text(
      'A',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  ),
)
```

### 聊天气泡

#### 发送气泡
```dart
Container(
  constraints: BoxConstraints(maxWidth: 240),
  decoration: BoxDecoration(
    color: Color(0xFF95EC69),
    borderRadius: BorderRadius.all(Radius.circular(8)),
  ),
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  margin: EdgeInsets.only(right: 8),
  child: Text(
    message,
    style: TextStyle(fontSize: 16, color: Colors.black),
  ),
)
```

#### 接收气泡
```dart
Container(
  constraints: BoxConstraints(maxWidth: 240),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  ),
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  child: Text(
    message,
    style: TextStyle(fontSize: 16, color: Colors.black),
  ),
)
```

---

## 📐 布局规范

### 页面布局

```dart
Scaffold(
  body: SafeArea(
    child: Column(
      children: [
        // 1. AppBar (UnifiedAppBar)
        UnifiedAppBar(title: '页面标题'),

        // 2. 内容区
        Expanded(
          child: Container(
            color: AppTheme.backgroundLight,
            padding: AppSpacing.page,
            child: ListView(...),
          ),
        ),
      ],
    ),
  ),
)
```

### 列表布局

```dart
ListView.separated(
  padding: EdgeInsets.all(24),
  separatorBuilder: (context, index) => SizedBox(height: 8),
  itemCount: items.length,
  itemBuilder: (context, index) {
    return _buildCard(items[index]);
  },
)
```

### 卡片列表

```dart
ListView(
  padding: EdgeInsets.all(24),
  children: [
    // 区块标题
    Text('设备设置', style: context.textTheme.displaySmall),
    SizedBox(height: 12),

    // 卡片
    Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildListTile('项目1', '值1'),
          Divider(height: 1, indent: 18),
          _buildListTile('项目2', '值2'),
        ],
      ),
    ),
  ],
)
```

### 分隔线

```dart
// 列表分隔线
Container(
  height: 1,
  margin: EdgeInsets.only(left: 18),
  color: AppTheme.dividerColor,
)

// 区块分隔线
Container(
  height: 1,
  color: AppTheme.dividerBorderColor,
)
```

---

## 🎭 动画规范

### 动画时长

| 类型 | 时长 | 用途 |
|------|------|------|
| Fast | 150ms | 简单状态变化 |
| Normal | 200ms | 标准动画（开关、展开） |
| Slow | 300ms | 复杂动画（页面切换） |
| Slower | 400ms | 特殊效果 |

### 动画曲线

```dart
// 标准曲线
Curves.easeOut
Curves.easeInOut
Curves.easeOutBack  // 弹性效果
```

### 示例

```dart
// 开关动画
AnimatedAlign(
  duration: Duration(milliseconds: 200),
  curve: Curves.easeOut,
  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
  child: ...,
)

// 弹窗动画
AnimationController(
  duration: Duration(milliseconds: 300),
  vsync: this,
);
scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
  CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutBack,
  ),
);
```

---

## 📝 代码示例

### 完整页面示例

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/example_controller.dart';

class ExampleView extends GetView<ExampleController> {
  const ExampleView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            UnifiedAppBar(title: '示例页面'),

            // 内容
            Expanded(
              child: Container(
                color: AppTheme.backgroundLight,
                padding: EdgeInsets.all(24),
                child: ListView(
                  children: [
                    // 区块标题
                    Text('设置', style: context.textTheme.displaySmall),
                    SizedBox(height: 12),

                    // 卡片
                    _buildCard(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildListTile(context, '设备名称', 'iPhone'),
          _buildDivider(),
          _buildListTile(context, '状态', '在线'),
        ],
      ),
    );
  }

  Widget _buildListTile(BuildContext context, String title, String value) {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Text(title, style: context.textTheme.titleLarge),
          Spacer(),
          Text(value, style: context.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: 18),
      color: AppTheme.dividerColor,
    );
  }
}
```

---

## ✅ 检查清单

在提交代码前，请确认：

- [ ] 所有颜色使用 `AppTheme.*` 常量
- [ ] 所有文字使用 `context.textTheme.*`
- [ ] 所有间距是 4 的倍数
- [ ] 所有圆角使用规范值（8/12/16/100）
- [ ] 按钮高度符合规范（40/52）
- [ ] 列表项高度为 56px
- [ ] 卡片圆角为 16px
- [ ] 动画时长使用规范值（150/200/300/400ms）
- [ ] 没有硬编码的颜色值（如 `Color(0xFF3D8A5A)`）
- [ ] 没有硬编码的字体大小（如 `fontSize: 18`）
- [ ] 没有使用 Material 3 样式

---

## 🔧 维护

### 添加新的文字样式

1. 在 `AppTheme` 中添加样式常量
2. 在 `GetTextTheme` 中添加 getter
3. 在本文档中更新字体规范表
4. 提供使用示例

### 添加新的颜色

1. 在 `AppTheme` 中添加颜色常量
2. 在本文档中更新颜色规范表
3. 说明使用场景

### 更新规范

1. 修改本文档
2. 更新版本号
3. 通知团队成员
4. 更新相关代码

---

**最后更新**: 2025-02-03
**维护者**: LocalP2P 开发团队
