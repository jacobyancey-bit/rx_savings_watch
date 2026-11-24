import 'package:flutter/material.dart';
import '../config/partner_links.dart';

/// Clean, scrollable in-app sheets for Privacy Policy, Terms of Service,
/// and Medical Disclaimer so users on both Web and Android can read the full
/// policies immediately without popup blockers or broken external redirects.
class LegalPolicySheet {
  static void showPrivacyPolicy(BuildContext context) {
    _showSheet(
      context,
      icon: Icons.privacy_tip_outlined,
      title: 'Privacy Policy & Consumer Health Data Notice',
      effectiveDate: 'Effective: November 2026 • Published by Dangling Dice Studios™',
      sections: const [
        (
          '1. Zero Accounts & Local-Only Storage',
          'Rx Savings Watch does not require an account, login, email address, phone number, or insurance ID. '
              'Your medication cabinet, caregiver cabinet names, OTC supplements, daily reminders, "Taken Today" logs, '
              'refill dates, and optional 5-digit ZIP code are stored strictly on your own device (browser local storage or mobile storage) '
              'and are never uploaded to a cloud profile.'
        ),
        (
          '2. Zero Trackers, Cookies, or Ad SDKs',
          'We do not use third-party advertising SDKs, behavioral analytics (such as Google Analytics or Meta Pixel), '
              'cross-site tracking cookies, or device advertising identifiers. We record only anonymous, aggregate daily '
              'server counters (total visits, searches, and syncs) with no IP addresses, user IDs, or drug names attached.'
        ),
        (
          '3. Privacy-Hardened Lookups',
          'Medication searches and pharmacy partner lookups are sent in HTTP POST bodies rather than URL query strings '
              'so drug names and RxCUIs do not appear in standard URL access logs. Cabinet status checks also mix in decoy '
              'common medications (query chaffing) to obscure which drugs are in your cabinet. Standard hosting infrastructure '
              'processes transient network traffic solely to deliver responses.'
        ),
        (
          '4. Optional Local ZIP & External Pharmacy Links',
          'If you enter an optional 5-digit ZIP code, it stays strictly on your device and is never sent to our servers. '
              'If you choose to click an external pharmacy or coupon link (such as Cost Plus Drugs, Amazon Pharmacy, SingleCare, '
              'GoodRx, Optum Perks, or WellRx), your browser navigates directly to that third party under its own privacy policy. '
              'We send Referrer-Policy: no-referrer and never attach personal or device IDs to outbound links.'
        ),
        (
          '5. Consumer Health Data Notice (WA / NV / US)',
          'We do not sell, rent, share, or build profiles from consumer health data, and we never request GPS location '
              'or use geofencing around pharmacies or medical facilities. Because your data stays on your device, you can '
              'erase all saved data at any time in Settings.'
        ),
        (
          '6. Contact',
          'Questions about privacy? Email ${PartnerLinks.supportEmail}.'
        ),
      ],
    );
  }

  static void showTermsOfService(BuildContext context) {
    _showSheet(
      context,
      icon: Icons.description_outlined,
      title: 'Terms of Service',
      effectiveDate: 'Effective: November 2026 • Published by Dangling Dice Studios™',
      sections: const [
        (
          '1. Informational Tool Only — Not Medical Advice',
          'Rx Savings Watch is an independent informational reference, price/generic monitor, and personal reminder tool. '
              'It does not provide medical, clinical, diagnostic, or pharmacy advice. Always confirm prescriptions, dosages, '
              'generic substitutions, interactions, and refills with your prescribing doctor or licensed pharmacist.'
        ),
        (
          '2. Not Insurance & Cash-Pay Discounts',
          'Rx Savings Watch is not health insurance, a pharmacy, or a Discount Medical Plan Organization (DMPO). '
              'External cash-price and retail pharmacy coupon links apply to cash-pay transactions only and generally '
              'cannot be combined with Medicare, Medicaid, TRICARE, or commercial insurance.'
        ),
        (
          '3. Official Public Data & Pricing Estimates',
          'Generic availability, therapeutic equivalence ratings, shortages, and acquisition benchmarks come from public '
              'U.S. government datasets (FDA Orange Book, Drugs@FDA, OpenFDA, NLM RxNorm, DailyMed, and CMS NADAC). '
              'Actual pharmacy inventory, cash prices, and insurance copays vary by pharmacy, dosage, and plan.'
        ),
        (
          '4. Third-Party Links & Affiliate Disclosure',
          'As an Amazon Associate, Dangling Dice Studios™ earns from qualifying purchases. Some external pharmacy or '
              'savings links may earn a small referral fee at zero cost to you. We are not responsible for the pricing, '
              'availability, or privacy practices of third-party pharmacy websites.'
        ),
        (
          '5. As-Is Service & Limitation of Liability',
          'Rx Savings Watch is provided "as is" and "as available" without warranties of any kind. Do not rely solely '
              'on app reminders or refill countdowns for critical or life-sustaining medications. To the fullest extent '
              'permitted by law, Dangling Dice Studios™ is not liable for indirect or consequential damages arising from use of the app.'
        ),
        (
          '6. Contact',
          'Questions about these terms? Email ${PartnerLinks.supportEmail}.'
        ),
      ],
    );
  }

  static void showMedicalDisclaimer(BuildContext context) {
    _showSheet(
      context,
      icon: Icons.medical_information_outlined,
      title: 'Medical & Pricing Disclaimer',
      effectiveDate: 'Rx Savings Watch • Dangling Dice Studios™',
      sections: const [
        (
          'Not Medical Advice',
          'Rx Savings Watch is strictly an informational tool and does not provide medical advice, diagnosis, or treatment. '
              'Never start, stop, or change a prescription or dosage without consulting your licensed prescriber or pharmacist.'
        ),
        (
          'Verify Generic Substitutions',
          'Even when an FDA-approved generic or interchangeable biosimilar exists, state substitution laws, formulary '
              'rules, and narrow therapeutic index considerations vary. Always confirm with your pharmacist.'
        ),
        (
          'Not Insurance',
          'Estimated NADAC acquisition costs and external cash/coupon links are not insurance quotes. Actual out-of-pocket '
              'prices are set by the dispensing pharmacy or your health plan.'
        ),
      ],
    );
  }

  static void _showSheet(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String effectiveDate,
    required List<(String, String)> sections,
  }) {
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
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          children: [
            Center(
              child: Container(
                width: 40,
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
                Icon(icon, color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        effectiveDate,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            for (final (heading, body) in sections) ...[
              Text(
                heading,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
