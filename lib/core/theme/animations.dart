import 'dart:math';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 现代化动画小部件集 — Flutter Q 弹动效
class AppAnimations {
  /// Q弹入场动画（curves.elasticOut）
  static Widget popIn({required Widget child, int index = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + index * 80),
      curve: Curves.elasticOut,
      builder: (context, value, _) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
    );
  }

  /// 上滑入场
  static Widget slideUp({required Widget child, int index = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 40.0, end: 0.0),
      duration: Duration(milliseconds: 400 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Transform.translate(
          offset: Offset(0, value),
          child: FadeTransition(
            opacity: AlwaysStoppedAnimation((1 - value / 40).clamp(0.0, 1.0)),
            child: child,
          ),
        );
      },
    );
  }

  /// 卡片按压弹性反馈
  static Widget bounce({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return _BounceWidget(onTap: onTap, child: child);
  }
}

class _BounceWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _BounceWidget({required this.child, required this.onTap});

  @override
  State<_BounceWidget> createState() => _BounceWidgetState();
}

class _BounceWidgetState extends State<_BounceWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    upperBound: 0.05,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.96).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
        ),
        child: widget.child,
      ),
    );
  }
}

/// 渐变背景（用于 AppBar / 横幅）
class GradientBox extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;
  final double radius;
  final EdgeInsetsGeometry padding;

  const GradientBox({
    super.key,
    required this.child,
    this.colors,
    this.radius = 20,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors ??
              const [Color(0xFFFF9A9E), AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// 玻璃拟态卡片（毛玻璃效果）
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 打字机动画文本（用于成功页/提示）
class TypeWriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;

  const TypeWriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 40),
  });

  @override
  State<TypeWriterText> createState() => _TypeWriterTextState();
}

class _TypeWriterTextState extends State<TypeWriterText> {
  String _display = '';
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() async {
    if (_idx >= widget.text.length) return;
    await Future.delayed(widget.speed);
    if (!mounted) return;
    setState(() {
      _idx++;
      _display = widget.text.substring(0, _idx);
    });
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_display, style: widget.style);
  }
}

/// 呼吸圆点（加载指示）
class BreathingDots extends StatefulWidget {
  final Color color;
  final double size;

  const BreathingDots({super.key, this.color = AppTheme.primary, this.size = 8});

  @override
  State<BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<BreathingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = sin((_ctrl.value * 2 * pi) + (i * pi / 2));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.3 + (t + 1) / 2 * 0.7),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

/// 3D 卡片翻转动画（用于成功/失败状态切换）
class FlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  final bool showBack;

  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.showBack,
  });

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.showBack) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant FlipCard old) {
    super.didUpdateWidget(old);
    if (old.showBack != widget.showBack) {
      widget.showBack ? _ctrl.forward() : _ctrl.reverse();
    }
  }

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
        final angle = _ctrl.value * pi;
        final isBack = angle > pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: isBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: widget.back,
                )
              : widget.front,
        );
      },
    );
  }
}
