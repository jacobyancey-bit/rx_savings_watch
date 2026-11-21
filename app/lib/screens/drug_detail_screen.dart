import 'package:flutter/material.dart';
import '../models/drug.dart';
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
                  OutlinedButton.icon(
                    onPressed: () => DoctorHandoutSheet.show(context, drug),
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('Show Doctor / Pharmacist Card'),
                  ),
                ],
              ),
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
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
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
                          color: p?.genericNadacUnitPrice != null ? Colors.green.shade700 : Colors.black87,
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
                            color: Colors.green.shade600,
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
                  color: Colors.green.shade50.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your current monthly brand copay (\$):',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
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
                            color: Colors.green.shade800,
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
                  color: Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade800, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Status: Current Shortage',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final s in drug.activeShortageDetails) ...[
                      if (s['reason'] != null)
                        Text(
                          'Reason: ${s['reason']}',
                          style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                        ),
                      if (s['start_date'] != null)
                        Text(
                          'Reported: ${s['start_date']}',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
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
          ],
        ),
      ),
    );
  }
}
