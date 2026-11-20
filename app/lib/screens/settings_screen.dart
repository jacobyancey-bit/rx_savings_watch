import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  bool? _pingSuccess;

  @override
  void initState() {
    super.initState();
    final currentUrl = context.read<CabinetProvider>().serverUrl;
    _urlController = TextEditingController(text: currentUrl);
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _pingSuccess = null;
    });

    final api = ApiService(baseUrl: _urlController.text.trim());
    final success = await api.checkHealth();

    setState(() {
      _isTesting = false;
      _pingSuccess = success;
    });
  }

  void _saveUrl() {
    final url = _urlController.text.trim();
    context.read<CabinetProvider>().setServerUrl(url);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server URL updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Privacy'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Privacy Assurance Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.teal.shade800, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Zero-Tracking Privacy Guarantee',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your medication cabinet is stored strictly on this device. '
                  'When checking for generic updates, the app sends only anonymized drug concept IDs (RXCUIs). '
                  'No names, emails, IP addresses, or personal health identifiers are ever tracked, logged, or tied to your identity.',
                  style: TextStyle(fontSize: 12.5, color: Colors.teal.shade900, height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Backend Server Configuration',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Node.js 22 server endpoint providing official FDA, CMS NADAC, and RxNorm feeds.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Server Base URL',
              hintText: 'http://localhost:3000',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Test Connection'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saveUrl,
                child: const Text('Save URL'),
              ),
            ],
          ),

          if (_pingSuccess != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _pingSuccess! ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _pingSuccess! ? Colors.green.shade300 : Colors.red.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _pingSuccess! ? Icons.check_circle : Icons.error,
                    size: 16,
                    color: _pingSuccess! ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _pingSuccess!
                        ? 'Server is online and healthy!'
                        : 'Could not connect. Verify server is running.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _pingSuccess! ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
