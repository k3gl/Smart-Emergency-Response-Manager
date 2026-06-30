import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/dispatch_service.dart';
import '../../theme/app_theme.dart';

class IncidentReportScreen extends StatefulWidget {
  final String incidentId;
  final String? typeHint;
  const IncidentReportScreen(
      {super.key, required this.incidentId, this.typeHint});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  final supabase = Supabase.instance.client;
  final DispatchService _service = DispatchService();
  final _formKey = GlobalKey<FormState>();
  final _actionsController = TextEditingController();
  final _outcomeController = TextEditingController();
  String _selectedType = 'Fire';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.typeHint != null && widget.typeHint!.isNotEmpty) {
      // try to map AI dispatch type to readable label
      final h = widget.typeHint!.toUpperCase();
      if (h.contains('FIRE')) _selectedType = 'Fire';
      else if (h.contains('AMBULANCE')) _selectedType = 'Medical';
      else if (h.contains('POLICE')) _selectedType = 'Crime';
      else _selectedType = 'Other';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Save the report row.
      await supabase.from('incident_reports').insert({
        'incident_id': widget.incidentId,
        'reporter_id': supabase.auth.currentUser?.id,
        'incident_type': _selectedType,
        'actions_taken': _actionsController.text.trim(),
        'outcome': _outcomeController.text.trim(),
      });

      // The Unit closes the incident by marking ITSELF Resolved.  The DB
      // trigger (`unit_status_after_resolve`) closes the incident and bounces
      // the unit back to Available — see the migration SQL.
      final me = await _service.getMyUnit();
      if (me != null) {
        await _service.setMyStatus(unitId: me.id, status: UnitStatus.resolved);
      } else {
        // No Unit row (an admin posting the report from the admin screen) —
        // fall back to the admin-side resolve path.
        await _service.resolveIncident(widget.incidentId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Report submitted. Incident closed.'),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post-Incident Report',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('Incident ID: ${widget.incidentId}',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: InputDecoration(
                  labelText: 'Incident Type',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                items: ['Fire', 'Medical', 'Crime', 'Other']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedType = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _actionsController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Actions Taken',
                  alignLabelWithHint: true,
                  hintText: 'Describe steps taken to resolve the incident...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _outcomeController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Outcome',
                  alignLabelWithHint: true,
                  hintText: 'Final state of the situation...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('Submit & Resolve',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
