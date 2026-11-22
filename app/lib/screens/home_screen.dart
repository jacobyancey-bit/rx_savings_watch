import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cabinet_provider.dart';
import '../services/cabinet_transfer_service.dart';
import '../services/web_push_service.dart';
import '../widgets/drug_card.dart';
import '../widgets/home_footer_section.dart';
import '../widgets/privacy_promise_sheet.dart';
import '../widgets/reminder_sheet.dart';
import '../widgets/transfer_cabinet_sheet.dart';
import 'drug_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checkedIncomingTransfer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIncomingTransferLink());
  }

  Future<void> _checkIncomingTransferLink() async {
    if (_checkedIncomingTransfer || !kIsWeb || !mounted) return;
    _checkedIncomingTransfer = true;

    final capturedHash = WebPushService.consumePendingImportHash();
    final fragment = capturedHash.isNotEmpty ? capturedHash : Uri.base.fragment;
    if (fragment.isEmpty || !fragment.toLowerCase().contains('import=')) return;

    final rxcuis = CabinetTransferService.parseRxcuisFromInput(fragment);
    // Immediately scrub #import=... from browser address bar & history
    WebPushService.clearUrlHash();

    if (rxcuis.isEmpty || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Medication Cabinet?'),
        content: Text(
          'This private transfer link contains ${rxcuis.length} medication${rxcuis.length == 1 ? '' : 's'}. '
          'Add them to this device\'s local cabinet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final added = await context.read<CabinetProvider>().importRxcuis(rxcuis);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? 'Imported $added medication${added == 1 ? '' : 's'} to this device!'
                : 'Those medications are already in your cabinet.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not import medications right now. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cabinet = context.watch<CabinetProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medication_liquid_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('Rx Savings Watch', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await cabinet.cycleTextScale();
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Text size: ${cabinet.textScaleLabel}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Tooltip(
              message: 'Change text size (${cabinet.textScaleLabel})',
              child: const Text(
                'Aa',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: cabinet.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Check for generic updates',
            onPressed: cabinet.isSyncing
                ? null
                : () async {
                    if (cabinet.cabinet.isEmpty) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Add a medication to your cabinet first to check for updates.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    await cabinet.syncCabinet();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).clearSnackBars();
                    final msg = cabinet.syncError != null
                        ? 'Could not reach server. Showing cached data.'
                        : cabinet.lastNewAlertsCount > 0
                            ? 'Found ${cabinet.lastNewAlertsCount} new medication update(s)!'
                            : 'Cabinet checked — all ${cabinet.cabinet.length} medication${cabinet.cabinet.length == 1 ? '' : 's'} up to date!';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings & Privacy',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: cabinet.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => cabinet.syncCabinet(),
              child: CustomScrollView(
                slivers: [
                  // Overview stats hero banner
                  SliverToBoxAdapter(
                    child: _buildHeroBanner(context, cabinet),
                  ),

                  // Persistent "No Personal Data Collected" trust indicator
                  const SliverToBoxAdapter(
                    child: PrivacyTrustBanner(),
                  ),

                  // Graceful Offline Mode Banner
                  if (cabinet.syncError != null)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_outlined, color: Colors.amber.shade800, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Offline Mode — Displaying cached verification data. Pull to refresh when connection is restored.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Cabinet items header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My Medication Cabinet (${cabinet.cabinet.length})',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (cabinet.lastChecked != null)
                                  Text(
                                    'Updated: ${cabinet.lastChecked!.split('T')[0]}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => TransferCabinetSheet.show(context),
                            icon: const Icon(Icons.devices_outlined, size: 18),
                            label: const Text('Transfer'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Empty State or List
                  if (cabinet.cabinet.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(context),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final drug = cabinet.cabinet[index];
                          return DrugCard(
                            drug: drug,
                            reminder: cabinet.reminderFor(drug.rxcui),
                            onReminderTap: () => ReminderSheet.show(context, drug),
                            onToggleTaken: () => cabinet.toggleTakenToday(drug.rxcui),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DrugDetailScreen(drug: drug),
                                ),
                              );
                            },
                            onRemove: () {
                              cabinet.removeDrug(drug.rxcui);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed ${drug.displayName}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          );
                        },
                        childCount: cabinet.cabinet.length,
                      ),
                    ),

                  // FAQs, Contact Info & Important Disclaimers
                  const SliverToBoxAdapter(
                    child: HomeFooterSection(),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Medication'),
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context, CabinetProvider cabinet) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade800, Colors.teal.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GENERIC LAUNCH MONITOR',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Watched', '${cabinet.cabinet.length}', Icons.medication),
              _buildStatItem('Launched', '${cabinet.genericLaunchedCount}', Icons.rocket_launch, color: Colors.greenAccent),
              _buildStatItem('Max Savings', cabinet.maxSavingsAvailable > 0 ? '~${cabinet.maxSavingsAvailable.toStringAsFixed(0)}%' : 'N/A', Icons.savings, color: Colors.amberAccent),
              _buildStatItem('Shortages', '${cabinet.shortageCount}', Icons.warning_amber, color: cabinet.shortageCount > 0 ? Colors.orangeAccent : Colors.white70),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.white),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Your Cabinet is Empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your prescriptions to watch for commercial generic launches, acquisition savings, and supply shortages.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Medication'),
            ),
          ],
        ),
      ),
    );
  }
}
