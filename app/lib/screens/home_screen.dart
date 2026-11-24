import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cabinet_provider.dart';
import '../services/cabinet_transfer_service.dart';
import '../services/web_push_service.dart';
import '../widgets/add_supplement_sheet.dart';
import '../widgets/cabinet_switcher_sheet.dart';
import '../widgets/drug_card.dart';
import '../widgets/home_footer_section.dart';
import '../widgets/privacy_promise_sheet.dart';
import '../widgets/refill_setup_sheet.dart';
import '../widgets/reminder_sheet.dart';
import '../widgets/supplement_card.dart';
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
  int _desktopNavIndex = 0; // 0 = Cabinet, 1 = Search Catalog, 2 = Settings
  String? _pendingSearchQuery;

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

  Future<void> _handleSyncPressed(BuildContext context, CabinetProvider cabinet) async {
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
  }

  Future<void> _handleTextScalePressed(BuildContext context, CabinetProvider cabinet) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final cabinet = context.watch<CabinetProvider>();
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 960;

    if (isDesktop) {
      return _buildDesktopShell(context, cabinet, theme);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medication_liquid_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Rx Savings Watch',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _handleTextScalePressed(context, cabinet),
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
            onPressed: cabinet.isSyncing ? null : () => _handleSyncPressed(context, cabinet),
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
      body: _buildCabinetBody(context, cabinet, theme, isDesktop: false),
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

  Widget _buildDesktopShell(BuildContext context, CabinetProvider cabinet, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF151E1D) : const Color(0xFFFAFCFC);
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    Widget buildNavItem({
      required IconData icon,
      required IconData selectedIcon,
      required String label,
      required int index,
      String? badge,
    }) {
      final selected = _desktopNavIndex == index;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.45 : 0.75)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _desktopNavIndex = index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    size: 20,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                        color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget activePane;
    switch (_desktopNavIndex) {
      case 1:
        activePane = SearchScreen(
          key: ValueKey('search_${_pendingSearchQuery ?? ''}'),
          embedded: true,
          initialQuery: _pendingSearchQuery,
        );
        break;
      case 2:
        activePane = const SettingsScreen(embedded: true);
        break;
      default:
        activePane = _buildCabinetBody(context, cabinet, theme, isDesktop: true);
    }

    return Scaffold(
      body: Row(
        children: [
          // Persistent Left Navigation Sidebar
          Container(
            width: 268,
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 16, 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.medication_liquid_outlined, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Rx Savings Watch',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Official FDA • Zero PII',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Primary Navigation
                  buildNavItem(
                    icon: Icons.inventory_2_outlined,
                    selectedIcon: Icons.inventory_2,
                    label: 'Medication Cabinet',
                    index: 0,
                    badge: '${cabinet.cabinet.length}',
                  ),
                  buildNavItem(
                    icon: Icons.search_outlined,
                    selectedIcon: Icons.search,
                    label: 'Search FDA Catalog',
                    index: 1,
                  ),
                  buildNavItem(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: 'Settings & Privacy',
                    index: 2,
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),

                  // Caregiver Cabinets Switcher right in Sidebar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CABINETS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => CabinetSwitcherSheet.show(context),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('Manage', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final c in cabinet.cabinets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Material(
                              color: c.id == cabinet.activeCabinetId && _desktopNavIndex == 0
                                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  cabinet.switchCabinet(c.id);
                                  setState(() => _desktopNavIndex = 0);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Color(c.colorValue),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          c.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: c.id == cabinet.activeCabinetId
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${c.drugs.length}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),
                  // Quick Tools Footer in Sidebar
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => AddSupplementSheet.show(context),
                          icon: const Icon(Icons.spa_outlined, size: 17),
                          label: const Text('Add OTC / Supplement'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => TransferCabinetSheet.show(context),
                                icon: const Icon(Icons.devices_outlined, size: 16),
                                label: const Text('Transfer', style: TextStyle(fontSize: 12.5)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.outlined(
                              tooltip: 'Check for generic updates',
                              onPressed: cabinet.isSyncing ? null : () => _handleSyncPressed(context, cabinet),
                              icon: cabinet.isSyncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync, size: 18),
                            ),
                            const SizedBox(width: 4),
                            IconButton.outlined(
                              tooltip: 'Text size (${cabinet.textScaleLabel})',
                              onPressed: () => _handleTextScalePressed(context, cabinet),
                              icon: const Text('Aa', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Full-Width Main Content Canvas
          Expanded(
            child: activePane,
          ),
        ],
      ),
    );
  }

  Widget _buildCabinetBody(BuildContext context, CabinetProvider cabinet, ThemeData theme, {required bool isDesktop}) {
    if (cabinet.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
              onRefresh: () => cabinet.syncCabinet(),
              child: CustomScrollView(
                slivers: [
                  if (isDesktop)
                    // Clean desktop page header + 4 accurate KPI cards (with smart fallback)
                    SliverToBoxAdapter(
                      child: _buildDesktopHeader(context, cabinet, theme),
                    )
                  else ...[
                    // Overview stats hero banner (mobile)
                    SliverToBoxAdapter(
                      child: _buildHeroBanner(context, cabinet),
                    ),

                    // Persistent "No Personal Data Collected" trust indicator (mobile)
                    const SliverToBoxAdapter(
                      child: PrivacyTrustBanner(),
                    ),
                  ],

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

                  // Cabinet items header (mobile only — desktop already shows title & sidebar switcher)
                  if (!isDesktop)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => CabinetSwitcherSheet.show(context),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (cabinet.hasMultipleCabinets || !cabinet.activeCabinet.isDefault) ...[
                                            Container(
                                              width: 10,
                                              height: 10,
                                              margin: const EdgeInsets.only(right: 7),
                                              decoration: BoxDecoration(
                                                color: Color(cabinet.activeCabinet.colorValue),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                          Flexible(
                                            child: Text(
                                              '${cabinet.activeCabinet.headerTitle} (${cabinet.cabinet.length})',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 20,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      if (cabinet.lastChecked != null)
                                        Text(
                                          'Updated: ${cabinet.lastChecked!.split('T')[0]}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                    ],
                                  ),
                                ),
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

                  // Refill-Due → Compare Prices Action Banner (high-intent point-of-fill CTA)
                  if (cabinet.refillsDueCount > 0 && cabinet.nextRefillDue != null)
                    SliverToBoxAdapter(
                      child: _buildRefillDueBanner(context, cabinet, theme, isDesktop: isDesktop),
                    ),

                  // Empty State or Prescription + OTC/Supplement Lists
                  if (cabinet.cabinet.isEmpty && cabinet.supplements.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(context),
                    )
                  else ...[
                    if (cabinet.cabinet.isNotEmpty)
                      ...() {
                        final useTwoColumns = isDesktop && MediaQuery.sizeOf(context).width >= 1100;

                        Widget buildCard(int index) {
                          final drug = cabinet.cabinet[index];
                          return DrugCard(
                            drug: drug,
                            reminder: cabinet.reminderFor(drug.rxcui),
                            onReminderTap: () => ReminderSheet.show(context, drug),
                            onToggleTaken: () => cabinet.toggleTakenToday(drug.rxcui),
                            refill: cabinet.refillFor(drug.rxcui),
                            onRefillTap: () => RefillSetupSheet.show(context, drug),
                            onMarkRefilled: () async {
                              await cabinet.markRefilledToday(drug.rxcui);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${drug.displayName} marked refilled today'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
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
                        }

                        if (!useTwoColumns) {
                          return <Widget>[
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => buildCard(index),
                                childCount: cabinet.cabinet.length,
                              ),
                            ),
                          ];
                        }

                        final rowCount = (cabinet.cabinet.length / 2).ceil();
                        return <Widget>[
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, rowIndex) {
                                  final leftIdx = rowIndex * 2;
                                  final rightIdx = leftIdx + 1;
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: buildCard(leftIdx)),
                                      Expanded(
                                        child: rightIdx < cabinet.cabinet.length
                                            ? buildCard(rightIdx)
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  );
                                },
                                childCount: rowCount,
                              ),
                            ),
                          ),
                        ];
                      }(),

                    // Clean, separated OTC & Supplements section (hidden until used)
                    if (cabinet.supplements.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.spa_outlined, size: 18, color: Colors.teal.shade700),
                                  const SizedBox(width: 6),
                                  Text(
                                    'OTC & Supplements (${cabinet.supplements.length})',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                onPressed: () => AddSupplementSheet.show(context),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final supp = cabinet.supplements[index];
                            return SupplementCard(
                              supplement: supp,
                              reminder: cabinet.reminderFor(supp.id),
                              onReminderTap: () => ReminderSheet.show(
                                context,
                                supp.toReminderDrug(),
                                dosage: supp.dosage,
                              ),
                              onToggleTaken: () => cabinet.toggleTakenToday(supp.id),
                              onRemove: () {
                                cabinet.removeSupplement(supp.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Removed ${supp.name}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            );
                          },
                          childCount: cabinet.supplements.length,
                        ),
                      ),
                    ],
                  ],

                  // FAQs, Contact Info & Important Disclaimers
                  const SliverToBoxAdapter(
                    child: HomeFooterSection(),
                  ),
                ],
              ),
            );
  }

  Widget _buildDesktopHeader(BuildContext context, CabinetProvider cabinet, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.7);
    final cardBg = isDark ? const Color(0xFF1A2423) : Colors.white;

    final totalRx = cabinet.cabinet.length;
    final totalOtc = cabinet.supplements.length;
    final genericCount = cabinet.genericLaunchedCount;
    final brandOnlyCount = (totalRx - genericCount).clamp(0, totalRx);
    final refillsDue = cabinet.refillsDueCount;
    final refillsTracked = cabinet.refillsTrackedCount;
    final nextRefill = cabinet.nextRefillDue;

    // Smart Fallback 4th KPI Card:
    // 1. Active FDA Shortages (highest urgency)
    // 2. Today's Doses (if daily reminders are configured)
    // 3. Est. Generic Cost Gap (NADAC acquisition spread)
    final String fourthLabel;
    final String fourthValue;
    final String fourthSub;
    final IconData fourthIcon;
    final Color fourthAccent;

    if (cabinet.shortageCount > 0) {
      fourthLabel = 'FDA SHORTAGES';
      fourthValue = '${cabinet.shortageCount} Active';
      fourthSub = 'Supply alert in cabinet';
      fourthIcon = Icons.warning_amber_rounded;
      fourthAccent = Colors.orange.shade700;
    } else if (cabinet.enabledRemindersCount > 0) {
      final taken = cabinet.takenTodayCount;
      final totalRem = cabinet.enabledRemindersCount;
      fourthLabel = "TODAY'S DOSES";
      fourthValue = '$taken of $totalRem';
      fourthSub = taken == totalRem ? 'All scheduled doses taken' : 'Doses marked taken today';
      fourthIcon = Icons.check_circle_outline_rounded;
      fourthAccent = taken == totalRem ? Colors.green.shade600 : Colors.teal.shade600;
    } else {
      fourthLabel = 'EST. GENERIC GAP';
      fourthValue = cabinet.maxSavingsAvailable > 0
          ? 'Up to ${cabinet.maxSavingsAvailable.toStringAsFixed(0)}%'
          : '—';
      fourthSub = 'NADAC brand vs. generic gap';
      fourthIcon = Icons.savings_outlined;
      fourthAccent = Colors.teal.shade700;
    }

    // Refills Due 3rd KPI Card
    final String refillValue;
    final String refillSub;
    final Color refillAccent;
    final IconData refillIcon;

    if (refillsDue > 0) {
      refillValue = '$refillsDue Due';
      refillSub = nextRefill != null
          ? '${nextRefill.drugName} • ${nextRefill.statusLabel()}'
          : 'Refill window open';
      refillAccent = Colors.amber.shade800;
      refillIcon = Icons.schedule_rounded;
    } else if (refillsTracked > 0) {
      refillValue = 'All Stocked';
      refillSub = nextRefill != null
          ? 'Next: ${nextRefill.drugName} (${nextRefill.nextRefillFormatted})'
          : '$refillsTracked prescriptions tracked';
      refillAccent = Colors.indigo.shade600;
      refillIcon = Icons.event_repeat_rounded;
    } else {
      refillValue = 'Not Set';
      refillSub = 'Tap Track Refill on any Rx';
      refillAccent = theme.colorScheme.onSurfaceVariant;
      refillIcon = Icons.event_repeat_rounded;
    }

    Widget buildKpiCard({
      required String label,
      required String value,
      required String sublabel,
      required IconData icon,
      required Color accent,
      bool highlight = false,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: highlight
                ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
                : cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlight ? accent.withValues(alpha: 0.45) : borderColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: highlight ? accent : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sublabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top compact title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (cabinet.hasMultipleCabinets || !cabinet.activeCabinet.isDefault) ...[
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 9),
                            decoration: BoxDecoration(
                              color: Color(cabinet.activeCabinet.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        Flexible(
                          child: Text(
                            cabinet.activeCabinet.headerTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => PrivacyPromiseSheet.show(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 14,
                                color: Colors.teal.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Stored locally • Zero tracking',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (cabinet.lastChecked != null)
                          Text(
                            '• FDA/NADAC synced ${cabinet.lastChecked!.split('T')[0]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => setState(() => _desktopNavIndex = 1),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Medication'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 4-card honest KPI strip
          Row(
            children: [
              buildKpiCard(
                label: 'WATCHED MEDS',
                value: '$totalRx Rx',
                sublabel: totalOtc > 0
                    ? '+ $totalOtc OTC / supplement'
                    : 'In this cabinet',
                icon: Icons.medication_outlined,
                accent: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              buildKpiCard(
                label: 'GENERICS AVAILABLE',
                value: totalRx == 0 ? '0' : '$genericCount of $totalRx',
                sublabel: brandOnlyCount > 0
                    ? '$brandOnlyCount brand-only watch'
                    : 'FDA commercial generics',
                icon: Icons.check_circle_outline,
                accent: Colors.green.shade700,
              ),
              const SizedBox(width: 12),
              buildKpiCard(
                label: 'REFILLS DUE',
                value: refillValue,
                sublabel: refillSub,
                icon: refillIcon,
                accent: refillAccent,
                highlight: refillsDue > 0,
              ),
              const SizedBox(width: 12),
              buildKpiCard(
                label: fourthLabel,
                value: fourthValue,
                sublabel: fourthSub,
                icon: fourthIcon,
                accent: fourthAccent,
                highlight: cabinet.shortageCount > 0,
              ),
            ],
          ),
        ],
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

  Widget _buildRefillDueBanner(
    BuildContext context,
    CabinetProvider cabinet,
    ThemeData theme, {
    required bool isDesktop,
  }) {
    final next = cabinet.nextRefillDue!;
    final isDark = theme.brightness == Brightness.dark;
    final matchingDrug = cabinet.cabinet.where((d) => d.rxcui == next.rxcui).toList();
    final extraCount = cabinet.refillsDueCount - 1;
    final extraText = extraCount > 0 ? ' (+$extraCount more due)' : '';

    return Container(
      margin: EdgeInsets.fromLTRB(isDesktop ? 24 : 16, 4, isDesktop ? 24 : 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.amber.withValues(alpha: 0.16) : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.amber.shade400.withValues(alpha: 0.5) : Colors.amber.shade400,
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_rounded,
                color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                size: 22,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${next.drugName} — ${next.statusLabel()}$extraText',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.amber.shade100 : Colors.amber.shade900,
                      ),
                    ),
                    Text(
                      next.needsDoctorRenewal
                          ? '0 refills remaining — contact your prescriber to renew'
                          : 'Compare local cash prices & free coupons before filling',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (matchingDrug.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DrugDetailScreen(drug: matchingDrug.first),
                      ),
                    );
                  },
                  icon: const Icon(Icons.local_offer_outlined, size: 16),
                  label: const Text('Compare Prices'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  await cabinet.markRefilledToday(next.rxcui);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${next.drugName} marked refilled today'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Mark Refilled'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    void openSearch([String? preset]) {
      if (MediaQuery.sizeOf(context).width >= 960) {
        setState(() {
          _pendingSearchQuery = preset;
          _desktopNavIndex = 1;
        });
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: preset)),
        );
      }
    }

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
              'Add your prescriptions to watch for FDA-approved generics, compare cash & coupon prices, and track refills.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => openSearch(),
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Medication'),
            ),
            const SizedBox(height: 20),
            Text(
              'Or try a popular prescription:',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final sample in const ['Lipitor', 'Eliquis', 'Metformin', 'Ozempic'])
                  ActionChip(
                    avatar: const Icon(Icons.search, size: 16),
                    label: Text(sample),
                    onPressed: () => openSearch(sample),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
