import 'package:flutter/material.dart';
import '../../models/station_model.dart';
import '../../models/unit_model.dart';
import '../../services/auth_service.dart';
import '../../services/dispatch_service.dart';
import '../../theme/app_theme.dart';

/// Admin Units management.
///
/// Admin can:
///   * List all units (active and disabled).
///   * Create a new Unit row + auth credentials in one flow.
///   * Edit name / email / type / station.
///   * Disable (toggle is_active off, sets status Offline).
///   * Delete (hard delete of the units row; auth user is left in place).
class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  final DispatchService _service = DispatchService();
  final AuthService _auth = AuthService();
  List<Unit> _units = [];
  List<Station> _stations = [];
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Units Management',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUnitDialog,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Create Unit'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _units.length,
                itemBuilder: (_, i) => _unitTile(_units[i]),
              ),
            ),
    );
  }

  Widget _unitTile(Unit u) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.15),
          child: Icon(_typeIcon(u.unitType), color: AppTheme.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                  u.name.isNotEmpty ? '${u.name} (${u.unitCode})' : u.unitCode,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (!u.isActive)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('DISABLED',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.red,
                        fontWeight: FontWeight.bold)),
              )
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${u.unitType} · ${u.stationName ?? 'No station'}'),
            const SizedBox(height: 2),
            Text(u.email.isEmpty ? '(no email — unprovisioned)' : u.email,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 2),
            if (u.currentLatitude != null && u.currentLongitude != null)
              Text(
                  'Loc: ${u.currentLatitude!.toStringAsFixed(3)}, ${u.currentLongitude!.toStringAsFixed(3)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11))
            else
              const Text('Loc: unknown',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
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
        onTap: () => _showUnitActions(u),
      ),
    );
  }

  void _showUnitActions(Unit u) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${u.name} · ${u.unitCode}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit details'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(u);
              },
            ),
            if (u.authUserId == null)
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('Provision login credentials'),
                onTap: () {
                  Navigator.pop(context);
                  _showProvisionDialog(u);
                },
              ),
            ListTile(
              leading: Icon(
                  u.isActive ? Icons.block : Icons.check_circle_outline,
                  color: u.isActive ? Colors.orange : Colors.green),
              title: Text(u.isActive ? 'Disable unit' : 'Re-enable unit'),
              onTap: () async {
                Navigator.pop(context);
                await _service.setUnitActive(unitId: u.id, active: !u.isActive);
                _refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete unit',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final ok = await _confirmDelete(u);
                if (ok != true) return;
                await _service.deleteUnit(u.id);
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(Unit u) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Delete ${u.unitCode}?'),
          content: const Text(
              'This removes the unit record. The login account in auth.users '
              'is kept for audit purposes but will no longer match any unit.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------
  void _showCreateUnitDialog() {
    final codeCtrl  = TextEditingController();
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    String type = 'POLICE';
    String? stationId = _stations.isNotEmpty ? _stations.first.id : null;
    bool busy = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateD) => AlertDialog(
          title: const Text('Create Unit'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Display name (e.g. "Officer Adel")')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Unit code (e.g. POL-009)')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Login email (unique)')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Temporary password')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'POLICE', child: Text('POLICE')),
                      DropdownMenuItem(
                          value: 'AMBULANCE', child: Text('AMBULANCE')),
                      DropdownMenuItem(value: 'FIRE', child: Text('FIRE')),
                    ],
                    onChanged: (v) => setStateD(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: stationId,
                    decoration: const InputDecoration(labelText: 'Station'),
                    items: _stations
                        .map((s) => DropdownMenuItem(
                            value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setStateD(() => stationId = v),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                      'Note: creating an account will sign you out of the Admin '
                      'session. You will be returned to the login screen.',
                      style:
                          TextStyle(color: Colors.orange, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (codeCtrl.text.trim().isEmpty ||
                          nameCtrl.text.trim().isEmpty ||
                          emailCtrl.text.trim().isEmpty ||
                          passCtrl.text.length < 6 ||
                          stationId == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text(
                                'Fill all fields. Password must be ≥6 chars.')));
                        return;
                      }
                      setStateD(() => busy = true);

                      try {
                        final unitId = await _service.createUnitRow(
                          stationId: stationId!,
                          unitCode: codeCtrl.text.trim(),
                          name: nameCtrl.text.trim(),
                          email: emailCtrl.text.trim(),
                          unitType: type,
                        );
                        final res = await _service.provisionUnitAccount(
                          unitId: unitId,
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text.trim(),
                        );
                        if (res == null) {
                          throw Exception(
                              'Auth signup failed (email may already exist).');
                        }
                        if (!mounted) return;
                        // Drop the new unit's session and route admin to login.
                        await _auth.signOut();
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Unit created. Please sign back in as admin.'),
                          backgroundColor: Colors.green,
                        ));
                        Navigator.pushNamedAndRemoveUntil(
                            context, '/', (_) => false);
                      } catch (e) {
                        setStateD(() => busy = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Failed: $e')));
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit
  // ---------------------------------------------------------------------------
  void _showEditDialog(Unit u) {
    final codeCtrl  = TextEditingController(text: u.unitCode);
    final nameCtrl  = TextEditingController(text: u.name);
    final emailCtrl = TextEditingController(text: u.email);
    String type = u.unitType;
    String? stationId = u.stationId;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateD) => AlertDialog(
          title: Text('Edit ${u.unitCode}'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name')),
                TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Code')),
                TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'POLICE', child: Text('POLICE')),
                    DropdownMenuItem(
                        value: 'AMBULANCE', child: Text('AMBULANCE')),
                    DropdownMenuItem(value: 'FIRE', child: Text('FIRE')),
                  ],
                  onChanged: (v) => setStateD(() => type = v!),
                ),
                DropdownButtonFormField<String>(
                  value: stationId,
                  decoration: const InputDecoration(labelText: 'Station'),
                  items: _stations
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setStateD(() => stationId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await _service.updateUnit(
                  unitId: u.id,
                  unitCode: codeCtrl.text.trim(),
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  unitType: type,
                  stationId: stationId,
                );
                if (mounted) Navigator.pop(ctx);
                _refresh();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Provision credentials for a pre-existing units row (auth_user_id is null)
  // ---------------------------------------------------------------------------
  void _showProvisionDialog(Unit u) {
    final emailCtrl = TextEditingController(text: u.email);
    final passCtrl = TextEditingController();
    bool busy = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateD) => AlertDialog(
          title: const Text('Provision login'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email')),
                TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 8),
                const Text(
                    'You will be signed out of the Admin session after creation.',
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (emailCtrl.text.trim().isEmpty ||
                          passCtrl.text.length < 6) return;
                      setStateD(() => busy = true);
                      try {
                        await _service.updateUnit(
                            unitId: u.id, email: emailCtrl.text.trim());
                        final res = await _service.provisionUnitAccount(
                          unitId: u.id,
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text.trim(),
                        );
                        if (res == null) throw Exception('Auth signup failed');
                        await _auth.signOut();
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        Navigator.pushNamedAndRemoveUntil(
                            context, '/', (_) => false);
                      } catch (e) {
                        setStateD(() => busy = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Failed: $e')));
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Provision'),
            ),
          ],
        ),
      ),
    );
  }
}
