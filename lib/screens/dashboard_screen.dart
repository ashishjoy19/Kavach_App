import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:vibration/vibration.dart';

import '../models/alert_record.dart';
import '../models/sensor_data.dart';
import '../services/mqtt_service.dart';
import 'alert_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  final MqttService mqttService;

  const DashboardScreen({super.key, required this.mqttService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  SensorData? _sensor;
  DateTime? _sensorLastUpdated;
  AlertRecord? _activeAlert;
  final Set<String> _acknowledgedIds = {};
  List<AlertRecord> _alertHistory = [];
  StreamSubscription<AlertRecord>? _emergencySub;
  StreamSubscription<SensorData?>? _sensorSub;
  StreamSubscription<MqttConnectionState>? _connectionSub;

  late AnimationController _pulseController;
  late AnimationController _flashController;

  static const _kEmergencyRed = Color(0xFFef4444);
  static const _kSafeGreen = Color(0xFF22c55e);
  static const _kDarkNavy = Color(0xFF0f172a);
  static const _kCardDark = Color(0xFF1e293b);
  static const _kAccentCyan = Color(0xFF06b6d4);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadAlertHistory();
    _connectionSub = widget.mqttService.connectionStream.listen((_) => _refreshConnection());
    _sensorSub = widget.mqttService.sensorStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _sensor = data;
        if (data != null) _sensorLastUpdated = DateTime.now();
      });
    });
    _emergencySub = widget.mqttService.emergencyStream.listen((record) async {
      if (!mounted) return;
      _triggerVibration();
      setState(() => _activeAlert = record);
      await _loadAlertHistory();
    });
  }

  Future<void> _loadAlertHistory() async {
    await widget.mqttService.alertRepository.load();
    if (mounted) setState(() => _alertHistory = widget.mqttService.alertRepository.records);
  }

  void _refreshConnection() {
    if (mounted) setState(() {});
  }

  Future<void> _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 400);
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flashController.dispose();
    _emergencySub?.cancel();
    _sensorSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  void _acknowledgeAlert() {
    if (_activeAlert == null) return;
    _triggerVibration();
    _flashController.stop();
    setState(() {
      _acknowledgedIds.add(_activeAlert!.id);
      _activeAlert = null;
    });
    _loadAlertHistory();
  }

  Future<void> _disconnect() async {
    await widget.mqttService.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.mqttService.connectionState == MqttConnectionState.connected;
    final connecting = widget.mqttService.connectionState == MqttConnectionState.connecting;

    return Scaffold(
      backgroundColor: _kDarkNavy,
      appBar: AppBar(
        title: const Text('Kavach', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlertHistoryScreen(repository: widget.mqttService.alertRepository),
                ),
              );
              _loadAlertHistory();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'disconnect') _disconnect();
              if (v == 'thresholds') _showThresholds(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'thresholds', child: Text('Set thresholds')),
              const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionStatusBar(connected: connected, connecting: connecting),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAlertHistory,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _EmergencySection(
                    activeAlert: _activeAlert,
                    onAcknowledge: _acknowledgeAlert,
                    flashController: _flashController,
                  ),
                  const SizedBox(height: 20),
                  _SensorSection(
                    sensor: _sensor,
                    lastUpdated: _sensorLastUpdated,
                    mqtt: widget.mqttService,
                    pulseController: _pulseController,
                  ),
                  const SizedBox(height: 20),
                  _AlertHistorySection(
                    records: _alertHistory,
                    acknowledgedIds: _acknowledgedIds,
                    onRefresh: _loadAlertHistory,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showThresholds(BuildContext context) {
    final tempController = TextEditingController(
      text: widget.mqttService.tempThreshold.toString(),
    );
    final humController = TextEditingController(
      text: widget.mqttService.humThreshold.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardDark,
        title: const Text('Alert thresholds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tempController,
              decoration: const InputDecoration(
                labelText: 'Temperature threshold (°C)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: humController,
              decoration: const InputDecoration(
                labelText: 'Humidity threshold (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final temp = double.tryParse(tempController.text);
              final hum = double.tryParse(humController.text);
              if (temp != null) widget.mqttService.tempThreshold = temp;
              if (hum != null) widget.mqttService.humThreshold = hum;
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusBar extends StatelessWidget {
  final bool connected;
  final bool connecting;

  const _ConnectionStatusBar({required this.connected, required this.connecting});

  static const _kSafeGreen = Color(0xFF22c55e);
  static const _kRed = Color(0xFFef4444);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: connected ? _kSafeGreen.withOpacity( 0.2) : _kRed.withOpacity( 0.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: connected ? _kSafeGreen : _kRed,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (connected ? _kSafeGreen : _kRed).withOpacity( 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            connected ? 'MQTT Connected' : (connecting ? 'Reconnecting…' : 'Disconnected'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencySection extends StatelessWidget {
  final AlertRecord? activeAlert;
  final VoidCallback onAcknowledge;
  final AnimationController flashController;

  const _EmergencySection({
    required this.activeAlert,
    required this.onAcknowledge,
    required this.flashController,
  });

  static const _kEmergencyRed = Color(0xFFef4444);
  static const _kSafeGreen = Color(0xFF22c55e);

  @override
  Widget build(BuildContext context) {
    if (activeAlert != null) {
      return AnimatedSlide(
        offset: Offset.zero,
        duration: const Duration(milliseconds: 350),
        child: _ActiveEmergencyCard(
          record: activeAlert!,
          onAcknowledge: onAcknowledge,
          flashController: flashController,
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: _kSafeGreen.withOpacity( 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSafeGreen.withOpacity( 0.5)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: _kSafeGreen, size: 28),
          SizedBox(width: 12),
          Text(
            'No Active Emergencies',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: _kSafeGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveEmergencyCard extends StatefulWidget {
  final AlertRecord record;
  final VoidCallback onAcknowledge;
  final AnimationController flashController;

  const _ActiveEmergencyCard({
    required this.record,
    required this.onAcknowledge,
    required this.flashController,
  });

  @override
  State<_ActiveEmergencyCard> createState() => _ActiveEmergencyCardState();
}

class _ActiveEmergencyCardState extends State<_ActiveEmergencyCard> {
  static const _kEmergencyRed = Color(0xFFef4444);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.flashController,
      builder: (context, child) {
        final borderOpacity = 0.5 + (widget.flashController.value * 0.5);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: _kEmergencyRed,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _kEmergencyRed.withOpacity( 0.4),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity( borderOpacity),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '🚨 EMERGENCY ALERT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.record.message,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTime(widget.record.at),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity( 0.9),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: widget.onAcknowledge,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _kEmergencyRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Acknowledge', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
}

class _SensorSection extends StatelessWidget {
  final SensorData? sensor;
  final DateTime? lastUpdated;
  final MqttService mqtt;
  final AnimationController pulseController;

  const _SensorSection({
    required this.sensor,
    required this.lastUpdated,
    required this.mqtt,
    required this.pulseController,
  });

  static const _kCardDark = Color(0xFF1e293b);
  static const _kAccentCyan = Color(0xFF06b6d4);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SensorCard(
            icon: Icons.thermostat,
            value: sensor?.temp ?? null,
            unit: '°C',
            label: 'Live Temperature',
            lastUpdated: lastUpdated,
            pulseController: pulseController,
            threshold: mqtt.tempThreshold,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SensorCard(
            icon: Icons.water_drop,
            value: sensor?.hum ?? null,
            unit: '%',
            label: 'Live Humidity',
            lastUpdated: lastUpdated,
            pulseController: pulseController,
            threshold: mqtt.humThreshold,
          ),
        ),
      ],
    );
  }
}

class _SensorCard extends StatelessWidget {
  final IconData icon;
  final double? value;
  final String unit;
  final String label;
  final DateTime? lastUpdated;
  final AnimationController pulseController;
  final double threshold;

  const _SensorCard({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.lastUpdated,
    required this.pulseController,
    required this.threshold,
  });

  static const _kCardDark = Color(0xFF1e293b);
  static const _kAccentCyan = Color(0xFF06b6d4);
  static const _kEmergencyRed = Color(0xFFef4444);

  @override
  Widget build(BuildContext context) {
    final isOver = value != null && value! >= threshold;
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final scale = value != null ? 1.0 + (pulseController.value * 0.03) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCardDark,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (value != null ? _kAccentCyan : Colors.grey).withOpacity( 0.15),
                  blurRadius: value != null ? 12 : 0,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: isOver ? _kEmergencyRed : _kAccentCyan, size: 28),
                const SizedBox(height: 12),
                Text(
                  value != null ? '${value!.toStringAsFixed(1)}$unit' : '--',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isOver ? _kEmergencyRed : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity( 0.7),
                  ),
                ),
                if (lastUpdated != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Updated ${_formatAgo(lastUpdated!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity( 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatAgo(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

class _AlertHistorySection extends StatelessWidget {
  final List<AlertRecord> records;
  final Set<String> acknowledgedIds;
  final VoidCallback onRefresh;

  const _AlertHistorySection({
    required this.records,
    required this.acknowledgedIds,
    required this.onRefresh,
  });

  static const _kEmergencyRed = Color(0xFFef4444);
  static const _kCardDark = Color(0xFF1e293b);

  @override
  Widget build(BuildContext context) {
    final recent = records.take(15).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alert History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No alerts yet.',
              style: TextStyle(color: Colors.white.withOpacity( 0.6)),
            ),
          )
        else
          ...recent.map((r) => _AlertHistoryTile(
                record: r,
                acknowledged: acknowledgedIds.contains(r.id),
              )),
      ],
    );
  }
}

class _AlertHistoryTile extends StatelessWidget {
  final AlertRecord record;
  final bool acknowledged;

  const _AlertHistoryTile({required this.record, required this.acknowledged});

  static const _kEmergencyRed = Color(0xFFef4444);
  static const _kCardDark = Color(0xFF1e293b);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: _kCardDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: _kEmergencyRed, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EMERGENCY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kEmergencyRed.withOpacity( 0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  record.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(record.at),
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity( 0.5)),
                ),
                if (acknowledged)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Acknowledged',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade300,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
}
