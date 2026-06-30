import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

/// Where a successful login should land the user.
///
///   * unit  -> /unit  (the auth user has a row in `units`)
///   * admin -> /admin
///   * citizen -> /citizen
///   * none  -> no profile + no unit row, treat as failure
enum LoginDestination { unit, admin, citizen, none }

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Citizen / Admin signup.
  //
  // Units are NEVER created here — they are provisioned by an admin from the
  // Units management screen.  The old `role: 'Unit'` + `unitId` parameters
  // have been removed on purpose.
  // ---------------------------------------------------------------------------
  Future<AuthResponse?> signUp({
    required String email,
    required String password,
    required String name,
    required String role, // 'Citizen' | 'Admin'
    String? emergencyName,
    String? emergencyPhone,
    required bool locationEnabled,
  }) async {
    assert(role != 'Unit', 'Units must be provisioned by an Admin.');
    try {
      final AuthResponse res = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      final User? user = res.user;
      if (user != null) {
        await _supabase.from('profiles').insert({
          'id': user.id,
          'name': name,
          'email': email,
          'role': role,
          'emergency_contact_name': emergencyName,
          'emergency_contact_phone': emergencyPhone,
          'location_enabled': locationEnabled,
        });
      }
      return res;
    } catch (e) {
      print('Error in Supabase Sign Up: $e');
      return null;
    }
  }

  Future<AuthResponse?> login(String email, String password) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('Error in Supabase Login: $e');
      return null;
    }
  }

  /// Decide where to route the freshly-logged-in user.
  ///
  /// Order is important: a Unit row wins over a `profiles.role`, so even if
  /// someone is accidentally also recorded as 'Admin' in `profiles` (legacy
  /// data) but has a units.auth_user_id link, they are still routed to /unit.
  Future<LoginDestination> resolveDestination(String authUserId) async {
    try {
      final unit = await _supabase
          .from('units')
          .select('id, is_active')
          .eq('auth_user_id', authUserId)
          .maybeSingle();
      if (unit != null) {
        if (unit['is_active'] == false) return LoginDestination.none;
        return LoginDestination.unit;
      }
    } catch (e) {
      print('resolveDestination/unit lookup error: $e');
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', authUserId)
          .maybeSingle();
      final role = profile?['role'] as String?;
      if (role == 'Admin') return LoginDestination.admin;
      if (role == 'Citizen') return LoginDestination.citizen;
    } catch (e) {
      print('resolveDestination/profile lookup error: $e');
    }

    return LoginDestination.none;
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (response != null) return UserModel.fromMap(response);
    } catch (e) {
      print('Error fetching user data: $e');
    }
    return null;
  }

  Future<void> signOut() async => _supabase.auth.signOut();
}
