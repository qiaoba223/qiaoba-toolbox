import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局主题控制器（支持白天/夜间/跟随系统，强刷系统状态栏与导航栏）
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  static const String _prefKey = 'app_theme_mode';
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  bool isDark([BuildContext? context]) {
    if (_mode == ThemeMode.dark) return true;
    if (_mode == ThemeMode.light) return false;
    if (context != null && context.mounted) {
      try {
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      } catch (_) {}
    }
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  /// 立即向底层系统 Window 应用状态栏与导航栏图标样式，彻底解决切换模式时图标与时间看不清的问题
  static void applySystemOverlay(bool dark) {
    final style = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // Android 状态栏图标：深色模式用白色(light)，浅色模式用黑色(dark)
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      // iOS 状态栏文字图标：深色模式用白色(dark)，浅色模式用黑色(light)
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: dark ? AppTheme.darkCard : Colors.white,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
    SystemChrome.setSystemUIOverlayStyle(style);
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'dark') {
        _mode = ThemeMode.dark;
      } else if (saved == 'light') {
        _mode = ThemeMode.light;
      } else {
        _mode = ThemeMode.system;
      }
      applySystemOverlay(_mode == ThemeMode.dark);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode newMode) async {
    _mode = newMode;
    applySystemOverlay(_mode == ThemeMode.dark);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newMode.name);
    } catch (_) {}
  }

  Future<void> toggle(BuildContext context) async {
    final dark = isDark(context);
    final targetMode = dark ? ThemeMode.light : ThemeMode.dark;
    // 立即同步更新底层系统状态栏，无须等待异步写入完成
    applySystemOverlay(!dark);
    await setMode(targetMode);
  }
}

/// 现代化 Material 3 主题设计规范（白天 + 夜间模式全面适配，彻底解决状态栏时间遮挡）
class AppTheme {
  // 品牌主色
  static const Color primary = Color(0xFFEC6C79); // 乔巴粉
  static const Color primaryDark = Color(0xFFC94A57);
  static const Color primaryLight = Color(0xFFFDEBEE);
  static const Color accent = Color(0xFF4A90D9);
  static const Color success = Color(0xFF34C77B);
  static const Color warning = Color(0xFFF5A623);
  static const Color danger = Color(0xFFE74C3C);

  // 业务模块标识色
  static const Color ctColor = Color(0xFF005BAC); // 电信蓝
  static const Color yspColor = Color(0xFFE43D2B); // 央视红
  static const Color ztoColor = Color(0xFF1A2A6C); // 中通深蓝

  // 兼容别名（向后兼容旧组件引用）
  static const Color bg = Color(0xFFF8FAFC);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE2E8F0);
  static const Color textMain = Color(0xFF0F172A);
  static const Color textSub = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);

  // 白天模式调色板
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Colors.white;
  static const Color lightTextMain = Color(0xFF0F172A);
  static const Color lightTextSub = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightInputFill = Color(0xFFF8FAFC);

  // 夜间模式调色板（高级深邃黑蓝，夜间舒适护眼）
  static const Color darkBg = Color(0xFF0B0F19);
  static const Color darkCard = Color(0xFF151D2F);
  static const Color darkTextMain = Color(0xFFF8FAFC);
  static const Color darkTextSub = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);
  static const Color darkBorder = Color(0xFF26334D);
  static const Color darkInputFill = Color(0xFF121929);

  /// 白天模式（强制浅色状态栏：黑色文字与图标，时间清晰可见）
  static ThemeData light() {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // Android 黑色图标与时间
      statusBarBrightness: Brightness.light,    // iOS 黑色图标与时间
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      surface: lightCard,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightBg,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: lightTextMain),
        bodyMedium: TextStyle(color: lightTextMain),
        bodySmall: TextStyle(color: lightTextSub),
        titleMedium: TextStyle(color: lightTextMain, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: lightTextMain, fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: lightTextMain,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: TextStyle(
          color: lightTextMain,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: lightTextMuted, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1),
    );
  }

  /// 夜间模式（强制深色状态栏：白色文字与图标，时间清晰可见）
  static ThemeData dark() {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Android 白色图标与时间
      statusBarBrightness: Brightness.dark,     // iOS 白色图标与时间
      systemNavigationBarColor: darkCard,
      systemNavigationBarIconBrightness: Brightness.light,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      surface: darkCard,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: darkTextMain),
        bodyMedium: TextStyle(color: darkTextMain),
        bodySmall: TextStyle(color: darkTextSub),
        titleMedium: TextStyle(color: darkTextMain, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: darkTextMain, fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: darkTextMain,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: TextStyle(
          color: darkTextMain,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: darkTextMuted, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1),
    );
  }
}
