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

  static const List<(String, int)> _weekdayOptions = [
    ('Sun', DateTime.sunday),
    ('Mon', DateTime.monday),
    ('Tue', DateTime.tuesday),
    ('Wed', DateTime.wednesday),
    ('Thu', DateTime.thursday),
    ('Fri', DateTime.friday),
    ('Sat', DateTime.saturday),
  ];

  late List<ReminderTime> _selectedTimes;
  late ReminderFrequency _frequency;
  late List<int> _weekdays;
  late int _dayOfMonth;
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
      _frequency = existing.frequency;
      _weekdays = List<int>.from(existing.normalizedWeekdays);
      _dayOfMonth = existing.dayOfMonth;
      _enabled = existing.enabled;
      _discreetLockScreen = existing.discreetLockScreen;
    } else {
      _selectedTimes = [const ReminderTime(hour: 8, minute: 0)];
      _frequency = ReminderFrequency.daily;
      _weekdays = [DateTime.now().weekday];
      _dayOfMonth = DateTime.now().day.clamp(1, 28);
      _enabled = true;
      _discreetLockScreen = false;
    }
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      if (_weekdays.contains(weekday)) {
        if (_weekdays.length > 1) {
          _weekdays.remove(weekday);
        }
      } else {
        _weekdays.add(weekday);
        _weekdays.sort();
      }
    });
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
      frequency: _frequency,
      weekdays: List<int>.from(_weekdays),
      dayOfMonth: _dayOfMonth,
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
              ? 'Reminder set for ${widget.drug.displayName} (${reminder.scheduleSummary})'
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
      SnackBar(content: Text('Removed reminder for ${widget.drug.displayName}')),
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
                        'Medication Reminder',
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
              'How often do you take it?',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ReminderFrequency>(
                segments: const [
                  ButtonSegment(
                    value: ReminderFrequency.daily,
                    label: Text('Every Day'),
                  ),
                  ButtonSegment(
                    value: ReminderFrequency.specificDays,
                    label: Text('Specific Days'),
                  ),
                  ButtonSegment(
                    value: ReminderFrequency.monthly,
                    label: Text('Monthly'),
                  ),
                ],
                selected: {_frequency},
                onSelectionChanged: (sel) => setState(() => _frequency = sel.first),
              ),
            ),

            if (_frequency == ReminderFrequency.specificDays) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (label, dayNum) in _weekdayOptions)
                    FilterChip(
                      label: Text(label),
                      selected: _weekdays.contains(dayNum),
                      onSelected: (_) => _toggleWeekday(dayNum),
                    ),
                ],
              ),
            ],

            if (_frequency == ReminderFrequency.monthly) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Day of every month:',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _dayOfMonth,
                    items: List.generate(
                      28,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(MedicationReminder.ordinalDay(i + 1)),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _dayOfMonth = v);
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            Text(
              'What time?',
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
                    : 'Schedule: ${_buildReminder().scheduleSummary}',
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
                  label: const Text('Add Reminder to Phone Calendar (.ics)'),
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
