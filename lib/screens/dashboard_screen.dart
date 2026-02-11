import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';

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

class _DashboardScreenState extends State<DashboardScreen> {
  SensorData? _sensor;
  final List<String> _helpMessages = [];
  static const _maxHelpMessages = 50;

  @override
  void initState() {
    super.initState();
    widget.mqttService.sensorStream.listen((data) {
      if (mounted) setState(() => _sensor = data);
    });
    widget.mqttService.helpStream.listen((msg) {
      if (mounted) {
        setState(() {
          _helpMessages.insert(0, msg);
          if (_helpMessages.length > _maxHelpMessages) {
            _helpMessages.removeLast();
          }
        });
      }
    });
  }

  Future<void> _disconnect() async {
    await widget.mqttService.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kavach Dashboard'),
        actions: [
          StreamBuilder<MqttConnectionState>(
            stream: widget.mqttService.connectionStream,
            initialData: widget.mqttService.connectionState,
            builder: (_, snapshot) {
              final state = snapshot.data ?? MqttConnectionState.disconnected;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state == MqttConnectionState.connected
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 10,
                        color: state == MqttConnectionState.connected
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state == MqttConnectionState.connected
                            ? 'Connected'
                            : 'Disconnected',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlertHistoryScreen(
                    repository: widget.mqttService.alertRepository,
                  ),
                ),
              );
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
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SensorCard(sensor: _sensor, mqtt: widget.mqttService),
            const SizedBox(height: 16),
            _HelpCard(messages: _helpMessages),
          ],
        ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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

class _SensorCard extends StatelessWidget {
  final SensorData? sensor;
  final MqttService mqtt;

  const _SensorCard({this.sensor, required this.mqtt});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.thermostat, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Sensor (fabacademy/kavach/sensor)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (sensor == null)
              const Text('Waiting for data…')
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ValueChip(
                    label: 'Temperature',
                    value: '${sensor!.temp.toStringAsFixed(1)}°C',
                    threshold: mqtt.tempThreshold,
                    isOver: sensor!.temp >= mqtt.tempThreshold,
                  ),
                  _ValueChip(
                    label: 'Humidity',
                    value: '${sensor!.hum.toStringAsFixed(1)}%',
                    threshold: mqtt.humThreshold,
                    isOver: sensor!.hum >= mqtt.humThreshold,
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              'Thresholds: temp ≥ ${mqtt.tempThreshold}°C, hum ≥ ${mqtt.humThreshold}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final String value;
  final double threshold;
  final bool isOver;

  const _ValueChip({
    required this.label,
    required this.value,
    required this.threshold,
    required this.isOver,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isOver ? Colors.red.shade100 : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOver ? Colors.red : Theme.of(context).dividerColor,
            ),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isOver ? Colors.red.shade900 : null,
                ),
          ),
        ),
      ],
    );
  }
}

class _HelpCard extends StatelessWidget {
  final List<String> messages;

  const _HelpCard({required this.messages});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notification_important, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Help (fabacademy/kavach/help)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (messages.isEmpty)
              const Text('No help messages yet.')
            else
              ...messages.take(20).map((msg) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      msg,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
