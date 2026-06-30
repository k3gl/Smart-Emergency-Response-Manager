import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_logo.dart';
import '../../theme/aurora_background.dart';
import '../../theme/entrance_fade.dart';

/// Animated intro shown to logged-out users. Living aurora background +
/// staggered entrance, then routes into the login / register flow.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _logoC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                        parent: _logoC, curve: Curves.easeOutBack),
                    child: FadeTransition(
                      opacity: _logoC,
                      child: const AppLogo(size: 100),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const EntranceFade(
                  delay: Duration(milliseconds: 350),
                  child: Text(
                    'RESPONDER',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textHi,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const EntranceFade(
                  delay: Duration(milliseconds: 500),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Fast, intelligent emergency dispatch.\nHelp reaches you in minutes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textLo,
                        fontSize: 15.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                EntranceFade(
                  delay: const Duration(milliseconds: 750),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: const Text('Get Started'),
                  ),
                ),
                const SizedBox(height: 12),
                EntranceFade(
                  delay: const Duration(milliseconds: 900),
                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    child: const Text('Create an account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
