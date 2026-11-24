import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/link.dart';
import '../models/drug.dart';
import '../models/refill_info.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';
import '../widgets/doctor_handout_sheet.dart';
import '../widgets/refill_setup_sheet.dart';
import '../widgets/reminder_sheet.dart';

class DrugDetailScreen extends StatefulWidget {
  final Drug drug;
  final String? initialStrength;
  final List<Map<String, dynamic>>? initialPartners;

  const DrugDetailScreen({
    super.key,
    required this.drug,
    this.initialStrength,
    this.initialPartners,
  });

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  final TextEditingController _copayController = TextEditingController(text: '60');
  final TextEditingController _zipController = TextEditingController();
  double _monthlyBrandCopay = 60.0;
  final double _monthlyGenericCopay = 10.0;
  late Drug _drug;
  bool _isRefreshingDetails = false;
  bool _isLoadingPartners = false;
  String? _selectedStrength;
  String? _selectedRouteGroup;
  List<Map<String, dynamic>> _verifiedPartners = const [];
  Map<String, dynamic>? _discountCard;
  Map<String, dynamic>? _brandAssistance;

  String? _matchBestStrength(List<String> strengths, String? target) {
    if (strengths.isEmpty) return target;
    if (target == null || target.trim().isEmpty) return strengths.first;

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final targetNorm = norm(target);

    for (final s in strengths) {
      if (norm(s) == targetNorm) return s;
    }
    for (final s in strengths) {
      if (norm(s).startsWith(targetNorm) || targetNorm.startsWith(norm(s))) {
        return s;
      }
    }
    // Match by numeric value alone (e.g., scanned "40 mg" vs "40 mg/1")
    final numMatch = RegExp(r'\d+(?:\.\d+)?').firstMatch(target);
    if (numMatch != null) {
      final numStr = numMatch.group(0)!;
      for (final s in strengths) {
        if (RegExp('\\b${RegExp.escape(numStr)}\\b').hasMatch(s)) return s;
      }
    }
    return strengths.first;
  }

  /// Filters FDA shortage entries strictly to the currently selected dosage strength.
  /// If a shortage entry specifies a strength (e.g., "25 mg • Capsule, Extended Release"),
  /// it will ONLY display when the user has that exact strength selected.
  List<Map<String, dynamic>> _shortagesForSelectedStrength(Drug drug) {
    if (!drug.hasActiveShortage || drug.activeShortageDetails.isEmpty) {
      return const [];
    }
    final selected = _selectedStrength?.trim().toLowerCase();
    if (selected == null || selected.isEmpty) {
      return drug.activeShortageDetails;
    }

    final strengthPattern = RegExp(r'\b(\d+(?:\.\d+)?)\s*(mg|mcg|ml|g|%)\b', caseSensitive: false);
    final selectedMatch = strengthPattern.firstMatch(selected);
    final selectedNorm = selectedMatch != null
        ? '${selectedMatch.group(1)} ${selectedMatch.group(2)!.toLowerCase()}'
        : selected;

    return drug.activeShortageDetails.where((s) {
      final formStr = (s['dosage_form'] ?? '').toString().toLowerCase();
      final formMatch = strengthPattern.firstMatch(formStr);
      // If FDA did not specify a particular strength on this shortage record, show it
      if (formMatch == null) return true;
      final formNorm = '${formMatch.group(1)} ${formMatch.group(2)!.toLowerCase()}';
      return formNorm == selectedNorm;
    }).toList();
  }

  String? _routeForStrength(Drug drug, String? strength) {
    final groups = drug.groupedStrengthsByRoute;
    if (groups.isEmpty) return null;
    if (strength != null) {
      for (final entry in groups.entries) {
        if (entry.value.contains(strength)) return entry.key;
      }
    }
    return groups.keys.first;
  }

  String? get _selectedDosageSummary {
    final s = _selectedStrength?.trim();
    if (s == null || s.isEmpty) return null;
    final groups = _drug.groupedStrengthsByRoute;
    if (groups.length > 1 && _selectedRouteGroup != null) {
      return '$s • $_selectedRouteGroup';
    }
    return s;
  }

  IconData _iconForRouteGroup(String routeGroup) {
    final lower = routeGroup.toLowerCase();
    if (lower.contains('inject')) return Icons.vaccines_outlined;
    if (lower.contains('solution') || lower.contains('liquid')) return Icons.water_drop_outlined;
    if (lower.contains('topical') || lower.contains('patch')) return Icons.spa_outlined;
    if (lower.contains('inhal') || lower.contains('spray')) return Icons.air_outlined;
    if (lower.contains('eye') || lower.contains('ear')) return Icons.visibility_outlined;
    return Icons.medication_outlined;
  }

  @override
  void initState() {
    super.initState();
    _drug = widget.drug;
    final strengths = _drug.availableStrengths;
    if (strengths.isNotEmpty) {
      _selectedStrength = _matchBestStrength(strengths, widget.initialStrength);
      _selectedRouteGroup = _routeForStrength(_drug, _selectedStrength);
    } else if (widget.initialStrength != null) {
      _selectedStrength = widget.initialStrength;
    }
    _loadLiveDetailsIfNeeded();
    _loadVerifiedPartners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final savedZip = context.read<CabinetProvider>().localZipCode;
      if (savedZip != null && savedZip.isNotEmpty) {
        _zipController.text = savedZip;
      }
    });
  }

  Future<void> _loadLiveDetailsIfNeeded() async {
    // If opened directly from Search (not yet synced via cabinet), fetch full live status & pricing
    if (_drug.verificationSources.isNotEmpty) return;
    setState(() => _isRefreshingDetails = true);
    try {
      final provider = context.read<CabinetProvider>();
      final api = ApiService(baseUrl: provider.serverUrl);
      final resp = await api.checkUpdates(rxcuis: [_drug.rxcui]);
      final List drugs = resp['drugs'] as List? ?? [];
      if (drugs.isNotEmpty && mounted) {
        final updated = _drug.copyWithUpdate(drugs.first as Map<String, dynamic>);
        setState(() {
          _drug = updated;
          if (updated.availableStrengths.isNotEmpty) {
            _selectedStrength = _matchBestStrength(
              updated.availableStrengths,
              widget.initialStrength ?? _selectedStrength,
            );
            _selectedRouteGroup = _routeForStrength(updated, _selectedStrength);
          }
          _isRefreshingDetails = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _isRefreshingDetails = false);
  }

  List<Map<String, dynamic>> _buildFallbackPartners(Drug drug) {
    final primary = drug.displayName.trim();
    final slug = primary
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .first
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final genericFirst = drug.genericName.trim().split(RegExp(r'[\s,/]+')).first;
    final list = <Map<String, dynamic>>[
      {
        'id': 'cost_plus_drugs',
        'label': 'Cost Plus Drugs',
        'url': 'https://www.costplusdrugs.com/medications/?search=${Uri.encodeQueryComponent(genericFirst.isNotEmpty ? genericFirst : primary)}',
        'price_hint': null,
      },
      {
        'id': 'amazon_pharmacy',
        'label': 'Amazon Pharmacy',
        'url': 'https://pharmacy.amazon.com/s?k=${Uri.encodeQueryComponent(primary)}&tag=danglingdices-20',
        'price_hint': null,
      },
    ];
    if (slug.length >= 3) {
      list.addAll([
        {
          'id': 'singlecare',
          'label': 'SingleCare Coupon',
          'url': 'https://www.singlecare.com/prescription/$slug',
          'price_hint': null,
        },
        {
          'id': 'goodrx',
          'label': 'GoodRx Coupon',
          'url': 'https://www.goodrx.com/$slug',
          'price_hint': null,
        },
        {
          'id': 'optum_perks',
          'label': 'Optum Perks Coupon',
          'url': 'https://perks.optum.com/drug/$slug',
          'price_hint': null,
        },
        {
          'id': 'wellrx',
          'label': 'WellRx Coupon',
          'url': 'https://www.wellrx.com/prescriptions/$slug/',
          'price_hint': null,
        },
      ]);
    }
    return list;
  }

  Future<void> _loadVerifiedPartners() async {
    if (widget.initialPartners != null) {
      if (mounted) {
        setState(() {
          _verifiedPartners = List<Map<String, dynamic>>.from(widget.initialPartners!);
          _isLoadingPartners = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingPartners = true;
        if (_verifiedPartners.isEmpty) {
          _verifiedPartners = _buildFallbackPartners(_drug);
        }
      });
    }
    final provider = context.read<CabinetProvider>();
    final api = ApiService(baseUrl: provider.serverUrl);
    final options = await api.getSavingsOptions(widget.drug.rxcui);
    final list = (options['partners'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
    if (mounted) {
      setState(() {
        _verifiedPartners = list.isNotEmpty ? list : _buildFallbackPartners(_drug);
        _discountCard = options['discount_card'] is Map<String, dynamic>
            ? options['discount_card'] as Map<String, dynamic>
            : null;
        _brandAssistance = options['brand_assistance'] is Map<String, dynamic>
            ? options['brand_assistance'] as Map<String, dynamic>
            : null;
        _isLoadingPartners = false;
      });
    }
  }

  @override
  void dispose() {
    _copayController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cabinet = context.watch<CabinetProvider>();
    final drug = _drug;
    final isWatched = cabinet.isWatched(drug.rxcui);
    final reminder = cabinet.reminderFor(drug.rxcui);
    final refill = cabinet.refillFor(drug.rxcui);
    final p = drug.pricing;

    final annualSavings = (_monthlyBrandCopay > _monthlyGenericCopay)
        ? (_monthlyBrandCopay - _monthlyGenericCopay) * 12
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(drug.displayName),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Doctor / Pharmacist Handout',
            onPressed: () => DoctorHandoutSheet.show(
              context,
              drug,
              selectedStrength: _selectedStrength,
              discountCard: _discountCard,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drug.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    drug.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (drug.availableStrengths.length > 1) ...[
                    ...() {
                      final routeGroups = drug.groupedStrengthsByRoute;
                      final hasMultipleRoutes = routeGroups.length > 1;
                      final activeRoute = (hasMultipleRoutes && routeGroups.containsKey(_selectedRouteGroup))
                          ? _selectedRouteGroup!
                          : (routeGroups.isNotEmpty ? routeGroups.keys.first : null);
                      final visibleStrengths = activeRoute != null
                          ? (routeGroups[activeRoute] ?? drug.availableStrengths)
                          : drug.availableStrengths;

                      return <Widget>[
                        Text(
                          hasMultipleRoutes
                              ? 'Dosage Form & Strength:'
                              : 'Select Your Dosage (Optional):',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (hasMultipleRoutes) ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: routeGroups.entries.map((entry) {
                                final isRouteSelected = entry.key == activeRoute;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    avatar: Icon(_iconForRouteGroup(entry.key), size: 16),
                                    label: Text('${entry.key} (${entry.value.length})'),
                                    selected: isRouteSelected,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      setState(() {
                                        _selectedRouteGroup = entry.key;
                                        if (!entry.value.contains(_selectedStrength) && entry.value.isNotEmpty) {
                                          _selectedStrength = entry.value.first;
                                        }
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: visibleStrengths.map((s) {
                            final isSelected = _selectedStrength == s;
                            return ChoiceChip(
                              label: Text(s),
                              selected: isSelected,
                              onSelected: (_) => setState(() => _selectedStrength = s),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ];
                    }(),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => DoctorHandoutSheet.show(
                          context,
                          drug,
                          selectedStrength: _selectedDosageSummary,
                        ),
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: const Text('Show Doctor / Pharmacist Card'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => ReminderSheet.show(
                          context,
                          drug,
                          dosage: _selectedDosageSummary,
                        ),
                        icon: Icon(
                          reminder != null && reminder.enabled
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_none_rounded,
                          size: 17,
                        ),
                        label: Text(
                          reminder != null
                              ? 'Reminder: ${reminder.scheduleSummary}'
                              : 'Set Reminder',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => RefillSetupSheet.show(context, drug),
                        icon: const Icon(Icons.event_repeat_rounded, size: 17),
                        label: Text(
                          refill != null ? refill.statusLabel() : 'Track Refill',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          if (isWatched) {
                            await cabinet.removeDrug(drug.rxcui);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${drug.displayName} removed from your cabinet')),
                              );
                            }
                          } else {
                            await cabinet.addDrug(drug);
                            if (!context.mounted) return;
                            final tracked = await RefillSetupSheet.show(
                              context,
                              drug,
                              isAddFlow: true,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    tracked == true
                                        ? '${drug.displayName} added with refill tracking'
                                        : '${drug.displayName} added to your cabinet',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        icon: Icon(isWatched ? Icons.check_circle : Icons.add, size: 18),
                        label: Text(isWatched ? 'In Cabinet' : 'Add to Cabinet'),
                      ),
                    ],
                  ),
                  if (_isRefreshingDetails) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Clean, patient-first 2-column layout on desktop (stacked on mobile)
            Builder(
              builder: (context) {
                final isWide = MediaQuery.sizeOf(context).width >= 900;
                final matchingShortages = _shortagesForSelectedStrength(drug);

                final leftCards = <Widget>[
                  if (matchingShortages.isNotEmpty)
                    _buildShortageCard(context, theme, matchingShortages),
                  if (refill != null)
                    _buildRefillCard(context, theme, cabinet, drug, refill),
                  _buildSubstitutionCard(context, theme, drug),
                ];

                final rightCards = <Widget>[
                  _buildPartnersCard(context, theme, drug),
                  if (_discountCard != null)
                    _buildDiscountCard(context, theme),
                  if (_brandAssistance != null)
                    _buildBrandAssistanceCard(context, theme),
                  _buildPricingAndCalculatorCard(context, theme, drug, p, annualSavings),
                ];

                Widget buildColumn(List<Widget> items) {
                  final spaced = <Widget>[];
                  for (var i = 0; i < items.length; i++) {
                    if (i > 0) spaced.add(const SizedBox(height: 18));
                    spaced.add(items[i]);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: spaced,
                  );
                }

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: buildColumn(leftCards)),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: buildColumn(rightCards)),
                    ],
                  );
                }

                return buildColumn([...leftCards, ...rightCards]);
              },
            ),

            const SizedBox(height: 20),

            // Zero-PII Anonymous Data Quality Flag Button
            Center(
              child: TextButton.icon(
                onPressed: () => _showFlagIssueSheet(context, drug),
                icon: Icon(Icons.flag_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                label: Text(
                  'Notice something off with this drug\'s info?',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showFlagIssueSheet(BuildContext context, Drug drug) {
    final options = <(String, String, IconData)>[
      ('generic_available', 'A generic version is actually available', Icons.verified_outlined),
      ('brand_only_now', 'No generic is actually available (Brand Only)', Icons.lock_clock),
      ('missing_dosage', 'Missing a dosage or strength', Icons.format_list_numbered),
      ('price_looks_off', 'Estimated price looks outdated or off', Icons.attach_money),
      ('shortage_incorrect', 'Shortage status looks outdated', Icons.warning_amber_outlined),
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help Improve Accuracy for ${drug.displayName}',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '100% anonymous — sends only the drug ID and issue category, with zero personal data.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final (issueCode, label, icon) in options)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      final provider = context.read<CabinetProvider>();
                      final api = ApiService(baseUrl: provider.serverUrl);
                      final ok = await api.submitDataQualityFlag(
                        rxcui: drug.rxcui,
                        issueType: issueCode,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Thank you! Flagged anonymously — no personal data was sent.'
                                  : 'Could not submit flag right now. Please try again later.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRefillCard(
    BuildContext context,
    ThemeData theme,
    CabinetProvider cabinet,
    Drug drug,
    RefillInfo refill,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final urgency = refill.urgency();
    final Color accent;
    switch (urgency) {
      case RefillUrgency.overdue:
        accent = Colors.red;
        break;
      case RefillUrgency.dueSoon:
        accent = Colors.amber.shade800;
        break;
      case RefillUrgency.ok:
        accent = Colors.teal;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? accent.withValues(alpha: 0.14) : accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? accent.withValues(alpha: 0.35) : accent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prescription Refill & Supply',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  refill.statusLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: refill.supplyProgress(),
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                'Day ${refill.daysElapsed()} of ${refill.daySupply}',
                style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(
                'Last filled: ${refill.lastFilledFormatted}',
                style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(
                'Next refill: ${refill.nextRefillFormatted}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (refill.refillsRemaining != null)
                Text(
                  refill.needsDoctorRenewal
                      ? '0 refills left — contact prescriber'
                      : '${refill.refillsRemaining} refill${refill.refillsRemaining == 1 ? '' : 's'} remaining',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: refill.needsDoctorRenewal ? Colors.red.shade700 : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await cabinet.markRefilledToday(drug.rxcui);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${drug.displayName} marked refilled today')),
                    );
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Mark Refilled Today'),
              ),
              OutlinedButton.icon(
                onPressed: () => RefillSetupSheet.show(context, drug),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Supply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCodePill(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubstitutionCard(BuildContext context, ThemeData theme, Drug drug) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = drug.commercialGenericAvailable
        ? (drug.isAutoSubstitutable ? Colors.teal : Colors.indigo)
        : Colors.blueGrey;
    final cardBg = isDark
        ? accent.withValues(alpha: 0.14)
        : accent.withValues(alpha: 0.07);
    final cardBorder = isDark
        ? accent.withValues(alpha: 0.35)
        : accent.withValues(alpha: 0.28);
    final iconColor = isDark ? accent.shade200 : accent.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                drug.isAutoSubstitutable
                    ? Icons.local_pharmacy
                    : Icons.medical_information_outlined,
                color: iconColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Generic Option & Pharmacy Guidance',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (drug.commercialGenericAvailable || drug.isUnbrandedGeneric) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drug.isUnbrandedGeneric
                        ? (drug.referenceBrands.isNotEmpty
                            ? 'Generic Version of Brand-Name Drug(s):'
                            : 'Already a Generic Medication:')
                        : (drug.drugType == 'biologic'
                            ? 'Available Biosimilar Prescription:'
                            : 'Ask Your Pharmacy For:'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    drug.isUnbrandedGeneric
                        ? (drug.referenceBrands.isNotEmpty
                            ? drug.referenceBrands.join(', ')
                            : drug.genericName)
                        : drug.genericName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Text(
            drug.substitutionPlainGuidance,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortageCard(
    BuildContext context,
    ThemeData theme,
    List<Map<String, dynamic>> matchingShortages,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.amber.withValues(alpha: 0.14)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.amber.withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: isDark ? Colors.amber.shade300 : Colors.orange.shade800,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedStrength != null
                      ? 'Active FDA Shortage ($_selectedStrength)'
                      : 'Active FDA Supply Shortage',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in matchingShortages) ...[
            if (s['dosage_form'] != null && s['dosage_form'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Affected Dose & Form: ${s['dosage_form']}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            if (s['reason'] != null)
              Text(
                'Reason: ${s['reason']}',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
              ),
            if (s['start_date'] != null)
              Text(
                'Reported: ${s['start_date']}',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 6),
          ],
          Link(
            uri: Uri.parse('https://www.accessdata.fda.gov/scripts/drugshortages/default.cfm'),
            target: LinkTarget.blank,
            builder: (context, followLink) => TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: followLink,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View FDA Drug Shortages'),
            ),
          ),
        ],
      ),
    );
  }

  Uri _buildClientPartnerUri(String id, String rawUrl, String? localZip) {
    final base = Uri.parse(rawUrl);
    if (localZip == null || localZip.length != 5) return base;
    final params = Map<String, String>.from(base.queryParameters);
    switch (id) {
      case 'goodrx':
        params['location'] = localZip;
        return base.replace(queryParameters: params);
      case 'singlecare':
      case 'optum_perks':
      case 'wellrx':
        params['zip'] = localZip;
        return base.replace(queryParameters: params);
      default:
        return base;
    }
  }

  Widget _buildPartnersCard(BuildContext context, ThemeData theme, Drug drug) {
    final cabinet = context.watch<CabinetProvider>();
    final localZip = cabinet.localZipCode;

    return Container(
      width: double.infinity,
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
              Icon(
                Icons.local_offer_outlined,
                color: theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade700,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Compare Cash & Pharmacy Prices',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Free cash-pay prices and retail pharmacy coupons for ${drug.displayName} (no account required):',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),

          // Optional on-device 5-digit ZIP code (never sent to Rx Savings Watch servers)
          Row(
            children: [
              SizedBox(
                width: 156,
                child: TextField(
                  controller: _zipController,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                    hintText: 'ZIP (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (val) {
                    final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length == 5) {
                      cabinet.setLocalZipCode(digits);
                    } else if (digits.isEmpty && localZip != null) {
                      cabinet.setLocalZipCode(null);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  localZip != null
                      ? 'Saved locally for $localZip • Never sent to our servers'
                      : 'Optional • Stored on this device only to pre-fill local coupons',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Instant 30-day retail cash benchmark from CMS NADAC (when available)
          if (drug.pricing?.genericNadacUnitPrice != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.teal.withValues(alpha: 0.14)
                    : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? Colors.teal.shade700
                      : Colors.teal.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    size: 18,
                    color: theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      () {
                        final base30 = drug.pricing!.genericNadacUnitPrice! * 30;
                        final low = (base30 + 5).round();
                        final high = (base30 + 12).round();
                        final zipNote = localZip != null ? ' near $localZip' : '';
                        return 'Est. 30-day generic cash range$zipNote: ~\$$low–\$$high (CMS NADAC + typical pharmacy fee). Tap a pharmacy below for exact live checkout prices.';
                      }(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.brightness == Brightness.dark ? Colors.teal.shade100 : Colors.teal.shade900,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_isLoadingPartners)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Checking live Cost Plus Drugs pricing...',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._verifiedPartners.map((partner) {
                final id = partner['id']?.toString() ?? '';
                final baseLabel = partner['label']?.toString() ?? 'Pharmacy';
                final priceHint = partner['price_hint']?.toString();
                final supportsZip = id == 'singlecare' || id == 'goodrx' || id == 'optum_perks' || id == 'wellrx';
                final String label;
                if (priceHint != null && priceHint.isNotEmpty) {
                  label = '$baseLabel ($priceHint)';
                } else if (supportsZip && localZip != null) {
                  label = '${baseLabel.replaceAll(' Coupon', '')} near $localZip';
                } else {
                  label = baseLabel;
                }
                final url = partner['url']?.toString() ?? '';
                final icon = switch (id) {
                  'cost_plus_drugs' => Icons.medication_outlined,
                  'amazon_pharmacy' => Icons.local_shipping_outlined,
                  'singlecare' => Icons.confirmation_number_outlined,
                  'goodrx' => Icons.savings_outlined,
                  'optum_perks' => Icons.local_pharmacy_outlined,
                  'wellrx' => Icons.discount_outlined,
                  _ => Icons.open_in_new,
                };
                return _buildPartnerButton(
                  context,
                  label: label,
                  icon: icon,
                  uri: _buildClientPartnerUri(id, url, localZip),
                );
              }),
              if (localZip != null)
                _buildPartnerButton(
                  context,
                  label: 'Pharmacies near $localZip',
                  icon: Icons.map_outlined,
                  uri: Uri.parse('https://www.google.com/maps/search/pharmacy+near+$localZip'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Cash-pay discounts only — not insurance. Clicking an external link opens that pharmacy\'s site under its own privacy policy. As an Amazon Associate we earn from qualifying purchases; some links may earn a small referral fee at zero cost to you.',
            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountCard(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.credit_card_outlined,
                color: theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade800,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _discountCard!['name']?.toString() ?? 'Pharmacy Discount Card',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Show these 4 numbers to your pharmacist for cash savings (no account required):',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildCodePill(context, 'BIN', _discountCard!['bin']?.toString() ?? ''),
              if (_discountCard!['pcn'] != null)
                _buildCodePill(context, 'PCN', _discountCard!['pcn'].toString()),
              _buildCodePill(context, 'GROUP', _discountCard!['group']?.toString() ?? ''),
              _buildCodePill(context, 'MEMBER ID', _discountCard!['member_id']?.toString() ?? ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrandAssistanceCard(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
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
              Icon(
                Icons.health_and_safety_outlined,
                color: theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade700,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Manufacturer Savings & Assistance',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_brandAssistance!['note'] != null) ...[
            const SizedBox(height: 6),
            Text(
              _brandAssistance!['note'].toString(),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_brandAssistance!['url'] != null)
                _buildPartnerButton(
                  context,
                  label: _brandAssistance!['program_name']?.toString() ?? 'Manufacturer Savings Card',
                  icon: Icons.card_giftcard_outlined,
                  uri: Uri.parse(_brandAssistance!['url'].toString()),
                ),
              if (_brandAssistance!['pap_url'] != null)
                _buildPartnerButton(
                  context,
                  label: 'Patient Assistance Program',
                  icon: Icons.volunteer_activism_outlined,
                  uri: Uri.parse(_brandAssistance!['pap_url'].toString()),
                ),
              if (_brandAssistance!['medicare_extra_help_url'] != null)
                _buildPartnerButton(
                  context,
                  label: 'Medicare Extra Help (SSA.gov)',
                  icon: Icons.account_balance_outlined,
                  uri: Uri.parse(_brandAssistance!['medicare_extra_help_url'].toString()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingAndCalculatorCard(
    BuildContext context,
    ThemeData theme,
    Drug drug,
    dynamic p,
    double annualSavings,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
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
              Icon(
                Icons.savings_outlined,
                color: isDark ? Colors.teal.shade200 : Colors.teal.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimated Cost & Savings',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (p != null && p.estimatedSavingsPct != null && p.estimatedSavingsPct! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '~${p.estimatedSavingsPct!.toStringAsFixed(0)}% GAP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Brand Acquisition Cost:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              Text(
                p?.brandNadacUnitPrice != null
                    ? '\$${p!.brandNadacUnitPrice!.toStringAsFixed(2)} / unit'
                    : 'Not reported',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Generic Acquisition Cost:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              Text(
                p?.genericNadacUnitPrice != null
                    ? '\$${p!.genericNadacUnitPrice!.toStringAsFixed(2)} / unit'
                    : (drug.commercialGenericAvailable ? 'Available' : 'Brand-only'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: p?.genericNadacUnitPrice != null
                      ? (isDark ? Colors.teal.shade200 : Colors.teal.shade800)
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          if (drug.commercialGenericAvailable) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your monthly brand copay (\$):',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                  ),
                ),
                SizedBox(
                  width: 78,
                  child: TextField(
                    controller: _copayController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _monthlyBrandCopay = double.tryParse(val) ?? 0.0;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Projected Annual Savings:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                Text(
                  '\$${annualSavings.toStringAsFixed(0)} / year',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartnerButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Uri uri,
  }) {
    return Link(
      uri: uri,
      target: LinkTarget.blank,
      builder: (context, followLink) => OutlinedButton.icon(
        onPressed: followLink,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}
