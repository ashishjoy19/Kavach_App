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
  /// Alternate topic names some brokers use
  static const topicSensorAlt = 'fabacademy/kavach/sensors';
  /// Gas sensor topic — alerts when gas leakage is detected (payload: device, gas, state)
  static const topicGas = 'fabacademy/kavach/gas';
  /// Intruder/motion topic — alerts when motion is detected (payload: "motion" or JSON with message/state)
  static const topicIntrude = 'fabacademy/kavach/intrude';
  /// Dedicated status/heartbeat topic — ESP32 can publish here periodically or use LWT for "offline"
  static const topicStatus = 'fabacademy/kavach/status';
  /// App → ESP: request "are you there?" (ESP must subscribe and reply on topicPong)
  static const topicPing = 'fabacademy/kavach/ping';
  /// ESP → App: response to ping (app subscribes; receiving here = device online)
  static const topicPong = 'fabacademy/kavach/pong';

  double tempThreshold = 35.0;
  double humThreshold = 80.0;

  final StreamController<SensorData?> _sensorController = StreamController<SensorData?>.broadcast();
  Stream<SensorData?> get sensorStream => _sensorController.stream;

  final StreamController<String> _helpController = StreamController<String>.broadcast();
  Stream<String> get helpStream => _helpController.stream;

  final StreamController<MqttConnectionState> _connectionController =
      StreamController<MqttConnectionState>.broadcast();
  Stream<MqttConnectionState> get connectionStream => _connectionController.stream;

  final StreamController<AlertRecord> _emergencyController = StreamController<AlertRecord>.broadcast();
  Stream<AlertRecord> get emergencyStream => _emergencyController.stream;

  MqttConnectionState get connectionState => _client?.connectionStatus?.state ?? MqttConnectionState.disconnected;
  AlertRepository get alertRepository => _alerts;

  /// Last time we received any "device is alive" signal (sensor data or status/heartbeat).
  DateTime? _lastDeviceSeenAt;
  /// Set to true when we receive explicit "offline" (e.g. LWT from broker when ESP32 disconnects).
  bool _deviceOfflineExplicit = false;
  DateTime? get lastDeviceMessageAt => _lastDeviceSeenAt;
  static const _deviceOfflineAfter = Duration(minutes: 2);
  bool get isDeviceOnline =>
      !_deviceOfflineExplicit &&
      _lastDeviceSeenAt != null &&
      DateTime.now().difference(_lastDeviceSeenAt!) < _deviceOfflineAfter;

  Future<void> connect({
    required String host,
    int port = 1883,
    required String username,
    required String password,
    String? clientId,
  }) async {
    await disconnect();
    _deviceOfflineExplicit = false;
    // Unique client ID per device so phone and emulator can both connect and receive data
    final id = clientId ?? 'kavach_${DateTime.now().millisecondsSinceEpoch}_${identityHashCode(this)}';
    _client = MqttServerClient.withPort(host, id, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 60;
    _client!.connectTimeoutPeriod = 30;
    _client!.autoReconnect = true;

    try {
      await _client!.connect(username, password);
      _connectionController.add(_client!.connectionStatus!.state);
      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        await _subscribe();
        sendPing();
      }
    } catch (e) {
      _connectionController.add(MqttConnectionState.disconnected);
      rethrow;
    }
  }

  Future<void> _subscribe() async {
    _client!.subscribe(topicHelp, MqttQos.atLeastOnce);
    _client!.subscribe(topicSensor, MqttQos.atLeastOnce);
    _client!.subscribe(topicSensorAlt, MqttQos.atLeastOnce);
    _client!.subscribe('$topicSensor/#', MqttQos.atLeastOnce);
    _client!.subscribe(topicStatus, MqttQos.atLeastOnce);
    _client!.subscribe(topicPong, MqttQos.atLeastOnce);
    _client!.subscribe(topicGas, MqttQos.atLeastOnce);
    _client!.subscribe(topicIntrude, MqttQos.atLeastOnce);
    _client!.updates!.listen(_onMessage);
  }

  bool _isSensorTopic(String topic) {
    return topic == topicSensor ||
        topic == topicSensorAlt ||
        topic.startsWith('$topicSensor/');
  }

  void _markDeviceSeen() {
    _lastDeviceSeenAt = DateTime.now();
    _deviceOfflineExplicit = false;
    _deviceOnlineController.add(true);
  }

  void _markDeviceOffline() {
    _deviceOfflineExplicit = true;
    _deviceOnlineController.add(false);
  }

  /// Returns true if payload indicates explicit "offline" (e.g. LWT message).
  bool _isOfflinePayload(String payload) {
    final lower = payload.trim().toLowerCase();
    if (lower == 'offline' || lower == '0' || lower == 'false') return true;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>?;
      if (map == null) return false;
      final status = (map['status'] as String?)?.toLowerCase();
      final online = map['online'];
      if (status == 'offline') return true;
      if (online == false) return true;
    } catch (_) {}
    return false;
  }

  final StreamController<bool> _deviceOnlineController = StreamController<bool>.broadcast();
  Stream<bool> get deviceOnlineStream => _deviceOnlineController.stream;

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final payload = msg.payload as MqttPublishMessage;
      final bytes = payload.payload.message;
      final payloadStr = _payloadToString(bytes);
      if (topic == topicHelp) {
        _markDeviceSeen();
        _handleHelp(payloadStr);
      } else if (topic == topicStatus) {
        if (_isOfflinePayload(payloadStr)) {
          _markDeviceOffline();
        } else {
          _markDeviceSeen();
        }
      } else if (topic == topicPong) {
        _markDeviceSeen();
      } else if (_isSensorTopic(topic)) {
        _markDeviceSeen();
        _handleSensor(payloadStr);
      } else if (topic == topicGas) {
        _markDeviceSeen();
        _handleGas(payloadStr);
      } else if (topic == topicIntrude) {
        _markDeviceSeen();
        _handleIntrude(payloadStr);
      }
    }
  }

  void _handleIntrude(String payload) {
    final trimmed = payload.trim().toLowerCase();
    bool isMotion = trimmed == 'motion';
    if (!isMotion) {
      try {
        final map = jsonDecode(payload) as Map<String, dynamic>?;
        if (map != null) {
          final msg = (map['message'] as String?)?.trim().toLowerCase();
          final state = (map['state'] as String?)?.trim().toLowerCase();
          isMotion = msg == 'motion' || state == 'motion' || map['motion'] == true;
        }
      } catch (_) {}
    }
    if (!isMotion) return;
    const message = 'Motion detected. Possible intruder.';
    final record = AlertRecord(
      id: '${DateTime.now().millisecondsSinceEpoch}_intrude',
      type: 'intrude',
      message: message,
      at: DateTime.now(),
    );
    _alerts.add(record);
    _emergencyController.add(record);
    _notifications.showEmergencyAlert(body: message);
  }

  void _handleGas(String payload) {
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>?;
      if (map == null) return;
      final device = map['device'] as String?;
      final state = map['state'] as String?;
      final gas = (map['gas'] is num) ? (map['gas'] as num).toInt() : null;
      final isLeak = state == 'LEAK' || (gas != null && gas >= 80);
      final isGasDevice = device == null || device == 'gas_sensor';
      if (!isLeak || !isGasDevice) return;
      final level = gas ?? 99;
      final message = 'Gas leakage detected in kitchen (level: $level)';
      final record = AlertRecord(
        id: '${DateTime.now().millisecondsSinceEpoch}_gas',
        type: 'gas',
        message: message,
        at: DateTime.now(),
      );
      _alerts.add(record);
      _emergencyController.add(record);
      _notifications.showEmergencyAlert(body: message);
    } catch (_) {}
  }

  /// Send a ping to the ESP box. If the ESP subscribes to [topicPing] and publishes
  /// a response on [topicPong], the app will mark the device as online when it receives it.
  void sendPing() {
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String('ping');
    if (builder.payload != null) {
      _client!.publishMessage(topicPing, MqttQos.atLeastOnce, builder.payload!);
    }
  }

  /// Decode payload as UTF-8 so behavior is identical on emulator and physical devices.
  static String _payloadToString(dynamic bytes) {
    if (bytes == null) return '';
    try {
      if (bytes is List<int>) return utf8.decode(bytes);
      return MqttPublishPayload.bytesToStringAsString(bytes);
    } catch (_) {
      return MqttPublishPayload.bytesToStringAsString(bytes);
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
    _emergencyController.add(record);
    _notifications.showEmergencyAlert(body: payload);
  }

  void _handleSensor(String payload) {
    try {
      final decoded = jsonDecode(payload);
      Map<String, dynamic>? map;
      if (decoded is Map<String, dynamic>) {
        map = decoded;
      } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
        map = decoded.first as Map<String, dynamic>;
      }
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
      _notifications.showEmergencyAlert(body: message);
      final recordForStream = AlertRecord(
        id: '${now.millisecondsSinceEpoch}_sensor',
        type: data.temp >= tempThreshold ? 'temp' : 'hum',
        message: message,
        at: now,
      );
      _emergencyController.add(recordForStream);
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
    _emergencyController.close();
    _deviceOnlineController.close();
    disconnect();
  }
}
