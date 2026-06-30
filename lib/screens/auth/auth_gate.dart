import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../admin/admin_dashboard.dart';
import '../citizen/citizen_dashboard.dart';
import '../unit/unit_dashboard.dart';
import 'welcome_screen.dart';

/// Decides the first screen on app start.
///
/// Supabase already persists the auth session across restarts, so if someone
/// is still signed in we skip the login screen and route straight to their
/// dashboard (Unit / Admin / Citizen). Otherwise we show Login.
///
/// This widget is the app's `'/'` route, so logging out (which navigates back
/// to `'/'`) re-runs the check and lands on Login.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  final SupabaseClient _supabase = Supabase.instance.client;
  Widget? _home;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final session = _supabase.auth.currentSession;

    // Not signed in (or session could not be restored) -> Login.
    if (session == null) {
      if (mounted) setState(() => _home = const WelcomeScreen());
      return;
    }

    // Signed in: route by role, exactly like the login flow does.
    final dest = await _auth.resolveDestination(session.user.id);
    Widget home;
    switch (dest) {
      case LoginDestination.unit:
        home = const UnitDashboard();
        break;
      case LoginDestination.admin:
        home = const AdminDashboard();
        break;
      case LoginDestination.citizen:
        home = const CitizenDashboard();
        break;
      case LoginDestination.none:
        // Session exists but the account isn't provisioned / is disabled.
        await _supabase.auth.signOut();
        home = const WelcomeScreen();
        break;
    }
    if (mounted) setState(() => _home = home);
  }

  @override
  Widget build(BuildContext context) {
    // While resolving, show a splash spinner.
    return _home ??
        const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
