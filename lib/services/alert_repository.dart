import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';

/// Persists alert records and computes frequency (e.g. alerts per hour).
class AlertRepository {
  static const _keyAlerts = 'kavach_alert_records';
  static const _maxStored = 500;

  final List<AlertRecord> _records = [];
  List<AlertRecord> get records => List.unmodifiable(_records);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAlerts);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return;
      _records.clear();
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          _records.add(AlertRecord.fromJson(e));
        }
      }
    } catch (_) {}
  }

  Future<void> add(AlertRecord record) async {
    _records.insert(0, record);
    if (_records.length > _maxStored) _records.removeRange(_maxStored, _records.length);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _records.map((e) => e.toJson()).toList();
    await prefs.setString(_keyAlerts, jsonEncode(list));
  }

  /// Alerts in the last [hours] hours.
  List<AlertRecord> recentAlerts({int hours = 24}) {
    final since = DateTime.now().subtract(Duration(hours: hours));
    return _records.where((r) => r.at.isAfter(since)).toList();
  }

  /// Count by type in the last [hours] hours.
  Map<String, int> countByType({int hours = 24}) {
    final recent = recentAlerts(hours: hours);
    final map = <String, int>{};
    for (final r in recent) {
      map[r.type] = (map[r.type] ?? 0) + 1;
    }
    return map;
  }

  /// Alerts per hour (frequency) in the last [hours] window.
  double alertsPerHour({int hours = 24}) {
    final recent = recentAlerts(hours: hours);
    if (hours <= 0) return 0;
    return recent.length / hours;
  }

  Future<void> clear() async {
    _records.clear();
    await _save();
  }
}
