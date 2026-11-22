import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/drug.dart';
import '../models/medication_reminder.dart';
import '../providers/cabinet_provider.dart';

class ReminderSheet extends StatefulWidget {
  final Drug drug;
  final String? dosage;

  const ReminderSheet({
    super.key,
    required this.drug,
    this.dosage,
  });

  static Future<void> show(
    BuildContext context,
    Drug drug, {
    String? dosage,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReminderSheet(drug: drug, dosage: dosage),
    );
  }

  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  static const List<(String, ReminderTime)> _presets = [
    ('Morning', ReminderTime(hour: 8, minute: 0)),
    ('Noon', ReminderTime(hour: 12, minute: 0)),
    ('Evening', ReminderTime(hour: 18, minute: 0)),
    ('Bedtime', ReminderTime(hour: 21, minute: 0)),
  ];

  late List<ReminderTime> _selectedTimes;
  late bool _enabled;
  late bool _discreetLockScreen;
  bool _hasExisting = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = context.read<CabinetProvider>().reminderFor(widget.drug.rxcui);
    if (existing != null) {
      _hasExisting = true;
      _selectedTimes = List<ReminderTime>.from(existing.times);
      _enabled = existing.enabled;
      _discreetLockScreen = existing.discreetLockScreen;
    } else {
      _selectedTimes = [const ReminderTime(hour: 8, minute: 0)];
      _enabled = true;
      _discreetLockScreen = false;
    }
  }

  void _toggleTime(ReminderTime time) {
    setState(() {
      if (_selectedTimes.contains(time)) {
        _selectedTimes.remove(time);
      } else if (_selectedTimes.length < 6) {
        _selectedTimes.add(time);
        _selectedTimes.sort((a, b) => a.totalMinutes.compareTo(b.totalMinutes));
      }
    });
  }

  Future<void> _pickCustomTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimes.isNotEmpty
          ? TimeOfDay(hour: _selectedTimes.last.hour, minute: _selectedTimes.last.minute)
          : const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null || !mounted) return;
    final t = ReminderTime(hour: picked.hour, minute: picked.minute);
    if (!_selectedTimes.contains(t) && _selectedTimes.length < 6) {
      setState(() {
        _selectedTimes.add(t);
        _selectedTimes.sort((a, b) => a.totalMinutes.compareTo(b.totalMinutes));
      });
    }
  }

  MedicationReminder _buildReminder() {
    final existing = context.read<CabinetProvider>().reminderFor(widget.drug.rxcui);
    return MedicationReminder(
      rxcui: widget.drug.rxcui,
      drugName: widget.drug.displayName,
      dosage: widget.dosage ?? existing?.dosage,
      times: List<ReminderTime>.from(_selectedTimes),
      enabled: _enabled,
      discreetLockScreen: _discreetLockScreen,
      takenDate: existing?.takenDate,
    );
  }

  Future<void> _save() async {
    if (_selectedTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one reminder time.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    final cabinet = context.read<CabinetProvider>();
    final reminder = _buildReminder();
    await cabinet.saveReminder(reminder);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _enabled
              ? 'Daily reminder set for ${widget.drug.displayName} (${reminder.formattedTimesSummary})'
              : 'Reminder paused for ${widget.drug.displayName}',
        ),
        backgroundColor: Colors.teal.shade700,
      ),
    );
  }

  Future<void> _remove() async {
    await context.read<CabinetProvider>().deleteReminder(widget.drug.rxcui);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed daily reminder for ${widget.drug.displayName}')),
    );
  }

  Future<void> _exportCalendarIcs() async {
    if (_selectedTimes.isEmpty) return;
    final reminder = _buildReminder();
    final ics = reminder.buildIcsContent();
    final dataUri = Uri.parse(
      'data:text/calendar;charset=utf-8,${Uri.encodeComponent(ics)}',
    );
    await launchUrl(dataUri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final customTimes = _selectedTimes
        .where((t) => !_presets.any((p) => p.$2 == t))
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.alarm_outlined, color: theme.colorScheme.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Reminder',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.dosage != null && widget.dosage!.isNotEmpty
                            ? '${widget.drug.displayName} (${widget.dosage})'
                            : widget.drug.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Privacy callout
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.teal.shade900.withValues(alpha: 0.32)
                    : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.teal.shade700 : Colors.teal.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kIsWeb
                          ? 'Stored only in this browser. For automatic background phone alarms, add to your Calendar below or use the Android app.'
                          : 'Stored 100% on this phone—never sent to any server. Fires daily even when the app is closed.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: isDark ? Colors.teal.shade100 : Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'When do you take this medication?',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, time) in _presets)
                  FilterChip(
                    label: Text('$label (${time.format12Hour()})'),
                    selected: _selectedTimes.contains(time),
                    onSelected: (_) => _toggleTime(time),
                  ),
                for (final ct in customTimes)
                  InputChip(
                    label: Text(ct.format12Hour()),
                    selected: true,
                    onDeleted: () => _toggleTime(ct),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_alarm, size: 18),
                  label: const Text('Custom Time'),
                  onPressed: _pickCustomTime,
                ),
              ],
            ),

            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminder Active'),
              subtitle: Text(
                _selectedTimes.isEmpty
                    ? 'Select at least one time above'
                    : 'Repeats daily at ${_buildReminder().formattedTimesSummary}',
              ),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide drug name on lock screen'),
              subtitle: const Text('Shows "Time to take your scheduled medication" for extra privacy'),
              value: _discreetLockScreen,
              onChanged: (v) => setState(() => _discreetLockScreen = v),
            ),

            if (kIsWeb && _selectedTimes.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _exportCalendarIcs,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('Add Daily Reminder to Phone Calendar (.ics)'),
                ),
              ),
            ],

            const SizedBox(height: 14),

            Row(
              children: [
                if (_hasExisting) ...[
                  OutlinedButton.icon(
                    onPressed: _remove,
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 18),
                    label: Text('Remove', style: TextStyle(color: Colors.red.shade700)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.check),
                      label: const Text(
                        'Save Reminder',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
