import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/dispatch_service.dart';
import '../../theme/app_theme.dart';

class IncidentDetailScreen extends StatefulWidget {
  final String incidentId;
  const IncidentDetailScreen({super.key, required this.incidentId});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  final supabase = Supabase.instance.client;
  final DispatchService _service = DispatchService();
  Map<String, dynamic>? _incident;
  List<Map<String, dynamic>> _dispatches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final inc = await supabase
        .from('incidents')
        .select()
        .eq('id', widget.incidentId)
        .single();
    final dispatches = await _service.getDispatchesForIncident(widget.incidentId);
    setState(() {
      _incident = inc;
      _dispatches = dispatches;
      _loading = false;
    });
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'POLICE':
        return Colors.indigo;
      case 'AMBULANCE':
        return Colors.red;
      case 'FIRE':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'POLICE':
        return Icons.local_police_outlined;
      case 'AMBULANCE':
        return Icons.local_hospital_outlined;
      case 'FIRE':
        return Icons.local_fire_department_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_incident == null) {
      return const Scaffold(body: Center(child: Text('Incident not found')));
    }

    final inc = _incident!;
    final lat = (inc['latitude'] as num).toDouble();
    final lng = (inc['longitude'] as num).toDouble();
    final severity = inc['severity'] ?? 'UNKNOWN';
    final type = inc['incident_type'] ?? '-';
    final status = inc['status'] ?? '-';
    final desc = inc['description'] ?? '';
    final voiceUrl = inc['voice_url'];

    // Build markers + polylines for ALL dispatched units.
    final markers = <Marker>{
      Marker(
          markerId: const MarkerId('incident'),
          position: LatLng(lat, lng),
          infoWindow: const InfoWindow(title: 'Incident'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
    };
    final polylines = <Polyline>{};
    final allLats = <double>[lat];
    final allLngs = <double>[lng];

    for (var i = 0; i < _dispatches.length; i++) {
      final d = _dispatches[i];
      final unit = d['units'];
      final station = unit?['stations'];
      if (station == null) continue;
      final sLat = (station['latitude'] as num).toDouble();
      final sLng = (station['longitude'] as num).toDouble();
      allLats.add(sLat);
      allLngs.add(sLng);

      markers.add(Marker(
        markerId: MarkerId('station_$i'),
        position: LatLng(sLat, sLng),
        infoWindow: InfoWindow(
            title: station['name'] ?? 'Station',
            snippet: '${unit['unit_code']} (${unit['unit_type']})'),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          unit['unit_type'] == 'FIRE'
              ? BitmapDescriptor.hueOrange
              : unit['unit_type'] == 'AMBULANCE'
                  ? BitmapDescriptor.hueRose
                  : BitmapDescriptor.hueAzure,
        ),
      ));
      polylines.add(Polyline(
        polylineId: PolylineId('route_$i'),
        points: [LatLng(sLat, sLng), LatLng(lat, lng)],
        color: _typeColor(unit['unit_type']),
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    }

    final centerLat = allLats.reduce((a, b) => a + b) / allLats.length;
    final centerLng = allLngs.reduce((a, b) => a + b) / allLngs.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident Details',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusHeader(severity, status, type),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 260,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                      target: LatLng(centerLat, centerLng), zoom: 11),
                  markers: markers,
                  polylines: polylines,
                  zoomControlsEnabled: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _descriptionCard(desc, voiceUrl),
            const SizedBox(height: 16),
            const Text('Dispatched Units',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_dispatches.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.amber),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            'No units assigned yet — use "Add Unit" to dispatch one.')),
                  ],
                ),
              )
            else
              ..._dispatches.map((d) => _dispatchCard(d)),
            const SizedBox(height: 16),
            _actionButtons(status),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _statusHeader(String severity, String status, String type) {
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: sevColor, borderRadius: BorderRadius.circular(20)),
            child: Text(severity,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text('Type: $type',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(status,
              style: TextStyle(
                  color: Colors.grey[600], fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _descriptionCard(String desc, String? voiceUrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Description',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(desc.isEmpty ? '(none)' : desc),
          if (voiceUrl != null) ...[
            const SizedBox(height: 8),
            Text('Voice: $voiceUrl',
                style: const TextStyle(color: Colors.blue, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ]
        ],
      ),
    );
  }

  Widget _dispatchCard(Map<String, dynamic> d) {
    final unit = d['units'];
    final station = unit?['stations'];
    final type = unit?['unit_type'] ?? '?';
    final code = unit?['unit_code'] ?? '?';
    final stationName = station?['name'] ?? '?';
    final dist = d['distance_km'];
    final eta = d['eta_minutes'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stroke)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _typeColor(type).withOpacity(0.15),
            child: Icon(_typeIcon(type), color: _typeColor(type)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$code · $type',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(stationName,
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12)),
                Text('~$dist km · ~$eta min',
                    style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: 'Remove this unit',
            onPressed: () async {
              await _service.removeDispatch(
                  incidentId: widget.incidentId, unitId: unit['id']);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(String status) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showAddUnitSheet,
            icon: const Icon(Icons.add),
            label: const Text('Add Unit'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                status == 'Resolved' ? null : () => _confirmResolve(),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Resolve'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddUnitSheet() async {
    final inc = _incident!;
    final lat = (inc['latitude'] as num).toDouble();
    final lng = (inc['longitude'] as num).toDouble();
    // Available units that aren't already dispatched to this incident.
    final dispatchedIds = _dispatches.map((d) => d['unit_id']).toSet();

    final all = await supabase.from('units').select(
        'id, unit_code, unit_type, status, station_id, stations(name, latitude, longitude)').eq('status', 'Available');
    final available = (all as List)
        .where((u) => !dispatchedIds.contains(u['id']))
        .map((u) => Map<String, dynamic>.from(u))
        .toList();

    for (final u in available) {
      final s = u['stations'];
      if (s != null) {
        final eta = DispatchService.estimateDistanceAndEta(
          (s['latitude'] as num).toDouble(),
          (s['longitude'] as num).toDouble(),
          lat,
          lng,
        );
        u['_dist'] = eta.$1;
        u['_eta'] = eta.$2;
      }
    }
    available.sort((a, b) =>
        ((a['_eta'] ?? 9e9) as num).compareTo((b['_eta'] ?? 9e9) as num));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: available.isEmpty
            ? const Center(child: Text('No available units.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: available.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final u = available[i];
                  final s = u['stations'];
                  final dist =
                      (u['_dist'] as num?)?.toStringAsFixed(1) ?? '?';
                  final eta = (u['_eta'] as num?)?.round();
                  return ListTile(
                    leading: Icon(_typeIcon(u['unit_type'])),
                    title: Text('${u['unit_code']} (${u['unit_type']})'),
                    subtitle: Text(
                        '${s?['name'] ?? '?'} · $dist km · ~${eta ?? '?'} min'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _service.addDispatch(
                        incidentId: widget.incidentId,
                        unitId: u['id'],
                        incidentLat: lat,
                        incidentLng: lng,
                      );
                      _load();
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmResolve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resolve incident?'),
        content: const Text(
            'This marks the incident closed and frees ALL dispatched units.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resolve')),
        ],
      ),
    );
    if (ok == true) {
      await _service.resolveIncident(widget.incidentId);
      _load();
    }
  }
}
