class WarningMarker {
  final String id;
  final double lat;
  final double lng;
  final String type; // e.g., 'police', 'accident', 'pothole', 'weather'
  final DateTime createdAt;
  final String createdBy; // userId

  WarningMarker({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.createdAt,
    required this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lat': lat,
      'lng': lng,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }

  factory WarningMarker.fromMap(Map<String, dynamic> map) {
    return WarningMarker(
      id: map['id'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      type: map['type'] ?? '',
      createdAt: map['createdAt'] != null 
          ? DateTime.parse(map['createdAt']) 
          : DateTime.now(),
      createdBy: map['createdBy'] ?? '',
    );
  }
}
