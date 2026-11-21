import 'package:flutter/material.dart';

/// Persistent, high-visibility privacy trust indicator designed for older adults
/// and privacy-conscious patients. Tapping opens the plain-English Privacy Promise.
class PrivacyTrustBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const PrivacyTrustBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.teal.shade900.withValues(alpha: 0.45) : Colors.teal.shade50;
    final borderColor = isDark ? Colors.teal.shade600 : Colors.teal.shade300;
    final textColor = isDark ? Colors.teal.shade100 : Colors.teal.shade900;

    return Semantics(
      label: 'No personal data collected. Your medicine list stays only on this phone. Tap to learn how we protect your privacy.',
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap ?? () => PrivacyPromiseSheet.show(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: isDark ? Colors.teal.shade200 : Colors.teal.shade800, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No Personal Data Collected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your medicine list stays only on this phone.',
                          style: TextStyle(
                            fontSize: 13,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Learn how',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain-English modal sheet explaining the app's zero-data-collection guarantee.
class PrivacyPromiseSheet extends StatelessWidget {
  const PrivacyPromiseSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PrivacyPromiseSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.teal.shade700, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Our Privacy Promise',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Your health information belongs strictly to you. Rx Savings Watch is built so we never know who you are or what medicines you take.',
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 18),
              _buildPromiseRow(
                context,
                icon: Icons.person_off_outlined,
                title: 'No Account or Sign-Up',
                description: 'We never ask for your name, email address, phone number, insurance ID, or birthday.',
              ),
              _buildPromiseRow(
                context,
                icon: Icons.phone_android_outlined,
                title: 'Stored Only on Your Phone',
                description: 'Your medication list is saved privately on this device—never uploaded to a cloud profile.',
              ),
              _buildPromiseRow(
                context,
                icon: Icons.shuffle_outlined,
                title: 'Anonymous Price & Generic Checks',
                description: 'When checking for lower-cost generics, the app mixes your lookups with random common medicines so no one can tell which ones are yours.',
              ),
              _buildPromiseRow(
                context,
                icon: Icons.delete_sweep_outlined,
                title: 'You Are Always in Control',
                description: 'You can erase your entire medicine list from this phone with one tap in Settings at any time.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Got It',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromiseRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.teal.shade700, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
