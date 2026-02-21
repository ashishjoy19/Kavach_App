/// Parsed payload from fabacademy/kavach/sensor topic (JSON).
/// Accepts keys: temp/temperature, hum/humidity (case-insensitive).
class SensorData {
  final double temp;
  final double hum;
  final DateTime receivedAt;

  const SensorData({
    required this.temp,
    required this.hum,
    required this.receivedAt,
  });

  static double _readNumber(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    }
    return 0.0;
  }

  factory SensorData.fromJson(Map<String, dynamic> json) {
    // Support common key names (case-sensitive for typical MQTT payloads)
    final temp = _readNumber(json, ['temp', 'temperature', 'Temp', 'Temperature']);
    final hum = _readNumber(json, ['hum', 'humidity', 'Hum', 'Humidity']);
    return SensorData(
      temp: temp,
      hum: hum,
      receivedAt: DateTime.now(),
    );
  }
}
