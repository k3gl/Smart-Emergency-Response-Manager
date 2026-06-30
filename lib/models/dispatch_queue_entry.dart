import 'incident_model.dart';

/// One waiting demand in the global dispatch queue: an [incident] that needs
/// a unit of [requiredUnitType] but had none available when it was created.
///
/// This is purely a read-model for the admin "Dispatch Queue" view — the
/// queue's priority ([severityRank] desc, then [enqueuedAt] asc) and the
/// actual dispatch decision live in the database (see the
/// 20260623_dispatch_queue migration).  The app never decides ordering or
/// matching itself.
class DispatchQueueEntry {
  final String id;
  final String incidentId;
  final String requiredUnitType;   // POLICE | AMBULANCE | FIRE
  final int severityRank;          // 3=Critical, 2=Urgent, 1=Low (0=Fake/unknown)
  final DateTime enqueuedAt;
  final Incident? incident;        // joined when selected with `incidents(...)`

  DispatchQueueEntry({
    required this.id,
    required this.incidentId,
    required this.requiredUnitType,
    required this.severityRank,
    required this.enqueuedAt,
    this.incident,
  });

  factory DispatchQueueEntry.fromMap(Map<String, dynamic> data) {
    final inc = data['incidents'];
    return DispatchQueueEntry(
      id: data['id'] ?? '',
      incidentId: data['incident_id'] ?? '',
      requiredUnitType: data['required_unit_type'] ?? '',
      severityRank: (data['severity_rank'] as num?)?.toInt() ?? 0,
      enqueuedAt: DateTime.parse(data['enqueued_at']),
      incident: inc is Map<String, dynamic> ? Incident.fromMap(inc) : null,
    );
  }
}
