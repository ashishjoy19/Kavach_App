/// Parsed payload from fabacademy/kavach/sensor topic (JSON: temp, hum).
class SensorData {
  final double temp;
  final double hum;
  final DateTime receivedAt;

  const SensorData({
    required this.temp,
    required this.hum,
    required this.receivedAt,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      temp: (json['temp'] as num?)?.toDouble() ?? 0.0,
      hum: (json['hum'] as num?)?.toDouble() ?? 0.0,
      receivedAt: DateTime.now(),
    );
  }
}
