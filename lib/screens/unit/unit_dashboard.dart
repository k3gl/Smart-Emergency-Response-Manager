import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/unit_model.dart';
import '../../services/dispatch_service.dart';
import '../../theme/app_theme.dart';
import 'incident_report_screen.dart';

/// Unit dashboard.
///
/// Layout:
///   ┌──────────────────────────────────────────┐
///   │  TOP   – current assignment (incident +   │
///   │          dispatch report)                 │
///   ├──────────────────────────────────────────┤
///   │  BOT   – current status + status controls │
///   └──────────────────────────────────────────┘
class UnitDashboard extends StatefulWidget {
  const UnitDashboard({super.key});

  @override
  State<UnitDashboard> createState() => _UnitDashboardState();
}

class _UnitDashboardState extends State<UnitDashboard> {
  final supabase = Supabase.instance.client;
  final DispatchService _service = DispatchService();

  Unit? _me;
  Map<String, dynamic>? _activeIncident; // top-section incident
  Map<String, dynamic>? _myDispatch;     // distance / eta for that incident
  bool _loading = true;
  bool _busy = false;

  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _startLocationLoop();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Location reporting
  // ---------------------------------------------------------------------------
  void _startLocationLoop() {
    _pushLocationOnce();
    _locationTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _pushLocationOnce());
  }

  Future<void> _pushLocationOnce() async {
    final unitId = _me?.id;
    if (unitId == null) return;
    try {
      // Only report GPS while the unit is actually on a job.  When it's
      // Available/Offline the server parks it at its station (see
      // return_idle_units_to_station); reporting would just overwrite that.
      // Read the live status so a server-side dispatch is picked up even
      // before the dashboard refreshes _me.
      final row = await supabase
          .from('units')
          .select('status')
          .eq('id', unitId)
          .maybeSingle();
      final status = row?['status'] as String?;
      if (status == null || status == 'Available' || status == 'Offline') {
        return;
      }

      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _service.updateMyLocation(
        unitId: unitId,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (e) {
      // Silently ignore: location is best-effort.
      print('Location push failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final me = await _service.getMyUnit();
      if (me == null) {
        setState(() {
          _me = null;
          _loading = false;
        });
        return;
      }

      // The "current assignment" is the incident this unit is dispatched to
      // and that isn't yet resolved.  Worker writes units.current_incident_id
      // on assignment; we also fall back to looking up the most recent
      // unresolved dispatch row in case current_incident_id is null.
      Map<String, dynamic>? incident;
      Map<String, dynamic>? dispatch;

      final incidentId = me.currentIncidentId;
      if (incidentId != null) {
        final inc = await supabase
            .from('incidents')
            .select()
            .eq('id', incidentId)
            .maybeSingle();
        if (inc != null && inc['status'] != 'Resolved') {
          incident = Map<String, dynamic>.from(inc);
          final d = await supabase
              .from('incident_dispatches')
              .select()
              .eq('incident_id', incidentId)
              .eq('unit_id', me.id)
              .maybeSingle();
          if (d != null) dispatch = Map<String, dynamic>.from(d);
        }
      } else {
        // Fallback: maybe `current_incident_id` was cleared but a dispatch
        // still points at this unit and the incident isn't resolved.
        final ds = await supabase
            .from('incident_dispatches')
            .select('incident_id, distance_km, eta_minutes')
            .eq('unit_id', me.id);
        final list = List<Map<String, dynamic>>.from(ds as List);
        for (final d in list) {
          final inc = await supabase
              .from('incidents')
              .select()
              .eq('id', d['incident_id'])
              .maybeSingle();
          if (inc != null && inc['status'] != 'Resolved') {
            incident = Map<String, dynamic>.from(inc);
            dispatch = d;
            break;
          }
        }
      }

      setState(() {
        _me = me;
        _activeIncident = incident;
        _myDispatch = dispatch;
        _loading = false;
      });
    } catch (e) {
      print('UnitDashboard load error: $e');
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Status transitions
  // ---------------------------------------------------------------------------

  /// Which next-statuses make sense from `current`.
  ///
  /// Allowed:
  ///   Available -> Offline
  ///   Offline   -> Available
  ///   Assigned  -> Enroute / Resolved
  ///   Enroute   -> OnScene / Resolved
  ///   OnScene   -> Resolved
  ///   Resolved  -> (handled by trigger; will show Available)
  List<String> _nextStatusesFrom(String current) {
    switch (current) {
      case UnitStatus.available:
        return [UnitStatus.offline];
      case UnitStatus.offline:
        return [UnitStatus.available];
      case UnitStatus.assigned:
        return [UnitStatus.enroute, UnitStatus.resolved];
      case UnitStatus.enroute:
        return [UnitStatus.onScene, UnitStatus.resolved];
      case UnitStatus.onScene:
        return [UnitStatus.resolved];
      default:
        return [];
    }
  }

  Future<void> _setStatus(String next) async {
    final unit = _me;
    if (unit == null) return;
    setState(() => _busy = true);
    try {
      await _service.setMyStatus(unitId: unit.id, status: next);
      if (UnitStatus.terminal.contains(next)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Incident closed. You are back to Available.'),
          backgroundColor: Colors.green,
        ));
      }
      await _loadAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_me?.name.isNotEmpty == true ? _me!.name : 'Response Unit',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.logout_rounded),
          onPressed: () async {
            await supabase.auth.signOut();
            if (mounted) Navigator.pushReplacementNamed(context, '/');
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _me == null
          ? _noUnitView()
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // TOP: Assignment section
                  _topAssignmentSection(),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  // BOTTOM: Status + controls
                  _bottomStatusSection(),
                ],
              ),
            ),
    );
  }

  Widget _noUnitView() {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
            'This account is not linked to a Response Unit.\n\n'
            'Ask an administrator to provision your unit.',
            textAlign: TextAlign.center),
      ),
    );
  }

  // ---------------------- TOP: Assignment -----------------------------------
  Widget _topAssignmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Current Assignment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_activeIncident == null) _noAssignmentCard() else _assignmentCard(),
      ],
    );
  }

  Widget _noAssignmentCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stroke)),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: Colors.grey),
          SizedBox(height: 8),
          Text('No active assignment.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('You\'ll be notified when dispatch sends you an incident.',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _assignmentCard() {
    final i = _activeIncident!;
    final severity = i['severity'] ?? 'UNKNOWN';
    final type = i['incident_type'] ?? '-';
    final desc = i['description'] ?? '';
    final lat = (i['latitude'] as num).toDouble();
    final lng = (i['longitude'] as num).toDouble();
    final eta = _myDispatch?['eta_minutes'];
    final dist = _myDispatch?['distance_km'];
    final created = DateTime.parse(i['created_at']);
    final ago = _timeAgo(created);

    Color sevColor;
    switch (severity) {
      case 'CRITICAL':
        sevColor = Colors.red;
        break;
      case 'URGENT':
        sevColor = Colors.orange;
        break;
      case 'LOW':
        sevColor = Colors.blue;
        break;
      default:
        sevColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: severity chip + type
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: sevColor,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(severity,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Type: $type',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              Text(ago,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          // Map preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              child: GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: LatLng(lat, lng), zoom: 14),
                markers: {
                  Marker(
                      markerId: const MarkerId('inc'),
                      position: LatLng(lat, lng))
                },
                zoomControlsEnabled: false,
                liteModeEnabled: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Dispatch report
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dispatch Report',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Incident ID: ${i['id']}',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
                if (eta != null && dist != null) ...[
                  const SizedBox(height: 4),
                  Text('Approx $dist km · ETA ~$eta min',
                      style: const TextStyle(
                          color: Colors.blue, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 4),
                Text('Location: $lat, $lng',
                    style:
                        TextStyle(color: Colors.grey[700], fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Details
          Text(desc.isEmpty ? '(no description)' : desc,
              style: const TextStyle(color: AppTheme.textHi)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IncidentReportScreen(
                    incidentId: i['id'], typeHint: type),
              ),
            ).then((_) => _loadAll()),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Write incident report'),
          ),
        ],
      ),
    );
  }

  // ---------------------- BOTTOM: Status + Controls -------------------------
  Widget _bottomStatusSection() {
    final me = _me!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Unit Status',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${me.unitCode} · ${me.unitType}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Station: ${me.stationName ?? '-'}',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.circle, color: Colors.greenAccent, size: 12),
                  const SizedBox(width: 8),
                  Text('Current status: ${me.status}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              if (me.currentLatitude != null && me.currentLongitude != null) ...[
                const SizedBox(height: 4),
                Text(
                    'Last known location: ${me.currentLatitude!.toStringAsFixed(3)}, ${me.currentLongitude!.toStringAsFixed(3)}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Update status',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          _statusControls(),
      ],
    );
  }

  Widget _statusControls() {
    final me = _me!;
    final nexts = _nextStatusesFrom(me.status);
    if (nexts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No transitions available from this state.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: nexts.map((s) {
        final isTerminal = UnitStatus.terminal.contains(s);
        return ElevatedButton.icon(
          onPressed: () => _setStatus(s),
          icon: Icon(_iconForStatus(s), size: 18),
          label: Text(_labelForStatus(s)),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isTerminal ? Colors.green : Colors.blue[700],
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }).toList(),
    );
  }

  String _labelForStatus(String s) {
    switch (s) {
      case UnitStatus.enroute:
        return 'Going Enroute';
      case UnitStatus.onScene:
        return 'Arrived On Scene';
      case UnitStatus.resolved:
        return 'Mark Resolved';
      case UnitStatus.offline:
        return 'Go Offline';
      case UnitStatus.available:
        return 'Go Available';
      default:
        return s;
    }
  }

  IconData _iconForStatus(String s) {
    switch (s) {
      case UnitStatus.enroute:
        return Icons.directions_car;
      case UnitStatus.onScene:
        return Icons.location_on;
      case UnitStatus.resolved:
        return Icons.check_circle_outline;
      case UnitStatus.offline:
        return Icons.power_settings_new;
      case UnitStatus.available:
        return Icons.play_circle_outline;
      default:
        return Icons.flag_outlined;
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
