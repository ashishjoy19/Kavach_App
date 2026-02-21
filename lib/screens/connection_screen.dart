import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../services/broker_config_service.dart';
import '../services/mqtt_service.dart';
import 'dashboard_screen.dart';

class ConnectionScreen extends StatefulWidget {
  /// When false, do not try auto-connect (e.g. after user tapped Disconnect).
  final bool autoConnect;

  const ConnectionScreen({super.key, this.autoConnect = true});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _hostController = TextEditingController(text: 'broker.hivemq.com');
  final _portController = TextEditingController(text: '1883');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _connecting = false;
  bool _autoConnecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
    _tryAutoConnect();
  }

  Future<void> _loadSavedConfig() async {
    final config = await BrokerConfigService.load();
    if (config == null || !mounted) return;
    setState(() {
      _hostController.text = config.host;
      _portController.text = config.port.toString();
      _usernameController.text = config.username;
      _passwordController.text = config.password;
    });
  }

  Future<void> _tryAutoConnect() async {
    if (!widget.autoConnect) return;
    final config = await BrokerConfigService.load();
    if (config == null || !_autoConnecting) return;
    setState(() => _connecting = true);
    try {
      final mqtt = MqttService();
      await mqtt.connect(
        host: config.host,
        port: config.port,
        username: config.username.isEmpty ? 'kavach' : config.username,
        password: config.password.isEmpty ? 'kavach' : config.password,
      );
      if (!mounted) return;
      if (mqtt.connectionState == MqttConnectionState.connected) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(mqttService: mqtt),
          ),
        );
        return;
      }
    } catch (_) {
      // Stay on connection screen with pre-filled fields
    }
    if (mounted) setState(() => _connecting = false);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _connecting = true;
    });
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 1883;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (host.isEmpty) {
      setState(() {
        _error = 'Enter broker host';
        _connecting = false;
      });
      return;
    }

    try {
      final config = BrokerConfig(
        host: host,
        port: port,
        username: username,
        password: password,
      );
      await BrokerConfigService.save(config);

      final mqtt = MqttService();
      await mqtt.connect(
        host: host,
        port: port,
        username: username.isEmpty ? 'kavach' : username,
        password: password.isEmpty ? 'kavach' : password,
      );
      if (!mounted) return;
      if (mqtt.connectionState == MqttConnectionState.connected) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(mqttService: mqtt),
          ),
        );
      } else {
        setState(() {
          _error = 'Connection failed';
          _connecting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
        _connecting = false;
      });
    }
  }

  Future<void> _forgetBroker() async {
    await BrokerConfigService.clear();
    setState(() {
      _error = null;
      _hostController.text = 'broker.hivemq.com';
      _portController.text = '1883';
      _usernameController.text = '';
      _passwordController.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.wifi_find, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Kavach MQTT',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to your MQTT broker. Connection is saved and will auto-connect next time until you disconnect.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'On a real phone: use your broker\'s IP (e.g. 192.168.1.x) or broker.hivemq.com. '
                        'Do not use localhost or 10.0.2.2—those only work on the emulator. '
                        'Phone and PC must be on the same Wi‑Fi if the broker runs on your PC.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Broker host',
                  hintText: 'e.g. broker.hivemq.com or 192.168.1.5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.dns),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password (optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _connect(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _connecting ? null : _connect,
                icon: _connecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_connecting ? 'Connecting…' : 'Connect'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _connecting ? null : _forgetBroker,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Forget saved broker'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
