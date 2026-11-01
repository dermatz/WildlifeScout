import 'package:latlong2/latlong.dart';

class SecretSpot {
  final String id;
  final String title;
  final String speciesId;
  final double latitude;
  final double longitude;
  final String notes;
  final String idealWindCardinal;
  final DateTime createdAt;

  const SecretSpot({
    required this.id,
    required this.title,
    required this.speciesId,
    required this.latitude,
    required this.longitude,
    required this.notes,
    required this.idealWindCardinal,
    required this.createdAt,
  });

  LatLng get coordinate => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'speciesId': speciesId,
    'latitude': latitude,
    'longitude': longitude,
    'notes': notes,
    'idealWindCardinal': idealWindCardinal,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SecretSpot.fromJson(Map<String, dynamic> json) {
    return SecretSpot(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Geheimer Ansitz',
      speciesId: json['speciesId']?.toString() ?? 'roe_deer',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 51.1657,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 10.4515,
      notes: json['notes']?.toString() ?? '',
      idealWindCardinal: json['idealWindCardinal']?.toString() ?? 'O',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
