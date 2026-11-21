import 'package:flutter/material.dart';
import '../models/drug.dart';
import 'signal_badges.dart';
import 'savings_badge.dart';

class DrugCard extends StatelessWidget {
  final Drug drug;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const DrugCard({
    super.key,
    required this.drug,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final semanticLabel = '${drug.displayName}, ${drug.genericName}. '
        '${drug.commercialGenericAvailable ? "Generic launched. 2-Signal verified." : "Brand only."}'
        '${drug.hasActiveShortage ? " Active FDA supply shortage reported." : ""}';

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: drug.commercialGenericAvailable
                ? Colors.green.shade300
                : Colors.grey.shade200,
            width: drug.commercialGenericAvailable ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Brand & Generic name + Savings badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drug.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            drug.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (drug.commercialGenericAvailable && drug.pricing != null)
                      SavingsBadge(pricing: drug.pricing),
                  ],
                ),

                const SizedBox(height: 12),

                // Shortage banner if active
                if (drug.hasActiveShortage) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'FDA Supply Shortage Active',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Signal badges row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SignalBadges(
                      hasApprovedGeneric: drug.hasApprovedGeneric,
                      commercialGenericAvailable: drug.commercialGenericAvailable,
                      compact: true,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade400),
                      onPressed: onRemove,
                      tooltip: 'Remove from cabinet',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
