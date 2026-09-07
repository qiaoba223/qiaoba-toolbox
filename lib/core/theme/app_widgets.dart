import 'dart:ui';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 现代化卡片与动效组件库
class AppWidgets {
  /// 毛玻璃拟态微浮卡片 (Glassmorphic Surface)
  static Widget glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    double radius = 18,
    Color? color,
    Border? border,
    List<BoxShadow>? shadows,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(radius),
        border: border ??
            Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1,
            ),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
      ),
      child: child,
    );
  }

  /// 弹性微动效反馈
  static Widget bounceCard({
    required Widget child,
    required VoidCallback onTap,
    double scaleDown = 0.96,
  }) {
    return _InteractiveBounce(scaleDown: scaleDown, onTap: onTap, child: child);
  }
}

class _InteractiveBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleDown;

  const _InteractiveBounce({
    required this.child,
    required this.onTap,
    this.scaleDown = 0.96,
  });

  @override
  State<_InteractiveBounce> createState() => _InteractiveBounceState();
}

class _InteractiveBounceState extends State<_InteractiveBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 180),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: widget.scaleDown,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.elasticOut,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
