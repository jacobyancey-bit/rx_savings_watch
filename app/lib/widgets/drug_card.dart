import 'package:flutter/material.dart';
import '../models/drug.dart';
import '../models/medication_reminder.dart';
import '../models/refill_info.dart';
import 'signal_badges.dart';
import 'savings_badge.dart';

class DrugCard extends StatelessWidget {
  final Drug drug;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final MedicationReminder? reminder;
  final VoidCallback? onReminderTap;
  final VoidCallback? onToggleTaken;
  final RefillInfo? refill;
  final VoidCallback? onRefillTap;
  final VoidCallback? onMarkRefilled;

  const DrugCard({
    super.key,
    required this.drug,
    required this.onTap,
    required this.onRemove,
    this.reminder,
    this.onReminderTap,
    this.onToggleTaken,
    this.refill,
    this.onRefillTap,
    this.onMarkRefilled,
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

                // Plain-English generic prescription name & substitution guidance when available
                if (drug.commercialGenericAvailable || drug.isUnbrandedGeneric) ...[
                  Text(
                    drug.isUnbrandedGeneric
                        ? (drug.referenceBrands.isNotEmpty
                            ? 'Generic for: ${drug.referenceBrands.join(', ')}'
                            : 'Already a Generic Medication')
                        : 'Ask for: ${drug.genericName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: theme.brightness == Brightness.dark
                          ? Colors.teal.shade200
                          : Colors.teal.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        drug.isAutoSubstitutable
                            ? Icons.local_pharmacy_outlined
                            : Icons.medical_information_outlined,
                        size: 16,
                        color: drug.isAutoSubstitutable
                            ? (theme.brightness == Brightness.dark ? Colors.teal.shade200 : Colors.teal.shade700)
                            : (theme.brightness == Brightness.dark ? Colors.indigo.shade200 : Colors.indigo.shade700),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          drug.substitutionPlainGuidance,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // Daily Medication Reminder, Taken Today, & Refill Tracker strip
                if (onReminderTap != null || onRefillTap != null) ...[
                  _buildActionStrip(context, theme),
                  const SizedBox(height: 10),
                ],

                // Signal badges row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: SignalBadges(
                        hasApprovedGeneric: drug.hasApprovedGeneric,
                        commercialGenericAvailable: drug.commercialGenericAvailable,
                        compact: true,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 22, color: Colors.grey.shade600),
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

  Widget _buildActionStrip(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final r = reminder;
    final rf = refill;
    final chips = <Widget>[];

    // 1. Reminder / Taken Today chips
    if (onReminderTap != null) {
      if (r == null) {
        chips.add(
          InkWell(
            onTap: onReminderTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 16,
                    color: isDark ? Colors.teal.shade200 : Colors.teal.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Set Reminder',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final taken = r.isTakenToday();
        final activeColor = r.enabled
            ? (isDark ? Colors.teal.shade200 : Colors.teal.shade800)
            : Colors.grey.shade600;

        chips.add(
          InkWell(
            onTap: onReminderTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: r.enabled
                    ? (isDark ? Colors.teal.withValues(alpha: 0.18) : Colors.teal.shade50)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: r.enabled
                      ? (isDark ? Colors.teal.shade400 : Colors.teal.shade300)
                      : Colors.grey.shade400,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    r.enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    size: 15,
                    color: activeColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    r.enabled ? r.scheduleSummary : 'Paused • ${r.scheduleSummary}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: activeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (onToggleTaken != null) {
          chips.add(
            InkWell(
              onTap: onToggleTaken,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: taken
                      ? (isDark ? Colors.green.withValues(alpha: 0.22) : Colors.green.shade50)
                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: taken
                        ? Colors.green.shade400
                        : Colors.grey.shade400,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      taken ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 15,
                      color: taken
                          ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      taken ? 'Taken Today' : 'Mark Taken',
                      style: TextStyle(
                        fontSize: 12.5,
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
          );
        }
      }
    }

    // 2. Refill tracker chips
    if (onRefillTap != null) {
      if (rf == null) {
        chips.add(
          InkWell(
            onTap: onRefillTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_repeat_rounded,
                    size: 15,
                    color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade700,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Track Refill',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final urgency = rf.urgency();
        Color bg;
        Color border;
        Color fg;
        IconData icon;
        switch (urgency) {
          case RefillUrgency.overdue:
            bg = isDark ? Colors.red.withValues(alpha: 0.22) : Colors.red.shade50;
            border = isDark ? Colors.red.shade400 : Colors.red.shade300;
            fg = isDark ? Colors.red.shade200 : Colors.red.shade900;
            icon = Icons.error_outline_rounded;
            break;
          case RefillUrgency.dueSoon:
            bg = isDark ? Colors.amber.withValues(alpha: 0.22) : Colors.amber.shade50;
            border = isDark ? Colors.amber.shade400 : Colors.amber.shade400;
            fg = isDark ? Colors.amber.shade200 : Colors.amber.shade900;
            icon = Icons.schedule_rounded;
            break;
          case RefillUrgency.ok:
            bg = isDark ? Colors.indigo.withValues(alpha: 0.18) : Colors.indigo.shade50;
            border = isDark ? Colors.indigo.shade400 : Colors.indigo.shade200;
            fg = isDark ? Colors.indigo.shade200 : Colors.indigo.shade900;
            icon = Icons.event_repeat_rounded;
            break;
        }

        final renewalTag = rf.needsDoctorRenewal ? ' • 0 left' : '';
        chips.add(
          InkWell(
            onTap: onRefillTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 5),
                  Text(
                    '${rf.statusLabel()} (${rf.nextRefillFormatted})$renewalTag',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (rf.isDueOrOverdue() && onMarkRefilled != null) {
          chips.add(
            InkWell(
              onTap: onMarkRefilled,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.teal.withValues(alpha: 0.24) : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.teal.shade400 : Colors.teal.shade400,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 15,
                      color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Mark Refilled',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }
}
