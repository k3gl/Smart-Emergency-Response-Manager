import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/user_model.dart';
import '../../services/feedback_service.dart';
import '../../theme/app_theme.dart';
import 'incident_rating_sheet.dart';

class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({super.key});

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard> {
  final supabase = Supabase.instance.client;
  UserModel? _userData;
  bool _isLoading = true;
  Position? _currentPosition;
  String _address = 'Fetching live location...';
  bool _isFetchingLocation = false;
  final _descriptionController = TextEditingController();
  bool _isSendingSos = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _audioPath;
  bool _isAnonymous = false; // citizen's choice to report anonymously

  // Active response (most recent unresolved incident + ALL units dispatched
  // to it).  The card hides as soon as no unit is in an active operational
  // state (Assigned / Enroute / OnScene).
  Map<String, dynamic>? _activeIncident;
  List<Map<String, dynamic>> _dispatchedUnits = [];
  Timer? _activeResponseTimer;

  // Fake / duplicate outcome cards are shown briefly then auto-hidden so the
  // citizen isn't left staring at a dead-end message forever.
  final Set<String> _expiredOutcomeIds = {};
  Timer? _outcomeTimer;
  String? _outcomeTimerId;

  // Feedback: resolved incidents this citizen reported that still need a rating.
  final FeedbackService _feedback = FeedbackService();
  List<Map<String, dynamic>> _unratedIncidents = [];
  final Set<String> _promptedFeedbackIds = {}; // already auto-prompted this session
  bool _ratingSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _determinePosition();
    _refreshActiveResponse();
    _checkFeedback();
    _activeResponseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshActiveResponse();
      _checkFeedback();
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _descriptionController.dispose();
    _activeResponseTimer?.cancel();
    _outcomeTimer?.cancel();
    super.dispose();
  }

  static const _activeUnitStatuses = ['Assigned', 'Enroute', 'OnScene'];

  Future<void> _refreshActiveResponse() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final inc = await supabase
          .from('incidents')
          .select()
          .eq('reporter_id', user.id)
          .neq('status', 'Resolved')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      List<Map<String, dynamic>> units = [];
      if (inc != null) {
        final dispatches = await supabase
            .from('incident_dispatches')
            .select('eta_minutes, distance_km, '
                'units(id, unit_code, unit_type, status, name, '
                'current_latitude, current_longitude, stations(name))')
            .eq('incident_id', inc['id'])
            .order('eta_minutes', ascending: true);
        for (final d in (dispatches as List)) {
          final u = d['units'];
          if (u == null) continue;
          final merged = Map<String, dynamic>.from(u as Map);
          merged['eta_minutes'] = d['eta_minutes'];
          merged['distance_km'] = d['distance_km'];
          units.add(merged);
        }
      }

      // Only show units that are still actively responding. A unit that
      // already marked itself Resolved is back to Available — the citizen
      // shouldn't see it on the active response card.
      final activeUnits = units
          .where((u) =>
              _activeUnitStatuses.contains(u['status'] as String?))
          .toList();

      // A fake or duplicate report is a dead-end (never dispatched). Show its
      // card for 5s, then auto-hide it.
      final incId = inc?['id'] as String?;
      final isFake = inc?['severity']?.toString().toUpperCase() == 'FAKE';
      final isDuplicate = inc?['has_duplicate'] == true;
      final isDeadEnd = activeUnits.isEmpty && (isFake || isDuplicate);

      if (isDeadEnd && incId != null) {
        if (_expiredOutcomeIds.contains(incId)) {
          // Already shown long enough — hide it.
          if (!mounted) return;
          setState(() {
            _activeIncident = null;
            _dispatchedUnits = [];
          });
          return;
        }
        // Not expired yet: show the outcome card (Rejected isn't a "waiting"
        // status, so we show it explicitly here) and schedule the auto-hide.
        if (_outcomeTimerId != incId) {
          _outcomeTimerId = incId;
          _outcomeTimer?.cancel();
          _outcomeTimer = Timer(const Duration(seconds: 5), () {
            _expiredOutcomeIds.add(incId);
            if (mounted) _refreshActiveResponse();
          });
        }
        if (!mounted) return;
        setState(() {
          _activeIncident = inc;
          _dispatchedUnits = [];
        });
        return;
      }

      // Show the card while a unit is actively responding, OR while the
      // incident is still pre-dispatch (being processed, or waiting in the
      // global queue for the next available unit).
      const waitingStatuses = {'Processing', 'Pending', 'Queued'};
      final incStatus = inc?['status'] as String?;
      final showCard =
          activeUnits.isNotEmpty || (inc != null && waitingStatuses.contains(incStatus));

      if (!mounted) return;
      setState(() {
        _activeIncident = showCard ? inc : null;
        _dispatchedUnits = activeUnits;
      });
    } catch (e) {
      print('Active response poll failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Feedback: detect resolved-but-unrated incidents, auto-prompt once each,
  // and keep the "rate past incidents" list fresh.
  // ---------------------------------------------------------------------------
  Future<void> _checkFeedback() async {
    try {
      final unrated = await _feedback.getUnratedResolvedIncidents();
      if (!mounted) return;
      setState(() => _unratedIncidents = unrated);

      // Auto-prompt the most recent incident we haven't already shown a sheet
      // for this session (only one sheet at a time).
      if (_ratingSheetOpen || unrated.isEmpty) return;
      Map<String, dynamic>? next;
      for (final inc in unrated) {
        if (!_promptedFeedbackIds.contains(inc['id'])) {
          next = inc;
          break;
        }
      }
      if (next == null) return;

      _promptedFeedbackIds.add(next['id'] as String);
      await _openRatingSheet(next);
    } catch (e) {
      print('Feedback check failed: $e');
    }
  }

  Future<void> _openRatingSheet(Map<String, dynamic> inc) async {
    if (_ratingSheetOpen || !mounted) return;
    _ratingSheetOpen = true;
    final label =
        (inc['incident_type'] ?? inc['type'] ?? 'Your incident').toString();
    final submitted = await showIncidentRatingSheet(
      context,
      incidentId: inc['id'] as String,
      subtitle: label,
    );
    _ratingSheetOpen = false;
    if (submitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Thanks for your feedback!'),
          backgroundColor: Colors.green,
        ));
      }
      await _checkFeedback(); // refresh the list (removes the rated one)
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase.from('profiles').select().eq('id', user.id).single();
        setState(() {
          _userData = UserModel.fromMap(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _determinePosition() async {
    setState(() {
      _isFetchingLocation = true;
      _address = 'Fetching live location...';
    });
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _address = 'Lat: ${position.latitude.toStringAsFixed(4)}, Long: ${position.longitude.toStringAsFixed(4)}';
        _isFetchingLocation = false;
      });
    } catch (e) {
      setState(() {
        _address = 'Location services disabled or denied.';
        _isFetchingLocation = false;
      });
    }
  }

  Future<void> _updateEmergencyContact() async {
    final nameController = TextEditingController(text: _userData?.emergencyContactName);
    final phoneController = TextEditingController(text: _userData?.emergencyContactPhone);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final user = supabase.auth.currentUser;
                await supabase.from('profiles').update({
                  'emergency_contact_name': nameController.text,
                  'emergency_contact_phone': phoneController.text,
                }).eq('id', user!.id);
                Navigator.pop(context);
                _loadUserData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact updated!')));
              } catch (e) {
                print('Update error: $e');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _audioPath = path;
      });
    } else {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/sos_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _audioPath = null;
        });
      }
    }
  }

  Future<void> _sendSos() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wait for location...')));
      return;
    }

    setState(() => _isSendingSos = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      String? voiceUrl;
      if (_audioPath != null) {
        final file = File(_audioPath!);
        final fileName = 'sos_${user.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await supabase.storage.from('voice_incidents').upload(fileName, file);
        voiceUrl = supabase.storage.from('voice_incidents').getPublicUrl(fileName);
      }

      await supabase.from('incidents').insert({
        'reporter_id': user.id,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'description': _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        'voice_url': voiceUrl,
        'is_anonymous': _isAnonymous,
        'status': 'Processing',
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS Sent! Help is on the way.'), backgroundColor: Colors.green));
      _descriptionController.clear();
      setState(() {
        _audioPath = null;
        _isSendingSos = false;
        _isAnonymous = false;
      });
      _refreshActiveResponse();
    } catch (e) {
      setState(() => _isSendingSos = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textHi));
  }

  // ---------------------------------------------------------------------------
  // Active response card  — shows what the responding unit is doing.
  //
  // Status mapping (matches dispatch_service.UnitStatus):
  //   Available  : not yet picked up (rare; usually the incident has no unit yet)
  //   Assigned   : "Dispatch assigned a unit"
  //   Enroute    : "On the way"
  //   OnScene    : "Help has arrived"
  //   Resolved   : closed (we hide the card when the incident is Resolved)
  // ---------------------------------------------------------------------------
  // A simple centered status card (icon + title + body) for the pre-dispatch
  // / outcome states (waiting, fake, duplicate).
  Widget _statusCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: color),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.textHi)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textLo, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildActiveResponseCard() {
    final units = _dispatchedUnits;

    // No unit dispatched yet. Decide what to tell the citizen based on the
    // incident's outcome so they're never stuck on an endless "please wait":
    //   * FAKE       -> the report wasn't recognised as a real emergency.
    //   * duplicate  -> matched to an emergency already being handled.
    //   * otherwise  -> genuinely waiting for a unit.
    if (units.isEmpty) {
      final inc = _activeIncident;
      final severity = inc?['severity']?.toString().toUpperCase();
      final isFake = severity == 'FAKE';
      final isDuplicate = inc?['has_duplicate'] == true;

      if (isFake) {
        return _statusCard(
          icon: Icons.gpp_bad_rounded,
          color: AppTheme.accent,
          title: 'Report not verified',
          body: "This report wasn't recognised as a genuine emergency. "
              "If this is real, call 122 / 123 / 118, or send a clearer "
              "description.",
        );
      }
      if (isDuplicate) {
        return _statusCard(
          icon: Icons.verified_rounded,
          color: Colors.green,
          title: 'Already being handled',
          body: 'We matched your report to an emergency already in progress '
              'nearby. Responders are on the way.',
        );
      }
      return _statusCard(
        icon: Icons.hourglass_top_rounded,
        color: Colors.blueGrey,
        title: 'Please wait…',
        body: 'We are handling your request.',
      );
    }

    // A unit is now assigned / on the way — show the real response info.
    // Headline reflects the *furthest along* unit ("Help has arrived" beats
    // "Help is on the way" beats "Units have been assigned").
    String headline;
    Color color;
    IconData icon;

    bool any(String s) => units.any((u) => u['status'] == s);
    if (any('OnScene')) {
      headline = 'Help has arrived';
      color = Colors.purple;
      icon = Icons.location_on_rounded;
    } else if (any('Enroute')) {
      headline = 'Help is on the way';
      color = Colors.orange;
      icon = Icons.directions_car_filled_rounded;
    } else {
      headline = 'Units have been assigned';
      color = Colors.blue;
      icon = Icons.assignment_turned_in_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(headline,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...units.map(_buildUnitRow),
        ],
      ),
    );
  }

  Widget _buildUnitRow(Map<String, dynamic> u) {
    final status = (u['status'] as String?) ?? '—';
    final type = (u['unit_type'] as String?) ?? '—';
    final code = (u['unit_code'] as String?) ?? '—';
    final eta = u['eta_minutes'];
    final dist = u['distance_km'];

    Color color;
    IconData icon;
    switch (type) {
      case 'POLICE':
        color = Colors.indigo;
        icon = Icons.local_police_outlined;
        break;
      case 'AMBULANCE':
        color = Colors.red;
        icon = Icons.local_hospital_outlined;
        break;
      case 'FIRE':
        color = Colors.deepOrange;
        icon = Icons.local_fire_department_outlined;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$type · $code',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (eta != null && dist != null)
                  Text('~$dist km · ETA ~$eta min',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackTile(Map<String, dynamic> inc) {
    final label =
        (inc['incident_type'] ?? inc['type'] ?? 'Incident').toString();
    final whenRaw = inc['resolved_at'] ?? inc['created_at'];
    String when = '';
    if (whenRaw != null) {
      final d = DateTime.tryParse(whenRaw.toString());
      if (d != null) {
        final diff = DateTime.now().difference(d);
        when = diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : '${diff.inDays}d ago';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.star_rounded, color: Colors.amber),
        ),
        title: Text(label.isEmpty ? 'Incident' : label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(when.isEmpty ? 'Resolved' : 'Resolved · $when',
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: ElevatedButton(
          onPressed: () => _openRatingSheet(inc),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Rate'),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required Color iconColor, required String title, required String subtitle, required String action, required VoidCallback onAction}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13))])),
          TextButton(onPressed: onAction, child: Text(action, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.logout_rounded), onPressed: () async { await supabase.auth.signOut(); Navigator.pushReplacementNamed(context, '/'); }),
        actions: [Padding(padding: const EdgeInsets.only(right: 16.0), child: Center(child: Text(_userData?.name ?? '', style: const TextStyle(fontWeight: FontWeight.bold))))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle('Your Status'),
            const SizedBox(height: 12),
            _buildInfoCard(
              icon: _isFetchingLocation ? Icons.sync : Icons.location_on_rounded,
              iconColor: Colors.red,
              title: 'Current Location',
              subtitle: _address,
              action: _currentPosition == null ? 'Retry' : 'Map',
              onAction: () {
                if (_currentPosition == null) { _determinePosition(); } else {
                   showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (context) => SizedBox(height: MediaQuery.of(context).size.height * 0.7, child: Column(children: [const SizedBox(height: 10), Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))), const SizedBox(height: 10),
                          Expanded(child: GoogleMap(initialCameraPosition: CameraPosition(target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 15), myLocationEnabled: true, markers: { Marker(markerId: const MarkerId('current'), position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude)) })),
                        ])));
                }
              },
            ),
            const SizedBox(height: 12),
            _buildInfoCard(icon: Icons.contact_phone_rounded, iconColor: Colors.blue, title: 'Emergency Contact', subtitle: '${_userData?.emergencyContactName ?? 'None'} • ${_userData?.emergencyContactPhone ?? ''}', action: 'Change', onAction: _updateEmergencyContact),
            if (_activeIncident != null) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('Active Response'),
              const SizedBox(height: 12),
              _buildActiveResponseCard(),
            ],
            if (_unratedIncidents.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('Rate Your Past Incidents'),
              const SizedBox(height: 12),
              ..._unratedIncidents.map(_buildFeedbackTile),
            ],
            const SizedBox(height: 32),
            _buildSectionTitle('Report Incident'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(controller: _descriptionController, maxLines: 4, decoration: const InputDecoration(hintText: 'Describe incident or use voice...', border: OutlineInputBorder(borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderSide: BorderSide.none))),
                  CheckboxListTile(
                    value: _isAnonymous,
                    onChanged: (v) => setState(() => _isAnonymous = v ?? false),
                    title: const Text('Report anonymously'),
                    subtitle: const Text('Hide my identity from this report'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppTheme.primary,
                  ),
                  const SizedBox(height: 12),
                  _isSendingSos ? const Center(child: CircularProgressIndicator()) : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _toggleRecording,
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic_rounded, color: _isRecording ? Colors.red : Colors.blue),
                          label: Text(_isRecording ? 'STOP' : 'Record Voice'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _sendSos,
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('SEND SOS'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                        ),
                      ),
                    ],
                  ),
                  if (_audioPath != null) const Padding(padding: EdgeInsets.only(top: 8.0), child: Text('Voice recorded successfully ✅', style: TextStyle(color: Colors.green, fontSize: 12))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
