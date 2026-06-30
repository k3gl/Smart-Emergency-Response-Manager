import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../theme/entrance_fade.dart';
import 'stations_screen.dart';
import 'units_screen.dart';
import 'incident_detail_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supabase = Supabase.instance.client;

  // Severity ranking for queue ordering: higher = more urgent.
  static const Map<String, int> _severityRank = {
    'CRITICAL': 3,
    'URGENT': 2,
    'LOW': 1,
  };

  int _rankOf(String? s) => _severityRank[s ?? ''] ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.logout_rounded),
          onPressed: () async {
            await supabase.auth.signOut();
            if (mounted) Navigator.pushReplacementNamed(context, '/');
          },
        ),
        actions: [
          CircleAvatar(
            backgroundColor: AppTheme.primary.withOpacity(0.18),
            child: const Icon(Icons.person, color: AppTheme.primary),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('incidents')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data ?? [];
          final assignedCount =
              all.where((i) => i['status'] == 'Assigned').length;
          final pending = all.where((i) => i['status'] == 'Pending').toList();
          final resolved =
              all.where((i) => i['status'] == 'Resolved').length;

          // Live queue: anything not yet resolved, sorted by severity desc, time asc.
          final queue = all
              .where((i) =>
                  i['status'] != 'Resolved' &&
                  i['status'] != 'Processing' &&
                  i['status'] != 'Rejected')
              .toList()
            ..sort((a, b) {
              final ra = _rankOf(a['severity']);
              final rb = _rankOf(b['severity']);
              if (ra != rb) return rb.compareTo(ra);
              final ta = DateTime.parse(a['created_at']);
              final tb = DateTime.parse(b['created_at']);
              return ta.compareTo(tb);
            });

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('System Overview',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textHi)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                          title: 'Assigned',
                          value: assignedCount.toString(),
                          color: Colors.orange,
                          icon: Icons.local_shipping_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                          title: 'Pending',
                          value: pending.length.toString(),
                          color: Colors.blue,
                          icon: Icons.hourglass_empty_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                          title: 'Resolved',
                          value: resolved.toString(),
                          color: Colors.green,
                          icon: Icons.check_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text('Unit Management',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'Stations',
                        icon: Icons.location_city_outlined,
                        color: Colors.blue[700]!,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const StationsScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        label: 'Units',
                        icon: Icons.local_police_outlined,
                        color: Colors.indigo,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const UnitsScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text('Live Queue (severity → time)',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (queue.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(child: Text('Queue is empty.')),
                    ),
                  )
                else
                  Column(
                    children: queue
                        .asMap()
                        .entries
                        .map((e) => EntranceFade(
                              delay: Duration(milliseconds: 50 * e.key),
                              child: _IncidentTile(incident: e.value),
                            ))
                        .toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  final Map<String, dynamic> incident;
  const _IncidentTile({required this.incident});

  Color _sevColor(String s) {
    switch (s) {
      case 'CRITICAL':
        return Colors.red;
      case 'URGENT':
        return Colors.orange;
      case 'LOW':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = incident['severity'] ?? 'UNKNOWN';
    final type = incident['incident_type'] ?? '-';
    final status = incident['status'] ?? '-';
    final lat = (incident['latitude'] as num).toStringAsFixed(4);
    final long = (incident['longitude'] as num).toStringAsFixed(4);
    final eta = incident['eta_minutes'];
    final dist = incident['distance_km'];

    final created = DateTime.parse(incident['created_at']);
    final diff = DateTime.now().difference(created);
    final ago = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.stroke),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: _sevColor(severity).withOpacity(0.15),
          child: Icon(Icons.notification_important_rounded,
              color: _sevColor(severity)),
        ),
        title: Text('Type: $type',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Loc: $lat, $long'),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(ago, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                if (eta != null && dist != null) ...[
                  const SizedBox(width: 8),
                  Text('· ~$dist km · $eta min',
                      style:
                          const TextStyle(color: Colors.blue, fontSize: 12)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text('Status: $status',
                style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: _sevColor(severity),
              borderRadius: BorderRadius.circular(20)),
          child: Text(severity,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncidentDetailScreen(incidentId: incident['id']),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  const _StatCard(
      {required this.title,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textHi)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(color: AppTheme.textLo, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }
}
