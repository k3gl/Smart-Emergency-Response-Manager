import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// A living, animated gradient background: soft colour "glows" that slowly
/// drift, giving depth and motion without image assets. Uses cheap radial
/// gradients (no real-time blur) so it stays smooth even in debug / on
/// emulators. Place content as [child] on top.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _AuroraPainter(Curves.easeInOut.transform(_c.value)),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  void _glow(Canvas canvas, Size s, Offset c, Color color, double radius) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.40), color.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: c, radius: radius));
    canvas.drawCircle(c, radius, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppTheme.bg);
    final w = size.width, h = size.height;

    _glow(canvas, size,
        Offset(w * lerpDouble(0.0, 0.25, t)!, h * lerpDouble(0.02, 0.18, t)!),
        AppTheme.primary, w * 0.75);
    _glow(canvas, size,
        Offset(w * lerpDouble(1.0, 0.75, t)!, h * lerpDouble(0.15, 0.35, t)!),
        const Color(0xFF7C5CFF), w * 0.70);
    _glow(canvas, size,
        Offset(w * lerpDouble(0.35, 0.6, t)!, h * lerpDouble(1.0, 0.8, t)!),
        AppTheme.accent, w * 0.65);

    // Slight darkening so foreground text stays crisp.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.22));
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

/// A translucent "glass" panel for forms/cards on top of the aurora. Uses a
/// semi-transparent fill + border (no live blur) so it's cheap to render.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}
