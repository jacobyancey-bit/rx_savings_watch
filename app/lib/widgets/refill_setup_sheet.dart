import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/drug.dart';
import '../models/refill_info.dart';
import '../providers/cabinet_provider.dart';

class RefillSetupSheet extends StatefulWidget {
  final Drug drug;
  final bool isAddFlow;

  const RefillSetupSheet({
    super.key,
    required this.drug,
    this.isAddFlow = false,
  });

  static Future<bool?> show(
    BuildContext context,
    Drug drug, {
    bool isAddFlow = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RefillSetupSheet(drug: drug, isAddFlow: isAddFlow),
    );
  }

  @override
  State<RefillSetupSheet> createState() => _RefillSetupSheetState();
}

class _RefillSetupSheetState extends State<RefillSetupSheet> {
  static const List<int> _supplyPresets = [30, 60, 90];
  static const List<int> _leadPresets = [3, 5, 7, 10];

  late DateTime _lastFilled;
  late int _daySupply;
  late int _remindDaysBefore;
  int? _refillsRemaining;
  bool _hasExisting = false;
  bool _isSaving = false;
  late TextEditingController _customSupplyController;
  bool _showCustomSupply = false;

  @override
  void initState() {
    super.initState();
    final existing = context.read<CabinetProvider>().refillFor(widget.drug.rxcui);
    if (existing != null) {
      _hasExisting = true;
      _lastFilled = existing.lastFilled;
      _daySupply = existing.daySupply;
      _remindDaysBefore = existing.remindDaysBefore;
      _refillsRemaining = existing.refillsRemaining;
      _showCustomSupply = !_supplyPresets.contains(_daySupply);
    } else {
      final now = DateTime.now();
      _lastFilled = DateTime(now.year, now.month, now.day);
      _daySupply = 30;
      _remindDaysBefore = 5;
      _refillsRemaining = null;
    }
    _customSupplyController = TextEditingController(text: '$_daySupply');
  }

  @override
  void dispose() {
    _customSupplyController.dispose();
    super.dispose();
  }

  RefillInfo _buildDraft() {
    return RefillInfo(
      rxcui: widget.drug.rxcui,
      drugName: widget.drug.displayName,
      lastFilledDate: RefillInfo.dateKey(_lastFilled),
      daySupply: _daySupply.clamp(1, 365),
      remindDaysBefore: _remindDaysBefore.clamp(0, 30),
      refillsRemaining: _refillsRemaining,
      enabled: true,
    );
  }

  Future<void> _pickLastFilledDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastFilled.isAfter(now) ? now : _lastFilled,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'When was this prescription last filled?',
    );
    if (picked != null && mounted) {
      setState(() {
        _lastFilled = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final provider = context.read<CabinetProvider>();
    if (!provider.isWatched(widget.drug.rxcui)) {
      await provider.addDrug(widget.drug);
    }
    await provider.saveRefill(_buildDraft());
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _markRefilledToday() async {
    setState(() => _isSaving = true);
    final provider = context.read<CabinetProvider>();
    await provider.markRefilledToday(widget.drug.rxcui);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _removeTracker() async {
    setState(() => _isSaving = true);
    await context.read<CabinetProvider>().deleteRefill(widget.drug.rxcui);
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _exportCalendar() async {
    final draft = _buildDraft();
    final ics = draft.buildIcsContent();
    final uri = Uri.dataFromString(
      ics,
      mimeType: 'text/calendar',
      parameters: {'charset': 'utf-8'},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final draft = _buildDraft();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _lastFilled == today;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.event_repeat_rounded, color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isAddFlow
                            ? 'Track Refill for ${widget.drug.displayName}'
                            : 'Refill & Supply — ${widget.drug.displayName}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Stored strictly on this device • Never shared with servers',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Last filled date
            Text(
              'Last Filled Date',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: isToday,
                  onSelected: (_) => setState(() => _lastFilled = today),
                ),
                ChoiceChip(
                  label: const Text('Yesterday'),
                  selected: _lastFilled == today.subtract(const Duration(days: 1)),
                  onSelected: (_) =>
                      setState(() => _lastFilled = today.subtract(const Duration(days: 1))),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    isToday
                        ? 'Pick Date'
                        : 'Filled ${RefillInfo.formatShortDate(_lastFilled)}',
                  ),
                  onPressed: _pickLastFilledDate,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Day supply
            Text(
              'Prescription Day Supply',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in _supplyPresets)
                  ChoiceChip(
                    label: Text('$days days'),
                    selected: !_showCustomSupply && _daySupply == days,
                    onSelected: (_) => setState(() {
                      _showCustomSupply = false;
                      _daySupply = days;
                      _customSupplyController.text = '$days';
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: _showCustomSupply,
                  onSelected: (_) => setState(() => _showCustomSupply = true),
                ),
              ],
            ),
            if (_showCustomSupply) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _customSupplyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days supply',
                    suffixText: 'days',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null && parsed >= 1 && parsed <= 365) {
                      setState(() => _daySupply = parsed);
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 3. Lead time before running out
            Text(
              'Remind Me Before Running Out',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final lead in _leadPresets)
                  ChoiceChip(
                    label: Text('$lead days before'),
                    selected: _remindDaysBefore == lead,
                    onSelected: (_) => setState(() => _remindDaysBefore = lead),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Optional refills remaining
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Refills Remaining (Optional)',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_refillsRemaining != null)
                  TextButton(
                    onPressed: () => setState(() => _refillsRemaining = null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in [0, 1, 2, 3, 5, 11])
                  ChoiceChip(
                    label: Text(count == 0 ? '0 (Need Dr.)' : '$count'),
                    selected: _refillsRemaining == count,
                    onSelected: (_) => setState(() {
                      _refillsRemaining = _refillsRemaining == count ? null : count;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // Live calculation preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                    : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.teal.shade700 : Colors.teal.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_available_rounded, color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next refill due ${draft.nextRefillFormatted} (${draft.statusLabel()})',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Alert starts ${RefillInfo.formatShortDate(draft.reminderDate)} ($_remindDaysBefore days before supply ends)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.teal.shade100 : Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Action buttons
            Row(
              children: [
                if (widget.isAddFlow) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Skip for Now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(_hasExisting ? 'Save Refill Settings' : 'Save Refill Tracker'),
                  ),
                ),
              ],
            ),
            if (_hasExisting) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _markRefilledToday,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Mark Refilled Today'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportCalendar,
                    icon: const Icon(Icons.calendar_month_outlined, size: 17),
                    label: const Text('Add to Calendar (.ics)'),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _removeTracker,
                    icon: Icon(Icons.delete_outline, size: 17, color: Colors.red.shade600),
                    label: Text('Stop Tracking', style: TextStyle(color: Colors.red.shade600)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
