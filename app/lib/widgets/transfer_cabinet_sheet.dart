import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/cabinet_provider.dart';
import '../services/cabinet_transfer_service.dart';

class TransferCabinetSheet extends StatefulWidget {
  const TransferCabinetSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const TransferCabinetSheet(),
    );
  }

  @override
  State<TransferCabinetSheet> createState() => _TransferCabinetSheetState();
}

class _TransferCabinetSheetState extends State<TransferCabinetSheet> {
  final TextEditingController _importController = TextEditingController();
  bool _isImporting = false;
  String? _importFeedback;
  bool _importSuccess = false;

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transfer link copied! Open it on your other device to import your cabinet.'),
      ),
    );
  }

  Future<void> _sendViaSms(String link, int count) async {
    final body = Uri.encodeComponent(
      'My Rx Savings Watch cabinet ($count medication${count == 1 ? '' : 's'}): $link',
    );
    final uri = Uri.parse('sms:?body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await _copyLink(link);
    }
  }

  Future<void> _sendViaEmail(String link, int count) async {
    final subject = Uri.encodeComponent('My Rx Savings Watch Medication Cabinet');
    final body = Uri.encodeComponent(
      'Open this private link on your phone or computer to transfer your $count watched medication${count == 1 ? '' : 's'}:\n\n$link\n\n'
      'Privacy note: Your medication list travels only inside the # fragment of this link and is never stored on any server.',
    );
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await _copyLink(link);
    }
  }

  Future<void> _handleImport() async {
    final raw = _importController.text.trim();
    final rxcuis = CabinetTransferService.parseRxcuisFromInput(raw);
    if (rxcuis.isEmpty) {
      setState(() {
        _importSuccess = false;
        _importFeedback = 'Paste a valid transfer link or RXW code from your other device.';
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _importFeedback = null;
    });

    try {
      final cabinet = context.read<CabinetProvider>();
      final addedCount = await cabinet.importRxcuis(rxcuis);
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _importSuccess = true;
        _importFeedback = addedCount > 0
            ? 'Imported $addedCount new medication${addedCount == 1 ? '' : 's'} to this device!'
            : 'All medications in that link are already in this device\'s cabinet.';
      });
      if (addedCount > 0) {
        _importController.clear();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _importSuccess = false;
        _importFeedback = 'Could not reach the server to verify those medications. Please check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cabinet = context.watch<CabinetProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rxcuis = cabinet.cabinet.map((d) => d.rxcui).toList();
    final hasItems = rxcuis.isNotEmpty;
    final transferLink = CabinetTransferService.buildTransferLink(rxcuis);

    return DraggableScrollableSheet(
      initialChildSize: hasItems ? 0.88 : 0.58,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Row(
                children: [
                  Icon(Icons.devices_outlined, color: theme.colorScheme.primary, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Transfer Cabinet Between Devices',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Zero-server privacy callout
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.teal.shade900.withValues(alpha: 0.35)
                      : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.teal.shade700 : Colors.teal.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Private zero-server transfer: Your medication codes travel only inside the # part of the link or QR code—never stored on our servers and never tied to an account.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: isDark ? Colors.teal.shade100 : Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (hasItems) ...[
                const SizedBox(height: 22),
                Text(
                  'Send to Your Phone or Computer (${rxcuis.length} medication${rxcuis.length == 1 ? '' : 's'})',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan this QR code with your phone camera, or tap a button below to send yourself the one-tap transfer link.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),

                // High-contrast white QR container so camera scanners work in Light & Dark mode
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: QrImageView(
                      data: transferLink,
                      version: QrVersions.auto,
                      size: 196,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF055A56),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _copyLink(transferLink),
                      icon: const Icon(Icons.link),
                      label: const Text('Copy Transfer Link'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _sendViaSms(transferLink, rxcuis.length),
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Text to Phone'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendViaEmail(transferLink, rxcuis.length),
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email Myself'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              Text(
                'Import From Another Device',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Paste a transfer link or RXW code copied from your computer or phone:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _importController,
                decoration: InputDecoration(
                  hintText: 'https://rx.dangling-dice-studios.com/#import=...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste_outlined),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && mounted) {
                        _importController.text = data!.text!.trim();
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isImporting ? null : _handleImport,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(
                    _isImporting ? 'Importing...' : 'Import Medications to This Device',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              if (_importFeedback != null) ...[
                const SizedBox(height: 12),
                Text(
                  _importFeedback!,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _importSuccess
                        ? (isDark ? Colors.teal.shade200 : Colors.teal.shade800)
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
