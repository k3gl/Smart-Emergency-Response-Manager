import 'package:supabase_flutter/supabase_flutter.dart';

/// Citizen-facing feedback operations: submit a 1–5 rating (+ optional comment)
/// for a resolved incident, and find which resolved incidents still need a
/// rating. All access is scoped to the signed-in citizen by RLS.
class FeedbackService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Insert a rating for an incident the current user reported.
  Future<void> submitFeedback({
    required String incidentId,
    required int rating,
    String? comment,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    final c = comment?.trim();
    await _supabase.from('incident_feedback').insert({
      'incident_id': incidentId,
      'reporter_id': uid,
      'rating': rating,
      'comment': (c != null && c.isNotEmpty) ? c : null,
    });
  }

  /// Resolved incidents reported by the current user that have NOT been rated
  /// yet, newest first. Used both for the auto-prompt and the "rate past
  /// incidents" list.
  Future<List<Map<String, dynamic>>> getUnratedResolvedIncidents() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    final resolved = await _supabase
        .from('incidents')
        .select('id, incident_type, severity, created_at, resolved_at')
        .eq('reporter_id', uid)
        .eq('status', 'Resolved')
        .order('resolved_at', ascending: false);

    final fb = await _supabase
        .from('incident_feedback')
        .select('incident_id')
        .eq('reporter_id', uid);
    final rated = (fb as List).map((f) => f['incident_id']).toSet();

    return (resolved as List)
        .map((e) => Map<String, dynamic>.from(e))
        .where((i) => !rated.contains(i['id']))
        .toList();
  }
}
