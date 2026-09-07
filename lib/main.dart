import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services/app_update_dialog.dart';
import 'core/services/app_update_service.dart';
import 'core/theme/animations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_widgets.dart';
import 'features/ctlogin/ct_login_page.dart';
import 'features/yspck/yspck_page.dart';
import 'features/zto/zto_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.init();
  runApp(const QiaobaToolboxApp());
}

class QiaobaToolboxApp extends StatelessWidget {
  const QiaobaToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final mode = ThemeController.instance.mode;
        return MaterialApp(
          key: ValueKey(mode), // 恢复切换白夜模式时全卡片 Q 弹波动的动感入场动效
          title: '小助手',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const RootPage(),
        );
      },
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage>
    with SingleTickerProviderStateMixin {
  static bool _hasAutoChecked = false;
  bool _checking = false;
  late final AnimationController _heroCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    // 启动时仅自动检测一次更新，切换明暗模式时绝不重复刷新检测更新
    if (!_hasAutoChecked) {
      _hasAutoChecked = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _checkUpdate(auto: true));
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkUpdate({bool auto = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final info = await AppUpdateService().checkUpdate();
      if (!mounted) return;
      if (info != null) {
        showUpdateDialog(context, info);
      } else if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✨ 当前已是最新版本，无需更新'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('检查更新超时，请检查网络或配置代理'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark(context);
    ThemeController.applySystemOverlay(isDark);

    // 状态栏精准配置：白天深色字、夜晚浅色字，彻底杜绝状态栏时间被白色遮挡
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark ? AppTheme.darkCard : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        appBar: AppBar(
          systemOverlayStyle: overlayStyle,
          title: Row(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, v, _) => Transform.scale(
                scale: v,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9A9E), AppTheme.primary],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('助',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('小助手',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.3)),
                Text('聚合工具箱',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B))),
              ],
            ),
          ]),
          actions: [
            // 昼夜模式切换按钮（带微动效）
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ThemeController.instance.toggle(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) =>
                          RotationTransition(turns: anim, child: child),
                      child: Icon(
                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        key: ValueKey<bool>(isDark),
                        size: 18,
                        color: isDark
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 检查更新按钮
            Container(
              margin: const EdgeInsets.only(right: 14),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _checking ? null : () => _checkUpdate(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(children: [
                    _checking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary))
                        : const Icon(Icons.sync_rounded,
                            size: 16, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    const Text('更新',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ]),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 现代化渐变主横幅（自适应时间段问候 + 左右拟人摆动手掌）
              AppAnimations.popIn(
                index: 0,
                child: FadeTransition(
                  opacity: _heroCtrl,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8E99), AppTheme.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const _WavingHand(),
                          const SizedBox(width: 10),
                          Text(_greeting(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5)),
                          const Spacer(),
                          BreathingDots(color: Colors.white, size: 6),
                        ]),
                        const SizedBox(height: 8),
                        Text('今日已就绪 · 选择下方工具开始使用',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text('核心工具',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155),
                        letterSpacing: 0.5)),
              ),

              // 工具卡片 1: 电信登录助手（文案精炼，无标签）
              AppAnimations.popIn(
                index: 1,
                child: _ModernToolCard(
                  color: AppTheme.ctColor,
                  gradientColors: const [Color(0xFF1E88E5), Color(0xFF005BAC)],
                  icon: Icons.phone_android_rounded,
                  title: '电信登录助手',
                  desc: '登录提取设备与转换 ID',
                  onTap: () => _open(context, const CtLoginPage()),
                ),
              ),

              const SizedBox(height: 12),

              // 工具卡片 2: 央视频CK获取（文案精炼，无标签）
              AppAnimations.popIn(
                index: 2,
                child: _ModernToolCard(
                  color: AppTheme.yspColor,
                  gradientColors: const [Color(0xFFFF6550), Color(0xFFE43D2B)],
                  icon: Icons.play_arrow_rounded,
                  title: '央视频CK获取',
                  desc: '一键提取完整登录凭证',
                  onTap: () => _open(context, const YspckPage()),
                ),
              ),

              const SizedBox(height: 12),

              // 工具卡片 3: 中通会员助手（文案精炼，无标签）
              AppAnimations.popIn(
                index: 3,
                child: _ModernToolCard(
                  color: AppTheme.ztoColor,
                  gradientColors: const [Color(0xFF2C3E8C), Color(0xFF1A2A6C)],
                  icon: Icons.local_shipping_rounded,
                  title: '中通会员助手',
                  desc: '账号登录与找回密码',
                  onTap: () => _open(context, const ZtoPage()),
                ),
              ),

              const SizedBox(height: 26),

              // 底部开发中状态指示
              AppAnimations.slideUp(
                index: 4,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text('更多实用功能持续扩展中',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF475569))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 使用原生 Material 路由转场，三个工具完全统一，秒开直入，杜绝掉帧
  void _open(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  /// 智能识别时间返回问候语
  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 9) return '早上好！';
    if (h >= 9 && h < 12) return '上午好！';
    if (h >= 12 && h < 14) return '中午好！';
    if (h >= 14 && h < 18) return '下午好！';
    if (h >= 18 && h < 23) return '晚上好！';
    return '夜深了，早点休息！';
  }
}

/// 👋 左右拟人摆动手掌
class _WavingHand extends StatefulWidget {
  const _WavingHand();

  @override
  State<_WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<_WavingHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final angle = (_ctrl.value * 28 - 14) * 3.14159 / 180;
        return Transform.rotate(
          angle: angle,
          origin: const Offset(-2, 12),
          child: const Text('👋', style: TextStyle(fontSize: 26)),
        );
      },
    );
  }
}

/// 现代化精美毛边悬浮卡片（无冗余标签，文案精炼，暗黑模式自适应，高对比度清晰字体）
class _ModernToolCard extends StatelessWidget {
  final Color color;
  final List<Color> gradientColors;
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  const _ModernToolCard({
    required this.color,
    required this.gradientColors,
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark(context);

    return AppWidgets.bounceCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isDark ? 0.12 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF475569),
                        height: 1.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
              size: 15),
        ]),
      ),
    );
  }
}
