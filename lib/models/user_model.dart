class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role; // Admin | Citizen  (Units no longer live in profiles)
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final bool locationEnabled;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.emergencyContactName,
    this.emergencyContactPhone,
    required this.locationEnabled,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': uid,
      'name': name,
      'email': email,
      'role': role,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'location_enabled': locationEnabled,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['id'] ?? map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'Citizen',
      emergencyContactName: map['emergency_contact_name'],
      emergencyContactPhone: map['emergency_contact_phone'],
      locationEnabled: map['location_enabled'] ?? false,
    );
  }
}
