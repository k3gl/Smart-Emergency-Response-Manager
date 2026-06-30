import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch_queue_entry.dart';
import '../models/station_model.dart';
import '../models/unit_model.dart';

/// Same constants used by the Python worker so the numbers match.
const double kRoadFactor = 1.3;
const double kAvgCitySpeedKmh = 30.0;

/// Status values a unit can be in.  System sets [assigned] on dispatch; every
/// subsequent value is set by the unit itself.
class UnitStatus {
  static const available = 'Available';
  static const assigned  = 'Assigned';
  static const enroute   = 'Enroute';
  static const onScene   = 'OnScene';
  static const resolved  = 'Resolved';
  static const offline   = 'Offline';

  static const operationalSequence = [enroute, onScene];
  static const terminal             = [resolved, 'Completed', 'Closed'];

  static const all = [available, assigned, enroute, onScene, resolved, offline];
}

class DispatchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ---------- Stations ----------

  Future<List<Station>> getStations() async {
    final data = await _supabase
        .from('stations')
        .select()
        .order('name', ascending: true);
    return (data as List).map((e) => Station.fromMap(e)).toList();
  }

  // ---------- Units (admin reads) ----------

  Future<List<Unit>> getAllUnits() async {
    final data = await _supabase
        .from('units')
        .select('*, stations(name, latitude, longitude)')
        .order('unit_code', ascending: true);
    return (data as List).map((e) => Unit.fromMap(e)).toList();
  }

  Future<List<Unit>> getUnitsForStation(String stationId) async {
    final data = await _supabase
        .from('units')
        .select('*, stations(name, latitude, longitude)')
        .eq('station_id', stationId)
        .order('unit_code', ascending: true);
    return (data as List).map((e) => Unit.fromMap(e)).toList();
  }

  // ---------- Admin: Unit CRUD ----------
  //
  // Provisioning a Unit account in two steps is intentional:
  //   1) `createUnitRow` inserts a `units` row (no auth yet).
  //   2) `provisionUnitAccount` calls supabase.auth.signUp on the unit's
  //      credentials, then links the new auth.users.id back to the row.
  //
  // The signUp call will log the Admin out and into the new Unit's session
  // (Supabase Flutter only keeps one client).  The UI handles this by signing
  // back out and routing to /login with a "Please log back in as admin"
  // message.  This is documented in the Admin Units screen.

  Future<String> createUnitRow({
    required String stationId,
    required String unitCode,
    required String name,
    required String email,
    required String unitType,
  }) async {
    final row = await _supabase.from('units').insert({
      'station_id': stationId,
      'unit_code':  unitCode,
      'name':       name,
      'email':      email.toLowerCase(),
      'unit_type':  unitType,
      'status':     UnitStatus.available,
      'is_active':  true,
    }).select('id').single();
    return row['id'] as String;
  }

  /// Creates the auth user for an existing units row and links it back.
  ///
  /// IMPORTANT: this call replaces the admin's current Supabase session with
  /// the new unit's session.  The caller is responsible for signing out and
  /// routing the admin back to the login screen afterwards.
  Future<AuthResponse?> provisionUnitAccount({
    required String unitId,
    required String email,
    required String password,
  }) async {
    final res = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    final newAuthId = res.user?.id;
    if (newAuthId == null) return null;
    await _supabase
        .from('units')
        .update({'auth_user_id': newAuthId})
        .eq('id', unitId);
    return res;
  }

  Future<void> updateUnit({
    required String unitId,
    String? unitCode,
    String? name,
    String? email,
    String? unitType,
    String? stationId,
  }) async {
    final updates = <String, dynamic>{};
    if (unitCode  != null) updates['unit_code']  = unitCode;
    if (name      != null) updates['name']       = name;
    if (email     != null) updates['email']      = email.toLowerCase();
    if (unitType  != null) updates['unit_type']  = unitType;
    if (stationId != null) updates['station_id'] = stationId;
    if (updates.isEmpty) return;
    await _supabase.from('units').update(updates).eq('id', unitId);
  }

  Future<void> setUnitActive({required String unitId, required bool active}) async {
    await _supabase.from('units').update({
      'is_active': active,
      if (!active) 'status': UnitStatus.offline,
    }).eq('id', unitId);
  }

  Future<void> moveUnitToStation({
    required String unitId,
    required String newStationId,
  }) async {
    await _supabase
        .from('units')
        .update({'station_id': newStationId})
        .eq('id', unitId);
  }

  Future<void> deleteUnit(String unitId) async {
    await _supabase.from('units').delete().eq('id', unitId);
  }

  // ---------- Unit self-service ----------

  /// Look up the Unit row for the currently-signed-in auth user, or null if
  /// the user is not a Unit.
  Future<Unit?> getMyUnit() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    final data = await _supabase
        .from('units')
        .select('*, stations(name, latitude, longitude)')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    if (data == null) return null;
    return Unit.fromMap(data);
  }

  /// Push the unit's current GPS reading into the database.  Called
  /// periodically from the unit dashboard.
  Future<void> updateMyLocation({
    required String unitId,
    required double latitude,
    required double longitude,
  }) async {
    await _supabase.from('units').update({
      'current_latitude':  latitude,
      'current_longitude': longitude,
      'last_location_at':  DateTime.now().toIso8601String(),
    }).eq('id', unitId);
  }

  /// The Unit owns its operational state.
  ///
  /// The DB trigger `unit_status_after_resolve` will, on a terminal status,
  /// close the incident and bounce the unit back to Available — this method
  /// just sends the intent.
  Future<void> setMyStatus({
    required String unitId,
    required String status,
  }) async {
    await _supabase
        .from('units')
        .update({'status': status})
        .eq('id', unitId);
  }

  // ---------- Distance / ETA ----------

  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * R * math.asin(math.sqrt(a));
  }

  static double _deg2rad(double d) => d * (math.pi / 180);

  static (double, double) estimateDistanceAndEta(
      double lat1, double lng1, double lat2, double lng2) {
    final straight = haversineKm(lat1, lng1, lat2, lng2);
    final road = straight * kRoadFactor;
    final etaMin = (road / kAvgCitySpeedKmh) * 60.0;
    return (road, etaMin);
  }

  // ---------- Dispatches ----------

  Future<List<Map<String, dynamic>>> getDispatchesForIncident(String incidentId) async {
    final data = await _supabase
        .from('incident_dispatches')
        .select(
            '*, units(id, unit_code, unit_type, status, station_id, name, stations(id, name, latitude, longitude))')
        .eq('incident_id', incidentId)
        .order('eta_minutes', ascending: true);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> getActiveIncidentsForUnit(String unitId) async {
    final dispatches = await _supabase
        .from('incident_dispatches')
        .select('incident_id, distance_km, eta_minutes')
        .eq('unit_id', unitId);
    final ids = (dispatches as List)
        .map((r) => r['incident_id'])
        .where((v) => v != null)
        .toList();
    if (ids.isEmpty) return [];
    final incidents = await _supabase
        .from('incidents')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(incidents as List);
  }

  // ---------- Global dispatch queue (read + control) ----------
  //
  // The queue and all ordering/matching live in the database.  These methods
  // only read the waiting list for the admin UI and forward dispatch *intents*
  // to the engine functions — they never decide priority or pick units.

  /// The whole global queue, already in priority order
  /// (severity highest first, then oldest first).  Joins the incident so the
  /// admin can see what is waiting and why.
  Future<List<DispatchQueueEntry>> getDispatchQueue() async {
    final data = await _supabase
        .from('dispatch_queue')
        .select(
            '*, incidents(id, reporter_id, type, description, latitude, longitude, address, status, severity, assigned_unit_id, created_at)')
        .order('severity_rank', ascending: false)
        .order('enqueued_at', ascending: true);
    return (data as List).map((e) => DispatchQueueEntry.fromMap(e)).toList();
  }

  /// Live stream of the queue for a self-updating admin view.  Ordering is
  /// re-applied client-side because `.stream()` cannot order by a joined
  /// column; the authoritative ordering still lives in the DB index.
  Stream<List<DispatchQueueEntry>> watchDispatchQueue() {
    return _supabase
        .from('dispatch_queue')
        .stream(primaryKey: ['id']).map((rows) {
      final list = rows.map((e) => DispatchQueueEntry.fromMap(e)).toList();
      list.sort((a, b) {
        final s = b.severityRank.compareTo(a.severityRank);
        return s != 0 ? s : a.enqueuedAt.compareTo(b.enqueuedAt);
      });
      return list;
    });
  }

  /// Ask the engine to dispatch a unit of [unitType] to [incidentId]:
  /// dispatches the nearest available unit immediately, or enqueues the demand
  /// if none is free.  Returns true if a unit was dispatched.  This is the
  /// single entry point the incident-creation path should use.
  Future<bool> requestDispatch({
    required String incidentId,
    required String unitType,
  }) async {
    final res = await _supabase.rpc('request_dispatch', params: {
      'p_incident_id': incidentId,
      'p_unit_type': unitType,
    });
    return res == true;
  }

  /// Admin: drop a waiting demand from the queue (e.g. cancelled / handled
  /// manually).  Does not touch any already-dispatched unit.
  Future<void> removeFromQueue({
    required String incidentId,
    required String requiredUnitType,
  }) async {
    await _supabase
        .from('dispatch_queue')
        .delete()
        .eq('incident_id', incidentId)
        .eq('required_unit_type', requiredUnitType);
  }

  // ---------- Manual override (admin only) ----------

  Future<void> addDispatch({
    required String incidentId,
    required String unitId,
    required double incidentLat,
    required double incidentLng,
  }) async {
    final newUnit = await _supabase
        .from('units')
        .select('id, unit_type, stations(latitude, longitude)')
        .eq('id', unitId)
        .single();
    final s = newUnit['stations'];
    final eta = estimateDistanceAndEta(
      (s['latitude'] as num).toDouble(),
      (s['longitude'] as num).toDouble(),
      incidentLat,
      incidentLng,
    );

    await _supabase.from('incident_dispatches').insert({
      'incident_id': incidentId,
      'unit_id': unitId,
      'distance_km': double.parse(eta.$1.toStringAsFixed(2)),
      'eta_minutes': eta.$2.round(),
    });

    // The unit is *Assigned* by the system; it's still up to the Unit to
    // advance the state through Enroute / OnScene / Resolved.
    await _supabase.from('units').update({
      'status': UnitStatus.assigned,
      'current_incident_id': incidentId,
    }).eq('id', unitId);

    // A manual dispatch fulfills the demand for this type, so clear any
    // matching waiting row — otherwise the engine would later send a second
    // unit for the same need.
    await _supabase
        .from('dispatch_queue')
        .delete()
        .eq('incident_id', incidentId)
        .eq('required_unit_type', newUnit['unit_type']);
  }

  Future<void> removeDispatch({
    required String incidentId,
    required String unitId,
  }) async {
    await _supabase
        .from('incident_dispatches')
        .delete()
        .eq('incident_id', incidentId)
        .eq('unit_id', unitId);

    await _supabase.from('units').update({
      'status': UnitStatus.available,
      'current_incident_id': null,
    }).eq('id', unitId);

    await _recomputePrimary(incidentId);
  }

  Future<void> _recomputePrimary(String incidentId) async {
    final remaining = await _supabase
        .from('incident_dispatches')
        .select('unit_id, distance_km, eta_minutes')
        .eq('incident_id', incidentId)
        .order('eta_minutes', ascending: true);
    final list = remaining as List;
    if (list.isEmpty) {
      await _supabase.from('incidents').update({
        'assigned_unit_id': null,
        'eta_minutes': null,
        'distance_km': null,
        'status': 'Pending',
      }).eq('id', incidentId);
    } else {
      final first = list.first;
      await _supabase.from('incidents').update({
        'assigned_unit_id': first['unit_id'],
        'eta_minutes': first['eta_minutes'],
        'distance_km': first['distance_km'],
        'status': 'Assigned',
      }).eq('id', incidentId);
    }
  }

  /// Admin-side resolve (kept for the admin detail screen).  Functionally
  /// equivalent to a Unit marking itself Resolved — the trigger handles the
  /// cleanup in either case, but admins can call this even when no unit is
  /// dispatched.
  Future<void> resolveIncident(String incidentId) async {
    final dispatches = await _supabase
        .from('incident_dispatches')
        .select('unit_id')
        .eq('incident_id', incidentId);
    final unitIds = (dispatches as List)
        .map((d) => d['unit_id'])
        .where((v) => v != null)
        .toList();

    await _supabase.from('incidents').update({
      'status': 'Resolved',
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('id', incidentId);

    for (final uid in unitIds) {
      await _supabase.from('units').update({
        'status': UnitStatus.available,
        'current_incident_id': null,
      }).eq('id', uid);
    }
  }
}
