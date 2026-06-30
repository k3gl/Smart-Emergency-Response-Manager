import 'package:flutter/material.dart';
import 'app_theme.dart';

/// The app's logo mark: a rounded gradient badge with a safety/emergency icon.
/// Used on the auth screens. Size scales everything inside it.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  const AppLogo({super.key, this.size = 84, this.showWordmark = false});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6AA0FF), Color(0xFF3D6BE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D6BE0).withOpacity(0.45),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.health_and_safety_rounded,
        color: Colors.white,
        size: size * 0.56,
      ),
    );

    if (!showWordmark) return badge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(height: 16),
        const Text(
          'RESPONDER',
          style: TextStyle(
            color: AppTheme.textHi,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}
