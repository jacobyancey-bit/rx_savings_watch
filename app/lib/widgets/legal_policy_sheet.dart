import 'package:flutter/material.dart';
import '../config/partner_links.dart';
import '../services/external_nav_service.dart';

/// Clean, scrollable in-app sheets for Privacy Policy, Terms of Service,
/// and Medical Disclaimer so users on both Web and Android can read the full
/// policies immediately without popup blockers or broken external redirects.
class LegalPolicySheet {
  static void showPrivacyPolicy(BuildContext context) {
    _showSheet(
      context,
      icon: Icons.privacy_tip_outlined,
      title: 'Privacy Policy & Consumer Health Data Notice',
      // Keep in sync with the hosted policy (docs/play_store/privacy_policy.md) and the
      // Play Console Data Safety answers (docs/play_store/play_store_listing.md).
      effectiveDate: 'Effective: November 27, 2026 • Published by Dangling Dice Studios™',
      sections: const [
        (
          '1. No Accounts — Your List Stays on Your Device',
          'Rx Savings Watch never asks you to create an account or give your name, email, phone number, or insurance ID. '
              'Your medication cabinets and caregiver cabinet names, OTC supplements, reminders, "Taken Today" logs, refill dates, '
              'the copay you type into the savings calculator, your saved ZIP code, and your settings are stored only on your device '
              '(phone storage, or browser storage on the website). Erase them anytime in Settings → Erase My Medication List.'
        ),
        (
          '2. What Is Sent to Our Server',
          '• Update checks: the public drug codes (RxCUIs) in your active cabinet, plus a few decoy common medications, to return '
              'current FDA generic, shortage, and price status. Not stored.\n'
              '• Searches: the medication name you search for. Your search text is never saved.\n'
              '• Savings options: the drug code for the medication you open. Not stored.\n'
              '• Data-quality reports (only if you send one): a drug code and an issue category. Stored without any information about who sent it.\n'
              '• Optional ZIP: only the 5-digit ZIP (never your medication), to list licensed pharmacies from the public CMS NPI Registry. Not stored or linked to you.\n'
              '• Sponsored pharmacy taps: which sponsored pharmacy and whether you tapped Call, Transfer, or Website. Kept only as a running total per pharmacy.\n'
              '• Reviews (only if you send one): your star rating, category, message, and platform. Stored privately, emailed to our '
              'support inbox via our email provider (Resend), and never shown publicly. Please do not include personal or health details.\n'
              'None of these requests include a name, account, or device ID. Searches and lookups are sent in POST bodies, so drug '
              'names and codes do not appear in URL logs.'
        ),
        (
          '3. IP Addresses & Aggregate Counts',
          'Our server and hosting provider (Railway) receive your IP address when the app connects. We use it only temporarily, '
              'in memory, for rate limiting, abuse prevention, and to avoid double-counting sponsored-pharmacy taps (up to 24 hours). '
              'We do not store IP addresses in our database or link them to drug codes, searches, ZIP codes, or reviews. We also keep '
              'daily totals (such as number of searches) that contain no information about individual users.'
        ),
        (
          '4. Camera & QR Transfer Scanner (Android)',
          'The QR scanner used to move your cabinet between devices processes camera images on your device. Images are never saved '
              'or uploaded by us. The scanner uses Google ML Kit, which may send Google diagnostic and usage information: device '
              'and app details, performance metrics, error codes, and a per-installation identifier not intended to identify you. '
              'This only happens when you use the scanner.'
        ),
        (
          '5. Sponsored Listings (Ads)',
          'Listings labeled "Sponsored Local Partner (Ad)" are local pharmacies that pay a flat monthly fee to appear for specific ZIP codes. '
              'They are chosen only by the ZIP you enter, never by your medications or any profile of you. We use no ad networks, '
              'advertising IDs, analytics SDKs, or tracking cookies.'
        ),
        (
          '6. External Links & Website Features',
          'Pharmacy and coupon links (such as Cost Plus Drugs, Amazon Pharmacy, SingleCare, and GoodRx) open that site under its own '
              'privacy policy. We send no personal or device IDs and ask your browser not to send referrer information. Amazon links '
              'carry our Associates tag only. On the website, optional browser notifications store a push subscription from your '
              'browser so we can send public generic-launch alerts (the same for everyone). The optional tip jar is handled by Buy Me a Coffee.'
        ),
        (
          '7. Consumer Health Data Notice (WA / NV / US)',
          'We do not sell or rent consumer health data, share it for advertising, or build profiles from it. We never request GPS '
              'location or use geofencing around pharmacies or medical facilities. Rx Savings Watch is not a HIPAA-covered entity '
              'and is not directed to children under 13.'
        ),
        (
          '8. Retention, Deletion & Your Rights',
          'On-device data is kept until you erase it. Reviews are kept until no longer needed or until you ask us to delete them. '
              'Data-quality reports and daily totals contain no information about who sent them. To request deletion of a review or '
              'exercise privacy rights (for example under California or EU/UK law), email ${PartnerLinks.supportEmail}. Because there '
              'are no accounts, tell us roughly when you sent a review and what it said so we can find it.'
        ),
        (
          '9. Full Policy & Contact',
          'Full privacy policy: ${PartnerLinks.privacyPolicyUrl}\n'
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
          '3. Independent App — Public Data Sources (Not a Government Entity)',
          'Rx Savings Watch is an independent application developed by Dangling Dice Studios™ and does NOT represent, '
              'nor is it affiliated with or endorsed by, the U.S. Food and Drug Administration (FDA), Centers for Medicare & '
              'Medicaid Services (CMS), National Institutes of Health (NIH), HHS, or any government entity. '
              'Public medication data is sourced from: FDA Orange Book (https://www.accessdata.fda.gov/scripts/cder/ob/), '
              'Drugs@FDA (https://www.accessdata.fda.gov/scripts/cder/daf/), openFDA (https://open.fda.gov/), '
              'FDA Drug Shortages (https://www.accessdata.fda.gov/scripts/drugshortages/), NIH DailyMed (https://dailymed.nlm.nih.gov/), '
              'NIH RxNorm (https://www.nlm.nih.gov/research/umls/rxnorm/), CMS NADAC (https://data.medicaid.gov/), and '
              'CMS NPI Registry (https://npiregistry.cms.hhs.gov/). '
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
        (
          'Not a Government Entity',
          'Rx Savings Watch is an independent tool built by Dangling Dice Studios™. It does not represent the FDA, CMS, '
              'NIH, HHS, or any U.S. government agency. All federal medication records are retrieved from publicly available '
              '.gov sources listed under Government Data Sources.'
        ),
      ],
    );
  }

  static void showGovernmentDataSources(BuildContext context) {
    final theme = Theme.of(context);
    const sources = <(String, String, String)>[
      (
        'FDA Orange Book',
        'Approved drug products & therapeutic equivalence evaluations',
        'https://www.accessdata.fda.gov/scripts/cder/ob/',
      ),
      (
        'Drugs@FDA',
        'FDA-approved prescription and over-the-counter drug catalog',
        'https://www.accessdata.fda.gov/scripts/cder/daf/',
      ),
      (
        'openFDA (NDC & Shortages)',
        'Public FDA National Drug Code directory & shortage APIs',
        'https://open.fda.gov/',
      ),
      (
        'FDA Drug Shortages',
        'Current and resolved medication supply shortages',
        'https://www.accessdata.fda.gov/scripts/drugshortages/',
      ),
      (
        'NIH / NLM DailyMed',
        'Structured Product Labeling (SPL) & drug listings',
        'https://dailymed.nlm.nih.gov/',
      ),
      (
        'NIH / NLM RxNorm',
        'Standardized clinical drug nomenclature & RxCUI mappings',
        'https://www.nlm.nih.gov/research/umls/rxnorm/',
      ),
      (
        'CMS NADAC (Medicaid.gov)',
        'National Average Drug Acquisition Cost pharmacy benchmarks',
        'https://data.medicaid.gov/',
      ),
      (
        'CMS NPI Registry',
        'Public directory of licensed U.S. retail pharmacies by ZIP code',
        'https://npiregistry.cms.hhs.gov/',
      ),
    ];

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
                Icon(Icons.account_balance_outlined, color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Government Data Sources & Disclaimer',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Independent App • Dangling Dice Studios™',
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                'Non-Government Disclaimer: Rx Savings Watch is an independent application developed by Dangling Dice Studios™. '
                'This app does NOT represent a government entity and is NOT affiliated with, endorsed by, or authorized by the FDA, '
                'CMS, NIH, HHS, or any U.S. government agency. All government information displayed in this app is aggregated solely '
                'from the official public U.S. government (.gov) sources below.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 16),
            for (final (name, desc, url) in sources)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(desc, style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text(
                        url,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => ExternalNavService.openUrl(url),
                ),
              ),
            const SizedBox(height: 8),
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
