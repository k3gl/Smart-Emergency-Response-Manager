import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles FCM push notifications:
///   * asks the OS for notification permission,
///   * fetches this device's FCM token and registers it against the
///     logged-in user (via the `register_device_token` RPC),
///   * removes it on logout (`unregister_device_token`),
///   * routes the user to the right screen when they tap a notification.
///
/// A token identifies a *device*; registering ties it to whoever is logged in
/// now, so a device only receives notifications for its current user.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Used to navigate when a notification is tapped (set on MaterialApp).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _token;

  /// One-time setup: permission + message handlers. Call once at startup.
  Future<void> init() async {
    await _messaging.requestPermission(); // Android 13+ / iOS prompt

    _messaging.onTokenRefresh.listen((t) {
      _token = t;
      _saveToken(t);
    });

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onTapped);
    // App opened from terminated state by tapping a notification:
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onTapped(initial);
  }

  /// Fetch + store this device's token for the current user. Call after login
  /// / when a session is restored.
  Future<void> registerToken() async {
    try {
      final t = await _messaging.getToken();
      if (t == null) return;
      _token = t;
      await _saveToken(t);
    } catch (e) {
      debugPrint('registerToken failed: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    if (_supabase.auth.currentUser == null) return;
    try {
      await _supabase.rpc('register_device_token',
          params: {'p_token': token, 'p_platform': 'android'});
    } catch (e) {
      debugPrint('register_device_token RPC failed: $e');
    }
  }

  /// Remove this device's token (call on logout, before/after signOut).
  Future<void> unregisterToken() async {
    final t = _token ?? await _messaging.getToken();
    if (t == null) return;
    try {
      await _supabase
          .rpc('unregister_device_token', params: {'p_token': t});
    } catch (e) {
      debugPrint('unregister_device_token RPC failed: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    // App is open: show a lightweight in-app banner. (A full system
    // notification while foregrounded would need flutter_local_notifications.)
    final n = message.notification;
    final ctx = navigatorKey.currentContext;
    if (n == null || ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('${n.title ?? ''}${n.title != null ? ' — ' : ''}${n.body ?? ''}'),
      backgroundColor: Colors.blue[700],
    ));
  }

  void _onTapped(RemoteMessage message) {
    // Bring the user to their dashboard; the dashboard's own logic (e.g. the
    // citizen rating prompt, the unit's current assignment) takes over.
    // message.data may carry {'type': 'rate_incident'|'new_assignment', ...}.
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil('/', (route) => false);
  }
}
