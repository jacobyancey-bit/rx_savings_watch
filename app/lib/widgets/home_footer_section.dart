import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/partner_links.dart';

/// Compact website-style bottom footer for the Home Screen.
/// Keeps the main screen uncluttered while keeping essential disclaimers visible
/// and giving one-tap access to full FAQs, Contact info, and Disclaimers.
class HomeFooterSection extends StatelessWidget {
  const HomeFooterSection({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showFaqsSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _buildSheetHeader(ctx, Icons.help_outline, 'Frequently Asked Questions'),
            const SizedBox(height: 8),
            _buildFaqTile(
              theme,
              'How do you verify whether a generic is really available?',
              'We use a strict 2-signal verification check against official U.S. government databases. '
                  'A generic is only marked "Available Now" when BOTH (1) the FDA Orange Book confirms a therapeutically '
                  'equivalent generic or authorized generic for that exact brand formulation, AND (2) commercial pharmacy '
                  'distribution is confirmed in CMS NADAC pricing, OpenFDA NDC, or NLM DailyMed labeling.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Why don\'t I need an account? How do I move my list to my phone?',
              'To protect your medical privacy, your medication cabinet is stored only on your own device—never on our servers. '
                  'Tap "Transfer" next to your cabinet to scan a private QR code or send yourself a one-tap link. '
                  'The link keeps your medication codes strictly in the # fragment, which browsers never send to any server.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Are my pill bottle photos or prescription lists ever uploaded?',
              'Never. When you scan a prescription bottle, optical text recognition runs 100% locally on your device, '
                  'all personal details (your name, doctor, Rx number, and pharmacy) are stripped immediately, and the photo '
                  'is wiped from memory right away. Update checks also mix in decoy maintenance drug codes.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Why might my pharmacy\'s price differ from the price shown?',
              'Benchmark prices come from the federal CMS NADAC survey (what pharmacies pay to acquire a medication), '
                  'not your specific insurance copay or retail markup. Use the verified Cash & Coupon buttons on each '
                  'medication page to check live out-of-pocket prices.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Is Rx Savings Watch really free? How is it supported?',
              'Yes—100% free, with zero ads and zero data selling. Rx Savings Watch is built independently by '
                  'Dangling Dice Studios™ and supported by optional referral fees on verified pharmacy links (at no cost to you) '
                  'and an optional tip jar in Settings.',
            ),
          ],
        ),
      ),
    );
  }

  void _showContactSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSheetHeader(ctx, Icons.support_agent_outlined, 'Contact & Support'),
            const SizedBox(height: 10),
            Text(
              'Published by Dangling Dice Studios™',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Have a question, feedback, or spot a medication entry that needs review? Reach out through our studio website or Discord, or use the anonymous "See something wrong?" button on any medication page.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _openUrl(PartnerLinks.studioWebsiteUrl),
                  icon: const Icon(Icons.language, size: 18),
                  label: const Text('Dangling Dice Studios'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openUrl(PartnerLinks.supportDiscordUrl),
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Support Discord'),
                ),
                if (PartnerLinks.supportEmail.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _openUrl(
                      'mailto:${PartnerLinks.supportEmail}?subject=Rx%20Savings%20Watch%20Support',
                    ),
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('Email Support'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDisclaimersSheet(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSheetHeader(ctx, Icons.info_outline, 'Important Disclaimers'),
              const SizedBox(height: 12),
              _buildDisclaimerParagraph(
                'Medical Disclaimer: ',
                'Rx Savings Watch is an independent informational tool and does not provide medical, clinical, or pharmacy advice. '
                    'Always consult your prescribing doctor or licensed pharmacist before starting, stopping, or switching any medication.',
                muted,
              ),
              const SizedBox(height: 12),
              _buildDisclaimerParagraph(
                'Data & Pricing Disclaimer: ',
                'Generic availability, therapeutic equivalence ratings, shortages, and acquisition benchmarks are sourced from public U.S. '
                    'government datasets (FDA Orange Book, Drugs@FDA, OpenFDA NDC & Shortages, NLM RxNorm, DailyMed SPL, and CMS NADAC). '
                    'Actual pharmacy stock, cash prices, and insurance copays vary by pharmacy, dosage, and plan.',
                muted,
              ),
              const SizedBox(height: 12),
              _buildDisclaimerParagraph(
                'Affiliate & Transparency Disclosure: ',
                'As an Amazon Associate I earn from qualifying purchases. Some verified pharmacy or savings links may earn Dangling Dice Studios™ '
                    'a small referral fee at zero cost to you. No personal data is shared when you open an external link.',
                muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetHeader(BuildContext context, IconData icon, String title) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFaqTile(ThemeData theme, String question, String answer) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: Text(
        question,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            answer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimerParagraph(String heading, String body, Color color) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 13.5, color: color, height: 1.45),
        children: [
          TextSpan(
            text: heading,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: body),
        ],
      ),
    );
  }

  Widget _footerLink(BuildContext context, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              _footerLink(context, 'FAQs', () => _showFaqsSheet(context)),
              Text('•', style: TextStyle(color: muted, fontSize: 12)),
              _footerLink(context, 'Contact', () => _showContactSheet(context)),
              Text('•', style: TextStyle(color: muted, fontSize: 12)),
              _footerLink(context, 'Disclaimers', () => _showDisclaimersSheet(context)),
              Text('•', style: TextStyle(color: muted, fontSize: 12)),
              _footerLink(context, 'Privacy', () => _openUrl(PartnerLinks.privacyPolicyUrl)),
              Text('•', style: TextStyle(color: muted, fontSize: 12)),
              _footerLink(context, 'Terms', () => _openUrl(PartnerLinks.termsOfServiceUrl)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Informational only — not medical advice. Verify with your doctor or pharmacist. '
            'As an Amazon Associate I earn from qualifying purchases.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted, height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(
            '© 2026 Dangling Dice Studios™ • Official FDA, RxNorm & CMS Data',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}
