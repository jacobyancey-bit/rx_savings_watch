import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/partner_links.dart';

class HomeFooterSection extends StatelessWidget {
  const HomeFooterSection({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedText = theme.colorScheme.onSurfaceVariant;
    final cardBg = theme.colorScheme.surfaceContainerLow;
    final borderColor = theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 104),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 18),

          // 1. Frequently Asked Questions
          Row(
            children: [
              Icon(Icons.help_outline, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Frequently Asked Questions',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildFaqItem(
                  context,
                  question: 'How do you verify whether a generic is really available?',
                  answer:
                      'We use a strict 2-signal verification check against official U.S. government databases. '
                      'A generic is only marked "Available Now" when BOTH (1) the FDA Orange Book confirms a therapeutically '
                      'equivalent generic or authorized generic for that exact brand formulation, AND (2) commercial pharmacy '
                      'distribution is confirmed in CMS NADAC pricing, OpenFDA NDC, or NLM DailyMed labeling.',
                ),
                const Divider(height: 1),
                _buildFaqItem(
                  context,
                  question: 'Why don\'t I need an account? How do I move my list to my phone?',
                  answer:
                      'To protect your medical privacy, your medication cabinet is stored only on your own device—never on our servers. '
                      'To move your list between your computer and phone, tap "Transfer" above to scan a private QR code or send yourself '
                      'a one-tap link. The link keeps your medication codes strictly in the # fragment, which browsers never send to any server.',
                ),
                const Divider(height: 1),
                _buildFaqItem(
                  context,
                  question: 'Are my pill bottle photos or prescription lists ever uploaded?',
                  answer:
                      'Never. When you scan a prescription bottle, optical text recognition runs 100% locally on your device, '
                      'all personal details (your name, doctor, Rx number, and pharmacy) are stripped immediately, and the photo '
                      'is wiped from memory right away. Update checks also mix in decoy maintenance drug codes so nobody can infer your list.',
                ),
                const Divider(height: 1),
                _buildFaqItem(
                  context,
                  question: 'Why might my pharmacy\'s price differ from the price shown?',
                  answer:
                      'Benchmark prices come from the federal CMS NADAC survey (National Average Drug Acquisition Cost), which reflects '
                      'what pharmacies pay to acquire a medication—not your specific insurance copay or retail markup. '
                      'Use the verified Cash & Coupon buttons on each medication page to check live out-of-pocket prices.',
                ),
                const Divider(height: 1),
                _buildFaqItem(
                  context,
                  question: 'Is Rx Savings Watch really free? How is it supported?',
                  answer:
                      'Yes—100% free, with zero ads and zero data selling. Rx Savings Watch is built independently by Dangling Dice Studios™ '
                      'and supported by optional referral fees on verified pharmacy links (at no cost to you) and an optional tip jar in Settings.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 2. Contact & Support
          Row(
            children: [
              Icon(Icons.support_agent_outlined, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Contact & Studio Info',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Published by Dangling Dice Studios™',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Have a question, feedback, or spot a medication entry that needs review? Reach out through our studio website or community support channel, or use the anonymous "See something wrong?" button on any medication page.',
                  style: TextStyle(fontSize: 13.5, color: mutedText, height: 1.4),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(PartnerLinks.studioWebsiteUrl),
                      icon: const Icon(Icons.language, size: 18),
                      label: const Text('Dangling Dice Studios'),
                    ),
                    OutlinedButton.icon(
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
                    TextButton.icon(
                      onPressed: () => _openUrl(PartnerLinks.privacyPolicyUrl),
                      icon: const Icon(Icons.privacy_tip_outlined, size: 17),
                      label: const Text('Privacy Policy'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openUrl(PartnerLinks.termsOfServiceUrl),
                      icon: const Icon(Icons.description_outlined, size: 17),
                      label: const Text('Terms of Service'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 3. Medical, Pricing & Affiliate Disclaimers
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerLowest
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: mutedText),
                    const SizedBox(width: 8),
                    Text(
                      'Important Disclaimers',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildDisclaimerParagraph(
                  'Medical Disclaimer: ',
                  'Rx Savings Watch is an independent informational tool and does not provide medical, clinical, or pharmacy advice. '
                  'Always consult your prescribing doctor or licensed pharmacist before starting, stopping, or switching any medication.',
                  mutedText,
                ),
                const SizedBox(height: 8),
                _buildDisclaimerParagraph(
                  'Data & Pricing Disclaimer: ',
                  'Generic availability, therapeutic equivalence ratings, shortages, and acquisition benchmarks are sourced from public U.S. '
                  'government datasets (FDA Orange Book, Drugs@FDA, OpenFDA NDC & Shortages, NLM RxNorm, DailyMed SPL, and CMS NADAC). '
                  'While we verify updates regularly, actual pharmacy availability, cash prices, and insurance coverage vary by location and plan.',
                  mutedText,
                ),
                const SizedBox(height: 8),
                _buildDisclaimerParagraph(
                  'Affiliate & Transparency Disclosure: ',
                  'As an Amazon Associate I earn from qualifying purchases. Some verified pharmacy or savings links may earn Dangling Dice Studios™ '
                  'a small referral fee at zero cost to you. No personal data is shared when you open an external link.',
                  mutedText,
                ),
                const SizedBox(height: 12),
                Text(
                  '© 2026 Dangling Dice Studios™ • Rx Savings Watch • Zero-PII Privacy Architecture',
                  style: TextStyle(fontSize: 12, color: mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem(
    BuildContext context, {
    required String question,
    required String answer,
  }) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Text(
        question,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
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
        style: TextStyle(fontSize: 12.5, color: color, height: 1.4),
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
}
