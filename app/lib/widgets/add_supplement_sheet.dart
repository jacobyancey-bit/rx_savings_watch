import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/otc_supplement.dart';
import '../providers/cabinet_provider.dart';

class AddSupplementSheet extends StatefulWidget {
  final String? initialName;

  const AddSupplementSheet({super.key, this.initialName});

  static Future<OtcSupplement?> show(
    BuildContext context, {
    String? initialName,
  }) {
    return showModalBottomSheet<OtcSupplement>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddSupplementSheet(initialName: initialName),
    );
  }

  @override
  State<AddSupplementSheet> createState() => _AddSupplementSheetState();
}

class _AddSupplementSheetState extends State<AddSupplementSheet> {
  late final TextEditingController _nameController;
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cleanName = OtcSupplement.sanitizeText(
      _nameController.text,
      OtcSupplement.maxNameLength,
    );
    if (cleanName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a supplement or OTC name.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final added = await context.read<CabinetProvider>().addSupplement(
          name: cleanName,
          dosage: _dosageController.text,
          note: _noteController.text,
        );
    if (!mounted) return;
    Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      child: SingleChildScrollView(
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
                Icon(Icons.spa_outlined, color: Colors.teal.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add OTC / Supplement',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.teal.shade900.withValues(alpha: 0.3)
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
                    size: 16,
                    color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stored strictly on this device and kept separate from FDA prescriptions. Supports reminders & Taken Today.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.teal.shade100 : Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Common Picks (1-Tap Fill)',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (presetName, presetDose) in OtcSupplement.commonPresets)
                  ActionChip(
                    label: Text(presetName),
                    onPressed: () {
                      setState(() {
                        _nameController.text = presetName;
                        _dosageController.text = presetDose;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              maxLength: OtcSupplement.maxNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name (e.g., Vitamin D3, Magnesium)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dosageController,
              maxLength: OtcSupplement.maxDosageLength,
              decoration: const InputDecoration(
                labelText: 'Strength / Dosage (Optional, e.g., 2000 IU)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLength: OtcSupplement.maxNoteLength,
              decoration: const InputDecoration(
                labelText: 'Note (Optional, e.g., Take with dinner)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add to Cabinet',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
