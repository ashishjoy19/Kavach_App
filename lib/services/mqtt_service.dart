import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/alert_record.dart';
import '../models/sensor_data.dart';
import 'alert_repository.dart';
import 'notification_service.dart';

/// MQTT client: connects with username/password, subscribes to help and sensor topics.
class MqttService {
  MqttServerClient? _client;
  final AlertRepository _alerts = AlertRepository();
  final NotificationService _notifications = NotificationService();

  static const topicHelp = 'fabacademy/kavach/help';
  static const topicSensor = 'fabacademy/kavach/sensor';

  double tempThreshold = 35.0;
  double humThreshold = 80.0;

  final StreamController<SensorData?> _sensorController = StreamController<SensorData?>.broadcast();
  Stream<SensorData?> get sensorStream => _sensorController.stream;

  final StreamController<String> _helpController = StreamController<String>.broadcast();
  Stream<String> get helpStream => _helpController.stream;

  final StreamController<MqttConnectionState> _connectionController =
      StreamController<MqttConnectionState>.broadcast();
  Stream<MqttConnectionState> get connectionStream => _connectionController.stream;

  MqttConnectionState get connectionState => _client?.connectionStatus?.state ?? MqttConnectionState.disconnected;
  AlertRepository get alertRepository => _alerts;

  Future<void> connect({
    required String host,
    int port = 1883,
    required String username,
    required String password,
    String clientId = 'kavach_app',
  }) async {
    await disconnect();
    _client = MqttServerClient.withPort(host, clientId, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 60;
    _client!.connectTimeoutPeriod = 30;
    _client!.autoReconnect = true;

    try {
      await _client!.connect(username, password);
      _connectionController.add(_client!.connectionStatus!.state);
      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        await _subscribe();
      }
    } catch (e) {
      _connectionController.add(MqttConnectionState.disconnected);
      rethrow;
    }
  }

  Future<void> _subscribe() async {
    _client!.subscribe(topicHelp, MqttQos.atLeastOnce);
    _client!.subscribe(topicSensor, MqttQos.atLeastOnce);
    _client!.updates!.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final payload = msg.payload as MqttPublishMessage;
      final payloadStr = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
      if (topic == topicHelp) {
        _handleHelp(payloadStr);
      } else if (topic == topicSensor) {
        _handleSensor(payloadStr);
      }
    }
  }

  void _handleHelp(String payload) {
    _helpController.add(payload);
    final record = AlertRecord(
      id: '${DateTime.now().millisecondsSinceEpoch}_help',
      type: 'help',
      message: payload,
      at: DateTime.now(),
    );
    _alerts.add(record);
    _notifications.showAlert(title: 'Help Alert', body: payload);
  }

  void _handleSensor(String payload) {
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>?;
      if (map == null) return;
      final data = SensorData.fromJson(map);
      _sensorController.add(data);
      final parts = <String>[];
      if (data.temp >= tempThreshold) {
        parts.add('Temperature ${data.temp.toStringAsFixed(1)}°C (above $tempThreshold°C)');
      }
      if (data.hum >= humThreshold) {
        parts.add('Humidity ${data.hum.toStringAsFixed(1)}% (above $humThreshold%)');
      }
      if (parts.isEmpty) return;
      final message = parts.join('. ');
      final now = DateTime.now();
      if (data.temp >= tempThreshold) {
        _alerts.add(AlertRecord(
          id: '${now.millisecondsSinceEpoch}_temp',
          type: 'temp',
          message: 'Temperature ${data.temp.toStringAsFixed(1)}°C (above $tempThreshold°C)',
          at: now,
        ));
      }
      if (data.hum >= humThreshold) {
        _alerts.add(AlertRecord(
          id: '${now.millisecondsSinceEpoch}_hum',
          type: 'hum',
          message: 'Humidity ${data.hum.toStringAsFixed(1)}% (above $humThreshold%)',
          at: now,
        ));
      }
      _notifications.showAlert(title: 'Sensor Alert', body: message);
    } catch (_) {
      _sensorController.add(null);
    }
  }

  Future<void> disconnect() async {
    _client?.disconnect();
    _client = null;
    _connectionController.add(MqttConnectionState.disconnected);
  }

  void dispose() {
    _sensorController.close();
    _helpController.close();
    _connectionController.close();
    disconnect();
  }
}
