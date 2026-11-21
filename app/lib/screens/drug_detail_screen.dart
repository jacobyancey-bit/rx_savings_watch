import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/partner_links.dart';
import '../models/drug.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';
import '../widgets/doctor_handout_sheet.dart';
import '../widgets/signal_badges.dart';

class DrugDetailScreen extends StatefulWidget {
  final Drug drug;

  const DrugDetailScreen({super.key, required this.drug});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  final TextEditingController _copayController = TextEditingController(text: '60');
  double _monthlyBrandCopay = 60.0;
  final double _monthlyGenericCopay = 10.0;
  String? _selectedStrength;

  @override
  void initState() {
    super.initState();
    final strengths = widget.drug.availableStrengths;
    if (strengths.isNotEmpty) {
      _selectedStrength = strengths.first;
    }
  }

  @override
  void dispose() {
    _copayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drug = widget.drug;
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
            tooltip: 'Clinical Handout',
            onPressed: () => DoctorHandoutSheet.show(context, drug),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          drug.drugType.toUpperCase().replaceAll('_', ' '),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RxCUI: ${drug.rxcui}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                    Text(
                      'Select Your Dosage (Optional):',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: drug.availableStrengths.map((s) {
                        final isSelected = _selectedStrength == s;
                        return ChoiceChip(
                          label: Text(s),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedStrength = s),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => DoctorHandoutSheet.show(context, drug),
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('Show Doctor / Pharmacist Card'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Plain-English Substitution & Official Sources Trust Card (low-glare, theme-aware)
            Builder(
              builder: (context) {
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
                    borderRadius: BorderRadius.circular(14),
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
                              'Pharmacy Substitution Guidance',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        drug.substitutionPlainGuidance,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (drug.verificationSources.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Verified using: ${drug.verificationSources.join(' • ')}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 2-Signal Status Section
            Text(
              '2-Signal Commercial Launch Verification',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'A commercial generic alert requires BOTH regulatory FDA approval AND active wholesale commercial distribution.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SignalBadges(
              hasApprovedGeneric: drug.hasApprovedGeneric,
              commercialGenericAvailable: drug.commercialGenericAvailable,
              compact: false,
            ),

            const SizedBox(height: 24),

            // Pricing & Savings Section
            Text(
              'CMS NADAC Pricing & Acquisition Savings',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Brand Acquisition Cost:'),
                      Text(
                        p?.brandNadacUnitPrice != null
                            ? '\$${p!.brandNadacUnitPrice!.toStringAsFixed(2)} / unit'
                            : 'Not reported',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Generic Acquisition Cost:'),
                      Text(
                        p?.genericNadacUnitPrice != null
                            ? '\$${p!.genericNadacUnitPrice!.toStringAsFixed(2)} / unit'
                            : (drug.commercialGenericAvailable ? 'Available' : 'Pending market launch'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: p?.genericNadacUnitPrice != null
                              ? (theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade800)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  if (p != null && p.estimatedSavingsPct != null && p.estimatedSavingsPct! > 0) ...[
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estimated Savings:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '~${p.estimatedSavingsPct!.toStringAsFixed(0)}% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Annual Out-of-Pocket Copay Calculator
            if (drug.commercialGenericAvailable) ...[
              const SizedBox(height: 24),
              Text(
                'Personalized Annual Copay Calculator',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.teal.withValues(alpha: 0.12)
                      : Colors.teal.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark
                        ? Colors.teal.withValues(alpha: 0.35)
                        : Colors.teal.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your current monthly brand copay (\$):',
                            style: TextStyle(fontSize: 13.5, color: theme.colorScheme.onSurface),
                          ),
                        ),
                        SizedBox(
                          width: 80,
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
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Standard Tier 1 Generic Copay:'),
                        Text('\$${_monthlyGenericCopay.toStringAsFixed(0)} / mo', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Projected Annual Savings:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          '\$${annualSavings.toStringAsFixed(0)} / year',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Supply Shortages if active
            if (drug.hasActiveShortage) ...[
              const SizedBox(height: 24),
              Text(
                'FDA Drug Shortage Report',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.brightness == Brightness.dark ? Colors.amber.shade200 : Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.amber.withValues(alpha: 0.14)
                      : Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark
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
                          color: theme.brightness == Brightness.dark ? Colors.amber.shade300 : Colors.orange.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status: Current Shortage',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final s in drug.activeShortageDetails) ...[
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
                    ],
                  ],
                ),
              ),
            ],

            // Alerts Log
            if (drug.alerts.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Verified Launch Alerts',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final alert in drug.alerts)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active, color: Colors.teal),
                    title: Text(
                      alert.eventType.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(alert.signalSummary, style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      alert.detectedAt.split('T')[0],
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ),
                ),
            ],
            // Compare Cash & Discount Pharmacy Prices (Optional Outbound Referral Links)
            const SizedBox(height: 24),
            Container(
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
                      Icon(Icons.local_offer_outlined, color: Colors.teal.shade700, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Compare Cash & Discount Prices',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Check transparent cash prices or free pharmacy discount coupons for ${drug.displayName}:',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildPartnerButton(
                        context,
                        label: 'Cost Plus Drugs',
                        icon: Icons.medication_outlined,
                        uri: PartnerLinks.buildCostPlusDrugsUrl(drug.genericName),
                      ),
                      _buildPartnerButton(
                        context,
                        label: 'Amazon Pharmacy',
                        icon: Icons.local_shipping_outlined,
                        uri: PartnerLinks.buildAmazonPharmacyUrl(drug.displayName),
                      ),
                      _buildPartnerButton(
                        context,
                        label: 'SingleCare Coupon',
                        icon: Icons.confirmation_number_outlined,
                        uri: PartnerLinks.buildSingleCareUrl(drug.displayName),
                      ),
                      _buildPartnerButton(
                        context,
                        label: 'GoodRx Coupon',
                        icon: Icons.savings_outlined,
                        uri: PartnerLinks.buildGoodRxUrl(drug.displayName),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Transparency notice: Some links may earn Dangling Dice Studios a small referral fee at zero cost to you. No personal data is shared when you open a link.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

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
      ('missing_dosage', 'Missing a dosage or strength', Icons.format_list_numbered),
      ('generic_available', 'A generic version is actually available', Icons.verified_outlined),
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

  Widget _buildPartnerButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Uri uri,
  }) {
    return OutlinedButton.icon(
      onPressed: () async {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open $label link.')),
          );
        }
      },
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}
