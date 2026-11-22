import 'package:flutter/material.dart';
import '../models/medication_reminder.dart';
import '../models/otc_supplement.dart';

class SupplementCard extends StatelessWidget {
  final OtcSupplement supplement;
  final MedicationReminder? reminder;
  final VoidCallback onReminderTap;
  final VoidCallback onToggleTaken;
  final VoidCallback onRemove;

  const SupplementCard({
    super.key,
    required this.supplement,
    this.reminder,
    required this.onReminderTap,
    required this.onToggleTaken,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final r = reminder;
    final taken = r?.isTakenToday() ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      color: isDark
          ? theme.colorScheme.surfaceContainerLow
          : Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.spa_outlined,
                  size: 18,
                  color: isDark ? Colors.teal.shade300 : Colors.teal.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplement.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                      if (supplement.subtitle.isNotEmpty)
                        Text(
                          supplement.subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade600),
                  onPressed: onRemove,
                  tooltip: 'Remove supplement',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  onTap: onReminderTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: r != null && r.enabled
                          ? (isDark ? Colors.teal.withValues(alpha: 0.18) : Colors.teal.shade50)
                          : (isDark ? Colors.grey.shade800 : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: r != null && r.enabled
                            ? (isDark ? Colors.teal.shade400 : Colors.teal.shade300)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          r == null
                              ? Icons.notifications_none_rounded
                              : (r.enabled
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_off_outlined),
                          size: 14,
                          color: r == null || r.enabled
                              ? (isDark ? Colors.teal.shade200 : Colors.teal.shade800)
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          r == null
                              ? 'Set Reminder'
                              : (r.enabled ? r.scheduleSummary : 'Paused • ${r.scheduleSummary}'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: r == null || r.enabled
                                ? (isDark ? Colors.teal.shade200 : Colors.teal.shade800)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (r != null)
                  InkWell(
                    onTap: onToggleTaken,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: taken
                            ? (isDark ? Colors.green.withValues(alpha: 0.22) : Colors.green.shade50)
                            : (isDark ? Colors.grey.shade800 : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: taken ? Colors.green.shade400 : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            taken ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 14,
                            color: taken
                                ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            taken ? 'Taken Today' : 'Mark Taken',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: taken
                                  ? (isDark ? Colors.green.shade200 : Colors.green.shade800)
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
