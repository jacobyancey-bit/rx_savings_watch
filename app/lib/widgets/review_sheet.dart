import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';

class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ReviewSheet(),
    );
  }

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  static const List<(String, String)> _categories = [
    ('general', 'General Review'),
    ('caregiver', 'Caregiver Feedback'),
    ('feature', 'Feature Idea'),
    ('bug', 'Bug Report'),
  ];

  final TextEditingController _messageController = TextEditingController();
  int _rating = 5;
  String _category = 'general';
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _messageController.text.trim();
    if (text.length < 3) {
      setState(() => _errorText = 'Please write a short comment before submitting.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final serverUrl = context.read<CabinetProvider>().serverUrl;
    final api = ApiService(baseUrl: serverUrl);
    final res = await api.submitReview(
      rating: _rating,
      category: _category,
      message: text,
    );

    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Thank you! Your review was sent privately to our team.'),
          backgroundColor: Colors.teal.shade700,
        ),
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorText = res.error ?? 'Could not send review right now.';
      });
    }
  }

  Future<void> _openDirectEmail() async {
    final stars = '★' * _rating + '☆' * (5 - _rating);
    final subject = Uri.encodeComponent('Rx Savings Watch Review ($stars)');
    final body = Uri.encodeComponent(_messageController.text.trim());
    final uri = Uri.parse('mailto:support@danglingdicestudios.com?subject=$subject&body=$body');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                Icon(Icons.rate_review_outlined, color: Colors.teal.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Leave a Review',
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
                      'Sent privately to our team at support@danglingdicestudios.com and never shown publicly. Please avoid sharing personal medical details.',
                      style: TextStyle(
                        fontSize: 12,
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
              'How has your experience been?',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                final filled = star <= _rating;
                return IconButton(
                  iconSize: 36,
                  onPressed: () => setState(() => _rating = star),
                  tooltip: '$star star${star == 1 ? '' : 's'}',
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled ? Colors.amber.shade700 : Colors.grey.shade400,
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (value, label) in _categories)
                  ChoiceChip(
                    label: Text(label),
                    selected: _category == value,
                    onSelected: (_) => setState(() => _category = value),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageController,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Your review or suggestion',
                hintText: 'Tell us what is working well or what would help you most...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 6),
              Text(
                _errorText!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _isSubmitting ? 'Sending...' : 'Send Private Review',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _openDirectEmail,
                child: const Text(
                  'Or email support@danglingdicestudios.com directly',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
