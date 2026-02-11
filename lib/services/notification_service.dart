import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows local notifications for help and sensor-threshold alerts.
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
    const androidDetails = AndroidNotificationDetails(
      'kavach_alerts',
      'Kavach Alerts',
      channelDescription: 'Help and sensor threshold alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'kavach_alerts',
          'Kavach Alerts',
          importance: Importance.high,
        ));
  }

  void _onSelect(NotificationResponse response) {
    // Could navigate to alert detail if needed
  }

  Future<void> showAlert({required String title, required String body}) async {
    _id = (_id % 0x7FFFFFFF) + 1;
    const android = AndroidNotificationDetails(
      'kavach_alerts',
      'Kavach Alerts',
      channelDescription: 'Help and sensor threshold alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(_id, title, body, details);
  }
}
