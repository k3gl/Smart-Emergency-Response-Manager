import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/citizen/citizen_dashboard.dart';
import 'screens/unit/unit_dashboard.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

/// Background/terminated-state push handler. Must be a top-level function.
/// The OS shows notification-type messages automatically; this runs in a
/// separate isolate so we only need it registered, not doing UI work.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // No-op: the system tray notification is shown automatically.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Initialize Firebase (Android reads android/app/google-services.json).
  //    Skipped on web: web FCM needs separate config and isn't used there,
  //    and an unconfigured Firebase.initializeApp() would crash startup.
  if (!kIsWeb) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  }

  // 1. Initialize Supabase
  await Supabase.initialize(
    url: 'https://uhxnkufxjcqtmajkostv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoeG5rdWZ4amNxdG1hamtvc3R2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEzNjg3MDksImV4cCI6MjA4Njk0NDcwOX0.v-WrV0K1I3M92GfP74PZd4NeWthBfSf33bp-LU-4hhU',
  );

  // 2. Notification setup + keep the device token in sync with who is logged in.
  //    Push notifications are mobile-only; skip the whole block on web.
  if (!kIsWeb) {
    await NotificationService.instance.init();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
          NotificationService.instance.registerToken();
          break;
        case AuthChangeEvent.signedOut:
          NotificationService.instance.unregisterToken();
          break;
        default:
          break;
      }
    });
  }

  runApp(const IncidentDetectionApp());
}

class IncidentDetectionApp extends StatelessWidget {
  const IncidentDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Incident Detection App',
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: '/',
      routes: {
        // '/' is the auth gate: it keeps a signed-in user logged in across
        // restarts and routes them by role; otherwise it shows Login.
        '/': (context) => const AuthGate(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/admin': (context) => const AdminDashboard(),
        '/citizen': (context) => const CitizenDashboard(),
        '/unit': (context) => const UnitDashboard(),
      },
    );
  }
}
