/// Single alert event for history and frequency calculation.
class AlertRecord {
  final String id;
  final String type; // 'help' | 'temp' | 'hum'
  final String message;
  final DateTime at;

  const AlertRecord({
    required this.id,
    required this.type,
    required this.message,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'message': message,
        'at': at.toIso8601String(),
      };

  factory AlertRecord.fromJson(Map<String, dynamic> json) {
    return AlertRecord(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'help',
      message: json['message'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
