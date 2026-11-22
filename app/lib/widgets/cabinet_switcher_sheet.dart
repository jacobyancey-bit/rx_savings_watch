import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient_cabinet.dart';
import '../providers/cabinet_provider.dart';

class CabinetSwitcherSheet extends StatelessWidget {
  const CabinetSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CabinetSwitcherSheet(),
    );
  }

  Future<void> _showCreateOrEditDialog(
    BuildContext context, {
    PatientCabinet? existing,
  }) async {
    final initialColor = existing?.colorValue ??
        PatientCabinet.palette[
            context.read<CabinetProvider>().cabinets.length % PatientCabinet.palette.length];

    final result = await showDialog<(String, int)?>(
      context: context,
      builder: (_) => _CabinetEditorDialog(
        existing: existing,
        initialColor: initialColor,
      ),
    );

    if (result == null || !context.mounted) return;

    final provider = context.read<CabinetProvider>();
    if (existing == null) {
      final created = await provider.createCabinet(name: result.$1, colorValue: result.$2);
      if (created != null && context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Switched to ${created.headerTitle}')),
        );
      }
    } else {
      await provider.renameCabinet(existing.id, name: result.$1, colorValue: result.$2);
    }
  }

  Future<void> _confirmDelete(BuildContext context, PatientCabinet target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${target.headerTitle}?'),
        content: Text(
          'This will permanently remove ${target.drugs.length} '
          'medication${target.drugs.length == 1 ? '' : 's'} and any scheduled reminders in "${target.name}" from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<CabinetProvider>().deleteCabinet(target.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${target.name}" cabinet')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cabinet = context.watch<CabinetProvider>();
    final theme = Theme.of(context);
    final canAddMore = cabinet.cabinets.length < PatientCabinet.maxCabinets;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.people_outline_rounded, color: Colors.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medication Cabinets',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Manage separate lists & reminders for family or patients',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: cabinet.cabinets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, index) {
                final item = cabinet.cabinets[index];
                final isSelected = item.id == cabinet.activeCabinetId;
                final color = Color(item.colorValue);

                return Material(
                  color: isSelected
                      ? color.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await cabinet.switchCabinet(item.id);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? color : theme.colorScheme.outlineVariant,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: color,
                            child: Text(
                              item.name.isNotEmpty ? item.name[0].toUpperCase() : 'M',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${item.drugs.length} medication${item.drugs.length == 1 ? '' : 's'}'
                                  '${item.reminders.isNotEmpty ? ' • ${item.reminders.length} reminder${item.reminders.length == 1 ? '' : 's'}' : ''}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle, color: color, size: 22),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20),
                            onSelected: (action) {
                              if (action == 'edit') {
                                _showCreateOrEditDialog(context, existing: item);
                              } else if (action == 'delete') {
                                _confirmDelete(context, item);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Rename / Color'),
                              ),
                              if (cabinet.cabinets.length > 1)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete Cabinet',
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: canAddMore ? () => _showCreateOrEditDialog(context) : null,
              icon: const Icon(Icons.add),
              label: Text(
                canAddMore
                    ? 'Add Patient / Family Cabinet'
                    : 'Maximum ${PatientCabinet.maxCabinets} cabinets reached',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CabinetEditorDialog extends StatefulWidget {
  final PatientCabinet? existing;
  final int initialColor;

  const _CabinetEditorDialog({
    required this.existing,
    required this.initialColor,
  });

  @override
  State<_CabinetEditorDialog> createState() => _CabinetEditorDialogState();
}

class _CabinetEditorDialogState extends State<_CabinetEditorDialog> {
  late final TextEditingController _controller;
  late int _selectedColor;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing?.name ?? '');
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Patient Cabinet' : 'Edit Cabinet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: PatientCabinet.maxNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nickname (e.g., Mom, Dad, Spouse)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Color Tag',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: PatientCabinet.palette.map((colorVal) {
                final isSelected = _selectedColor == colorVal;
                return InkWell(
                  onTap: () => setState(() => _selectedColor = colorVal),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(colorVal),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2.5,
                            )
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Stored strictly on this device. Nicknames are never uploaded to any server.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final clean = PatientCabinet.sanitizeName(_controller.text, fallback: '');
            if (clean.isEmpty) return;
            Navigator.of(context).pop((clean, _selectedColor));
          },
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
