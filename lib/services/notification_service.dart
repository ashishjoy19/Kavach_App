import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows local notifications for emergency alerts.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  int _id = 0;

  NotificationService._();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onSelect,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'kavach_emergency',
          'Emergency Alerts',
          description: 'High priority emergency alerts with sound and vibration',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));
  }

  void _onSelect(NotificationResponse response) {
    // Tapping notification opens app (dashboard already open if in app)
  }

  /// Emergency alert: title "🚨 Emergency Alert", high priority, sound + vibration.
  Future<void> showEmergencyAlert({required String body}) async {
    _id = (_id % 0x7FFFFFFF) + 1;
    const android = AndroidNotificationDetails(
      'kavach_emergency',
      'Emergency Alerts',
      channelDescription: 'High priority emergency alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(_id, '🚨 Emergency Alert', body, details);
  }
}
