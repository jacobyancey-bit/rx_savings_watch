import 'package:flutter/material.dart';

class SignalBadges extends StatelessWidget {
  final bool hasApprovedGeneric;
  final bool commercialGenericAvailable;
  final bool compact;

  const SignalBadges({
    super.key,
    required this.hasApprovedGeneric,
    required this.commercialGenericAvailable,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      if (hasApprovedGeneric && commercialGenericAvailable) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade600, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, size: 14, color: Colors.green.shade700),
              const SizedBox(width: 4),
              Text(
                '2-Signal Verified',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
        );
      } else if (hasApprovedGeneric) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade600, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pending_actions, size: 14, color: Colors.amber.shade800),
              const SizedBox(width: 4),
              Text(
                'FDA Approved (Awaiting Launch)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_clock, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                'Brand Only',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSignalChip(
              title: 'Signal 1: Regulatory FDA Approval',
              isVerified: hasApprovedGeneric,
              activeColor: Colors.teal,
              icon: Icons.check_circle_outline,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _buildSignalChip(
              title: 'Signal 2: Commercial Distribution & Pricing',
              isVerified: commercialGenericAvailable,
              activeColor: Colors.blue,
              icon: Icons.local_shipping_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignalChip({
    required String title,
    required bool isVerified,
    required Color activeColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isVerified ? activeColor.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVerified ? activeColor : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isVerified ? activeColor : Colors.grey.shade500,
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isVerified ? FontWeight.bold : FontWeight.normal,
              color: isVerified ? activeColor.withValues(alpha: 0.9) : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
