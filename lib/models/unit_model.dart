class Unit {
  final String id;
  final String? authUserId;
  final String? stationId;
  final String unitCode;
  final String name;
  final String email;
  final String unitType;      // POLICE | AMBULANCE | FIRE
  final String status;         // Available | Assigned | Enroute | OnScene | Resolved | Offline
  final String? currentIncidentId;
  final double? currentLatitude;
  final double? currentLongitude;
  final DateTime? lastLocationAt;
  final bool isActive;
  final String? stationName;   // joined from stations table when available

  Unit({
    required this.id,
    required this.authUserId,
    required this.stationId,
    required this.unitCode,
    required this.name,
    required this.email,
    required this.unitType,
    required this.status,
    required this.currentIncidentId,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.lastLocationAt,
    required this.isActive,
    required this.stationName,
  });

  factory Unit.fromMap(Map<String, dynamic> data) {
    final station = data['stations'];
    return Unit(
      id: data['id'] ?? '',
      authUserId: data['auth_user_id'] as String?,
      stationId: data['station_id'] as String?,
      unitCode: data['unit_code'] ?? '',
      name: data['name'] ?? data['unit_code'] ?? '',
      email: data['email'] ?? '',
      unitType: data['unit_type'] ?? 'POLICE',
      status: data['status'] ?? 'Available',
      currentIncidentId: data['current_incident_id'] as String?,
      currentLatitude: (data['current_latitude'] as num?)?.toDouble(),
      currentLongitude: (data['current_longitude'] as num?)?.toDouble(),
      lastLocationAt: data['last_location_at'] != null
          ? DateTime.tryParse(data['last_location_at'].toString())
          : null,
      isActive: data['is_active'] ?? true,
      stationName: station is Map ? station['name'] as String? : null,
    );
  }
}
