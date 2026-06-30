import 'package:flutter/material.dart';
import '../../models/station_model.dart';
import '../../models/unit_model.dart';
import '../../services/dispatch_service.dart';
import '../../theme/app_theme.dart';
import 'units_screen.dart';

class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final DispatchService _service = DispatchService();
  List<Station> _stations = [];
  List<Unit> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final stations = await _service.getStations();
    final units = await _service.getAllUnits();
    setState(() {
      _stations = stations;
      _units = units;
      _loading = false;
    });
  }

  List<Unit> _unitsFor(String stationId) =>
      _units.where((u) => u.stationId == stationId).toList();

  Color _statusColor(String s) {
    switch (s) {
      case 'Available':
        return Colors.green;
      case 'Assigned':
        return Colors.orange;
      case 'Enroute':
        return Colors.amber;
      case 'OnScene':
        return Colors.purple;
      case 'Resolved':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stations & Units',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UnitsScreen()),
        ).then((_) => _refresh()),
        icon: const Icon(Icons.manage_accounts_outlined),
        label: const Text('Manage Units'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _stations.length,
                itemBuilder: (_, i) => _buildStationCard(_stations[i]),
              ),
            ),
    );
  }

  Widget _buildStationCard(Station s) {
    final units = _unitsFor(s.id);
    final available = units.where((u) => u.status == 'Available').length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.15),
          child: const Icon(Icons.local_police, color: AppTheme.primary),
        ),
        title: Text(s.name,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(
            '${s.address ?? ''}\n${units.length} units · $available available',
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        children: units.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No units at this station yet.'),
                )
              ]
            : units.map((u) => _buildUnitTile(u)).toList(),
      ),
    );
  }

  Widget _buildUnitTile(Unit u) {
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: _typeColor(u.unitType).withOpacity(0.15),
        child: Icon(
          u.unitType == 'POLICE'
              ? Icons.local_police_outlined
              : u.unitType == 'AMBULANCE'
                  ? Icons.local_hospital_outlined
                  : Icons.local_fire_department_outlined,
          color: _typeColor(u.unitType),
          size: 20,
        ),
      ),
      title: Text(u.name.isNotEmpty ? '${u.name} · ${u.unitCode}' : u.unitCode,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(u.email.isEmpty
          ? '${u.unitType} · ${u.status} · unprovisioned'
          : '${u.unitType} · ${u.status} · ${u.email}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _statusColor(u.status).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(u.status,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _statusColor(u.status))),
      ),
    );
  }
}
