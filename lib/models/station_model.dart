class Station {
  final String id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;

  Station({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory Station.fromMap(Map<String, dynamic> data) {
    return Station(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      address: data['address'],
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
    );
  }
}
