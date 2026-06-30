class Incident {
  final String id;
  final String reporterId;
  final String type;
  final String description;
  final String? voiceUrl;
  final double latitude;
  final double longitude;
  final String address;
  final String status;
  final String? severity;     // LOW | URGENT | CRITICAL (AI) — see severity_rank()
  final String? assignedUnitId;
  final DateTime timestamp;

  Incident({
    required this.id,
    required this.reporterId,
    required this.type,
    required this.description,
    this.voiceUrl,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.status,
    this.severity,
    this.assignedUnitId,
    required this.timestamp,
  });

  // Convert Supabase Map to Incident Object
  factory Incident.fromMap(Map<String, dynamic> data) {
    return Incident(
      id: data['id'] ?? '',
      reporterId: data['reporter_id'] ?? '',
      type: data['type'] ?? '',
      description: data['description'] ?? '',
      voiceUrl: data['voice_url'],
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      address: data['address'] ?? '',
      status: data['status'] ?? 'Pending',
      severity: data['severity'],
      assignedUnitId: data['assigned_unit_id'],
      timestamp: DateTime.parse(data['created_at']),
    );
  }

  // Convert Incident Object to Map for Supabase
  Map<String, dynamic> toMap() {
    return {
      'reporter_id': reporterId,
      'type': type,
      'description': description,
      'voice_url': voiceUrl,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status,
      'assigned_unit_id': assignedUnitId,
      // 'created_at' is usually handled by Supabase default now()
    };
  }
}
