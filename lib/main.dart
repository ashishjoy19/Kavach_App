import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/connection_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await NotificationService().init();
  await Permission.notification.request();
  runApp(const KavachApp());
}

class KavachApp extends StatelessWidget {
  const KavachApp({super.key});

  static const Color darkNavy = Color(0xFF0f172a);
  static const Color emergencyRed = Color(0xFFef4444);
  static const Color safeGreen = Color(0xFF22c55e);
  static const Color cardDark = Color(0xFF1e293b);
  static const Color accentCyan = Color(0xFF06b6d4);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kavach MQTT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkNavy,
        colorScheme: ColorScheme.dark(
          primary: accentCyan,
          secondary: accentCyan,
          surface: cardDark,
          error: emergencyRed,
          onPrimary: darkNavy,
          onSecondary: darkNavy,
          onSurface: Colors.white,
          onError: Colors.white,
          onSurfaceVariant: Colors.white70,
        ),
        cardTheme: CardTheme(
          color: cardDark,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkNavy,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
          headlineMedium: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          titleLarge: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          bodyLarge: TextStyle(fontSize: 16),
        ),
      ),
      home: const ConnectionScreen(),
    );
  }
}
