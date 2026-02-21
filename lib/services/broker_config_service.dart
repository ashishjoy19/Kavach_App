import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists broker connection so we can auto-connect and reconnect.
class BrokerConfig {
  final String host;
  final int port;
  final String username;
  final String password;

  const BrokerConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };

  static BrokerConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final host = json['host'] as String?;
    if (host == null || host.isEmpty) return null;
    return BrokerConfig(
      host: host,
      port: (json['port'] as num?)?.toInt() ?? 1883,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }
}

class BrokerConfigService {
  static const _key = 'kavach_broker_config';

  static Future<BrokerConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>?;
      return BrokerConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(BrokerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
