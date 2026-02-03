import 'package:flutter/material.dart';

/// 应用主题配置
///
/// 统一管理应用的文字样式、颜色、间距等
/// 详细规范见 APP_THEME.md
class AppTheme {
  // ========== 颜色常量 ==========

  /// 主题绿色
  static const Color primaryGreen = Color(0xFF3D8A5A);

  /// 背景色
  static const Color backgroundLight = Color(0xFFF8F8F6);
  static const Color backgroundDark = Color(0xFF1A1A1A);

  /// 卡片背景色
  static const Color cardBackgroundLight = Color(0xFFFFFFFF);
  static const Color cardBackgroundDark = Color(0xFF2D2D2D);

  /// 分隔线边框颜色
  static const Color dividerBorderColorDark = Color(0xFF404040);

  /// 文字颜色
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6D6C6A);
  static const Color textTertiary = Color(0xFF9C9B99);

  /// 分隔线颜色
  static const Color dividerColor = Color(0xFFE5E4E1);
  static const Color dividerBorderColor = Color(0xFFCCCCCC);

  // ========== 间距常量 ==========

  /// 基础间距单位（4px 倍数）
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 20;
  static const double spacingXxl = 24;
  static const double spacingXxxl = 32;

  /// 页面边距
  static const EdgeInsets paddingPage = EdgeInsets.all(spacingXxl);

  /// 卡片内边距
  static const EdgeInsets paddingCard = EdgeInsets.all(18);

  /// 列表项内边距
  static const EdgeInsets paddingListTile = EdgeInsets.symmetric(horizontal: 18);

  /// 按钮内边距
  static const EdgeInsets paddingButton = EdgeInsets.symmetric(horizontal: 24, vertical: 12);

  // ========== 圆角常量 ==========

  /// 卡片圆角
  static const double radiusCard = 16;

  /// 按钮圆角
  static const double radiusButton = 8;

  /// 圆形（用于状态标签等）
  static const double radiusCircle = 100;

  /// 头像方形圆角
  static const double radiusAvatar = 12;

  // ========== 尺寸常量 ==========

  /// 列表项高度
  static const double heightListTile = 56;

  /// 按钮高度
  static const double heightButtonSmall = 40;
  static const double heightButtonLarge = 52;

  /// 图标大小
  static const double iconSizeSmall = 16;
  static const double iconSizeMedium = 20;
  static const double iconSizeLarge = 24;
  static const double iconSizeXLarge = 36;

  /// 头像大小
  static const double avatarSizeSmall = 32;
  static const double avatarSizeMedium = 40;
  static const double avatarSizeLarge = 56;

  // ========== 文字样式 ==========

  /// 导航栏标题（特殊大标题）
  static const TextStyle appBarTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.normal,
    color: textPrimary,
    height: 1.2,
  );

  /// 大标题（页面标题）
  static const TextStyle displayLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.3,
  );

  /// 中标题（区块标题）
  static const TextStyle displaySmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.3,
  );

  /// 列表项标题
  static const TextStyle titleLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    color: textPrimary,
    height: 1.4,
  );

  /// 正文文字
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    color: textSecondary,
    height: 1.5,
  );

  /// 次要正文
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textSecondary,
    height: 1.5,
  );

  /// 小字提示
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textTertiary,
    height: 1.4,
  );

  // ========== Material 主题 ==========

  /// 浅色主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: false, // 使用 Material 2 以保持原有字体大小
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.light,
        primary: primaryGreen,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: backgroundLight,
        selectedItemColor: primaryGreen,
        unselectedItemColor: Color(0xFF999999),
        type: BottomNavigationBarType.fixed,
        elevation: 1,
        selectedLabelStyle: TextStyle(fontSize: 10),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),
      textTheme: _buildTextTheme(Brightness.light),
      // 扩展主题数据
      extensions: [
        _CustomTheme(
          scaffoldBackground: backgroundLight,
          cardBackground: cardBackgroundLight,
          dividerColor: dividerBorderColor,
          iconColor: textSecondary,
          iconColorLight: textSecondary,
          searchBackground: Colors.white,
          statusGreen: Color(0xFF3D8A5A),
          statusOrange: Color(0xFFF57C00),
          statusRed: Color(0xFFD32F2F),
          statusGrey: Color(0xFF9E9E9E),
          statusGreenBg: Color(0xFFC8F0D8),
          statusGreenBgLight: Color(0xFFE8F5E9),
        ),
      ],
    );
  }

  /// 深色主题
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: false,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.dark,
        primary: primaryGreen,
      ),
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2D5A3A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF2D2D2D),
        selectedItemColor: Color(0xFF6BC48A),
        unselectedItemColor: Color(0xFF888888),
        type: BottomNavigationBarType.fixed,
        elevation: 1,
        selectedLabelStyle: TextStyle(fontSize: 10),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      extensions: [
        _CustomTheme(
          scaffoldBackground: backgroundDark,
          cardBackground: cardBackgroundDark,
          dividerColor: dividerBorderColorDark,
          iconColor: Colors.white70,
          iconColorLight: Colors.white54,
          searchBackground: const Color(0xFF2D2D2D),
          statusGreen: Color(0xFF6BC48A),
          statusOrange: Color(0xFFB97D00),
          statusRed: Color(0xFFEF5350),
          statusGrey: Color(0xFF757575),
          statusGreenBg: Color(0xFF2D5A3A),
          statusGreenBgLight: Color(0xFF1A3A2A),
        ),
      ],
    );
  }

  /// 构建文字主题
  static TextTheme _buildTextTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return TextTheme(
      displayLarge: displayLarge.copyWith(
        color: isDark ? Colors.white : textPrimary,
      ),
      displayMedium: displayLarge.copyWith(
        fontSize: 16,
        color: isDark ? Colors.white70 : textPrimary,
      ),
      displaySmall: displaySmall.copyWith(
        color: isDark ? Colors.white70 : textPrimary,
      ),
      headlineLarge: displayLarge.copyWith(
        fontSize: 20,
        color: isDark ? Colors.white : textPrimary,
      ),
      headlineMedium: displayLarge.copyWith(
        color: isDark ? Colors.white70 : textPrimary,
      ),
      headlineSmall: displaySmall.copyWith(
        color: isDark ? Colors.white70 : textPrimary,
      ),
      titleLarge: titleLarge.copyWith(
        color: isDark ? Colors.white : textPrimary,
      ),
      titleMedium: titleLarge.copyWith(
        fontSize: 14,
        color: isDark ? Colors.white70 : textPrimary,
      ),
      titleSmall: bodyMedium.copyWith(
        color: isDark ? Colors.white70 : textPrimary,
      ),
      bodyLarge: bodyLarge.copyWith(
        color: isDark ? Colors.white70 : textSecondary,
      ),
      bodyMedium: bodyMedium.copyWith(
        color: isDark ? Colors.white60 : textSecondary,
      ),
      bodySmall: bodySmall.copyWith(
        color: isDark ? Colors.white54 : textTertiary,
      ),
      labelLarge: bodyLarge.copyWith(
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white : textPrimary,
      ),
      labelMedium: bodyMedium.copyWith(
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white70 : textSecondary,
      ),
      labelSmall: bodySmall.copyWith(
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white60 : textTertiary,
      ),
    );
  }

  // ========== 扩展方法 ==========

  /// GetX 上下文扩展
  /// 使用方式: context.textTheme.displayLarge
  static GetTextTheme getTextTheme(BuildContext context) {
    return GetTextTheme(Theme.of(context).textTheme);
  }
}

/// GetX 文字主题扩展
class GetTextTheme {
  final TextTheme _theme;

  GetTextTheme(this._theme);

  TextStyle get appBarTitle => AppTheme.appBarTitle;
  TextStyle get displayLarge => _theme.displayLarge ?? AppTheme.displayLarge;
  TextStyle get displaySmall => _theme.displaySmall ?? AppTheme.displaySmall;
  TextStyle get titleLarge => _theme.titleLarge ?? AppTheme.titleLarge;
  TextStyle get titleMedium => _theme.titleMedium ?? AppTheme.titleLarge.copyWith(fontSize: 14);
  TextStyle get titleSmall => _theme.titleSmall ?? AppTheme.bodyMedium;
  TextStyle get bodyLarge => _theme.bodyLarge ?? AppTheme.bodyLarge;
  TextStyle get bodyMedium => _theme.bodyMedium ?? AppTheme.bodyMedium;
  TextStyle get bodySmall => _theme.bodySmall ?? AppTheme.bodySmall;
  TextStyle get labelLarge => _theme.labelLarge ?? AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w500);
  TextStyle get labelMedium => _theme.labelMedium ?? AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500);
  TextStyle get labelSmall => _theme.labelSmall ?? AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w500);
}

/// 上下文扩展
extension AppThemeContextExtension on BuildContext {
  /// 获取应用文字主题（避免与 GetX 的 textTheme 冲突）
  GetTextTheme get appTextTheme => GetTextTheme(Theme.of(this).textTheme);

  /// 获取自定义主题扩展
  _CustomTheme get customTheme => Theme.of(this).extension<_CustomTheme>()!;
}

/// 自定义主题扩展
///
/// 用于定义两套主题（浅色/深色）的自定义颜色
@immutable
class _CustomTheme extends ThemeExtension<_CustomTheme> {
  final Color scaffoldBackground;
  final Color cardBackground;
  final Color dividerColor;
  final Color iconColor;
  final Color iconColorLight;
  final Color searchBackground;
  final Color statusGreen;
  final Color statusOrange;
  final Color statusRed;
  final Color statusGrey;
  final Color statusGreenBg;
  final Color statusGreenBgLight;

  const _CustomTheme({
    required this.scaffoldBackground,
    required this.cardBackground,
    required this.dividerColor,
    required this.iconColor,
    required this.iconColorLight,
    required this.searchBackground,
    required this.statusGreen,
    required this.statusOrange,
    required this.statusRed,
    required this.statusGrey,
    required this.statusGreenBg,
    required this.statusGreenBgLight,
  });

  @override
  _CustomTheme copyWith({
    Color? scaffoldBackground,
    Color? cardBackground,
    Color? dividerColor,
    Color? iconColor,
    Color? iconColorLight,
    Color? searchBackground,
    Color? statusGreen,
    Color? statusOrange,
    Color? statusRed,
    Color? statusGrey,
    Color? statusGreenBg,
    Color? statusGreenBgLight,
  }) {
    return _CustomTheme(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      dividerColor: dividerColor ?? this.dividerColor,
      iconColor: iconColor ?? this.iconColor,
      iconColorLight: iconColorLight ?? this.iconColorLight,
      searchBackground: searchBackground ?? this.searchBackground,
      statusGreen: statusGreen ?? this.statusGreen,
      statusOrange: statusOrange ?? this.statusOrange,
      statusRed: statusRed ?? this.statusRed,
      statusGrey: statusGrey ?? this.statusGrey,
      statusGreenBg: statusGreenBg ?? this.statusGreenBg,
      statusGreenBgLight: statusGreenBgLight ?? this.statusGreenBgLight,
    );
  }

  @override
  _CustomTheme lerp(covariant ThemeExtension<_CustomTheme>? other, double t) {
    if (other is! _CustomTheme) {
      return this;
    }
    return _CustomTheme(
      scaffoldBackground: Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
      iconColor: Color.lerp(iconColor, other.iconColor, t)!,
      iconColorLight: Color.lerp(iconColorLight, other.iconColorLight, t)!,
      searchBackground: Color.lerp(searchBackground, other.searchBackground, t)!,
      statusGreen: Color.lerp(statusGreen, other.statusGreen, t)!,
      statusOrange: Color.lerp(statusOrange, other.statusOrange, t)!,
      statusRed: Color.lerp(statusRed, other.statusRed, t)!,
      statusGrey: Color.lerp(statusGrey, other.statusGrey, t)!,
      statusGreenBg: Color.lerp(statusGreenBg, other.statusGreenBg, t)!,
      statusGreenBgLight: Color.lerp(statusGreenBgLight, other.statusGreenBgLight, t)!,
    );
  }
}

