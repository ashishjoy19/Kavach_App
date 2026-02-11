import 'package:flutter/material.dart';

import '../models/alert_record.dart';
import '../services/alert_repository.dart';

class AlertHistoryScreen extends StatefulWidget {
  final AlertRepository repository;

  const AlertHistoryScreen({super.key, required this.repository});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  int _hours = 24;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.repository.load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert history & frequency'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear history?'),
                  content: const Text(
                    'This will delete all stored alert records.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await widget.repository.clear();
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
      body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FrequencyCard(
                repository: widget.repository,
                hours: _hours,
                onHoursChanged: (h) => setState(() => _hours = h),
              ),
              const SizedBox(height: 16),
              _AlertList(
                records: widget.repository.recentAlerts(hours: _hours),
              ),
            ],
          ),
    );
  }
}

class _FrequencyCard extends StatelessWidget {
  final AlertRepository repository;
  final int hours;
  final ValueChanged<int> onHoursChanged;

  const _FrequencyCard({
    required this.repository,
    required this.hours,
    required this.onHoursChanged,
  });

  @override
  Widget build(BuildContext context) {
    final recent = repository.recentAlerts(hours: hours);
    final perHour = repository.alertsPerHour(hours: hours);
    final byType = repository.countByType(hours: hours);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert frequency',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1h')),
                ButtonSegment(value: 6, label: Text('6h')),
                ButtonSegment(value: 24, label: Text('24h')),
              ],
              selected: {hours},
              onSelectionChanged: (s) => onHoursChanged(s.first),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total alerts (last $hours h):', style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  '${recent.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Alerts per hour:', style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  perHour.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (byType.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              Text('By type', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              ...byType.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key),
                      Text('${e.value}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlertList extends StatelessWidget {
  final List<AlertRecord> records;

  const _AlertList({required this.records});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent alerts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              const Text('No alerts in this period.')
            else
              ...records.take(100).map((r) => _AlertTile(record: r)),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final AlertRecord record;

  const _AlertTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final typeColor = switch (record.type) {
      'help' => Colors.orange,
      'temp' => Colors.red,
      'hum' => Colors.blue,
      _ => Colors.grey,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: typeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.type.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: typeColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  _formatTime(record.at),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${at.day}/${at.month} ${at.hour}:${at.minute.toString().padLeft(2, '0')}';
  }
}
