import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/link.dart';
import '../config/partner_links.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/web_push_service.dart';
import '../widgets/legal_policy_sheet.dart';
import '../widgets/privacy_promise_sheet.dart';
import '../widgets/review_sheet.dart';
import '../widgets/transfer_cabinet_sheet.dart';

class SettingsScreen extends StatefulWidget {
  final bool embedded;

  const SettingsScreen({super.key, this.embedded = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  bool? _pingSuccess;
  String _webPushStatus = 'unsupported';
  bool _webPushBusy = false;

  @override
  void initState() {
    super.initState();
    final currentUrl = context.read<CabinetProvider>().serverUrl;
    _urlController = TextEditingController(text: currentUrl);
    if (kIsWeb) {
      WebPushService.getStatus().then((status) {
        if (mounted) setState(() => _webPushStatus = status);
      });
    }
  }

  Future<void> _toggleWebPush() async {
    setState(() => _webPushBusy = true);
    final cabinet = context.read<CabinetProvider>();
    final nextStatus = _webPushStatus == 'subscribed'
        ? await WebPushService.unsubscribe(cabinet.serverUrl)
        : await WebPushService.subscribe(cabinet.serverUrl);

    if (nextStatus == 'subscribed') {
      await WebPushService.syncWatchedRxcuis(cabinet.cabinet.map((d) => d.rxcui).toList());
    }

    if (mounted) {
      setState(() {
        _webPushStatus = nextStatus;
        _webPushBusy = false;
      });
      final msg = switch (nextStatus) {
        'subscribed' => 'Browser alerts enabled! Filtered privately on this device.',
        'unsubscribed' => 'Browser alerts turned off.',
        'denied' => 'Browser blocked notifications. Enable them in your browser address bar settings.',
        _ => 'Could not update browser alert status.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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

  Future<void> _sendTestNotification() async {
    if (kIsWeb) {
      final ok = await WebPushService.showLocalTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Test browser notification sent!'
                  : 'Please allow notifications in your browser to receive alerts.',
            ),
          ),
        );
      }
      return;
    }

    final notifs = NotificationService();
    await notifs.showGenericLaunchNotification(
      drugName: 'Vyvanse (Test)',
      genericName: 'lisdexamfetamine dimesylate',
      savingsPct: 93.0,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test notification dispatched to device')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cabinet = context.watch<CabinetProvider>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
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
                  'Your medication cabinet is stored strictly on this device (or in this browser on the web). '
                  'When checking for generic updates, the app sends the public drug codes (RxCUIs) in your cabinet plus a few decoy lookups. '
                  'No names, emails, accounts, or device IDs are sent, and Rx Savings Watch does not store IP addresses with your lookups.\n\n'
                  'Privacy Trade-Off: Because there is no account or cloud backup, your list stays saved when you close the app or browser, '
                  'but it will not sync between different devices, and uninstalling the app or clearing browser site data will erase it.',
                  style: TextStyle(fontSize: 13, color: Colors.teal.shade900, height: 1.45),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Display & Readability (Senior-Friendly Text Size)
          Text(
            'Text Size & Readability',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a comfortable reading size across the entire app.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment<double>(
                value: 1.0,
                label: Text('Standard'),
              ),
              ButtonSegment<double>(
                value: 1.18,
                label: Text('Large'),
              ),
              ButtonSegment<double>(
                value: 1.35,
                label: Text('Extra Large'),
              ),
            ],
            selected: {
              cabinet.textScale >= 1.3
                  ? 1.35
                  : cabinet.textScale >= 1.15
                      ? 1.18
                      : 1.0
            },
            onSelectionChanged: (selection) {
              cabinet.setTextScale(selection.first);
            },
          ),

          const SizedBox(height: 24),

          // Notification Preferences
          Text(
            'Notification Alerts',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Commercial Generic Launch Alerts'),
            subtitle: const Text('Notify when FDA approval + commercial market distribution are verified'),
            value: cabinet.allowLaunchNotifs,
            onChanged: (val) => cabinet.setAllowLaunchNotifs(val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('FDA Drug Shortage Warnings'),
            subtitle: const Text('Notify if a watched prescription enters an active supply shortage'),
            value: cabinet.allowShortageNotifs,
            onChanged: (val) => cabinet.setAllowShortageNotifs(val),
          ),
          const SizedBox(height: 8),
          if (kIsWeb && _webPushStatus != 'unsupported') ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _webPushStatus == 'subscribed'
                        ? 'Browser Push Alerts: ON'
                        : 'Get Automatic Browser Alerts (No Login)',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Get notified even when this tab is closed. Your medicine list stays only in this browser and filters alerts locally.',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _webPushBusy ? null : _toggleWebPush,
                      icon: Icon(
                        _webPushStatus == 'subscribed'
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_outlined,
                      ),
                      label: Text(
                        _webPushStatus == 'subscribed'
                            ? 'Turn Off Browser Alerts'
                            : 'Turn On Browser Alerts',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          OutlinedButton.icon(
            onPressed: _sendTestNotification,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(kIsWeb ? 'Send Test Browser Notification' : 'Send Test Alert Notification'),
          ),

          if (kDebugMode) ...[
            const SizedBox(height: 28),
            Text(
              'Backend Server Configuration (Debug Only)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Node.js 22 server endpoint providing public FDA, CMS NADAC, and RxNorm datasets.',
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
          const SizedBox(height: 28),

          // Reviews & Feedback (Private to support@danglingdicestudios.com)
          Text(
            'Reviews & Feedback',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.rate_review_outlined, color: Colors.teal.shade700),
              title: const Text('Leave a Review'),
              subtitle: const Text('Send private feedback directly to our team'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ReviewSheet.show(context),
            ),
          ),

          const SizedBox(height: 28),

          // Legal & Official Policies
          Text(
            'Legal & Official Policies',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.verified_user_outlined, color: Colors.teal.shade700),
                  title: const Text('Read Our Privacy Promise'),
                  subtitle: const Text('Quick summary right in this app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => PrivacyPromiseSheet.show(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => LegalPolicySheet.showPrivacyPolicy(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => LegalPolicySheet.showTermsOfService(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.medical_information_outlined),
                  title: const Text('Medical Disclaimer'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => LegalPolicySheet.showMedicalDisclaimer(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Government Data Sources & Disclaimer'),
                  subtitle: const Text('Not a government app • Official .gov source links'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => LegalPolicySheet.showGovernmentDataSources(context),
                ),
              ],
            ),
          ),

          // Quiet, Optional Tip Jar (Web-only to comply with Google Play Payments Policy on Android)
          if (kIsWeb) ...[
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.favorite_outline, color: Colors.teal.shade700, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Support Independent Software (Optional)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rx Savings Watch is 100% free, with no ad networks or trackers. If it helped lower your prescription costs and you would like to leave an optional tip for our independent studio, thank you!',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: Link(
                      uri: Uri.parse(PartnerLinks.tipJarUrl),
                      target: LinkTarget.blank,
                      builder: (context, followLink) => FilledButton.tonalIcon(
                        onPressed: followLink,
                        icon: const Icon(Icons.volunteer_activism_outlined),
                        label: const Text(
                          'Leave an Optional Tip',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          // One-Tap Data Control
          Text(
            'Your Device Data',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Your medicine list is stored only on this device. You can privately transfer it to your phone or computer with a QR code or link, or erase it anytime.',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              onPressed: () => TransferCabinetSheet.show(context),
              icon: const Icon(Icons.devices_outlined),
              label: const Text(
                'Transfer Cabinet Between Devices',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: cabinet.cabinet.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Erase Medication List?'),
                          content: Text(
                            kIsWeb
                                ? 'This will remove all saved medications from this browser. You can add them back anytime.'
                                : 'This will remove all saved medications from this phone. You can add them back anytime.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Erase All'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await cabinet.clearAllData();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                kIsWeb
                                    ? 'All saved medications erased from this browser.'
                                    : 'All saved medications erased from this phone.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              icon: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
              label: Text(
                'Erase My Medication List',
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
