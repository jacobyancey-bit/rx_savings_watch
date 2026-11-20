import 'package:flutter/material.dart';
import '../models/pricing_info.dart';

class SavingsBadge extends StatelessWidget {
  final PricingInfo? pricing;

  const SavingsBadge({super.key, required this.pricing});

  @override
  Widget build(BuildContext context) {
    if (pricing == null || pricing!.estimatedSavingsPct == null) {
      return const SizedBox.shrink();
    }

    final pct = pricing!.estimatedSavingsPct!;
    if (pct <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade600, Colors.teal.shade800],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_down, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'Save ${pct.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
