import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../config/partner_links.dart';
import '../services/external_nav_service.dart';
import 'legal_policy_sheet.dart';
import 'privacy_promise_sheet.dart';
import 'review_sheet.dart';

/// Compact website-style bottom footer for the Home Screen.
/// Keeps the main screen uncluttered while keeping essential disclaimers visible
/// and giving one-tap access to full FAQs, Contact info, and Disclaimers.
class HomeFooterSection extends StatelessWidget {
  final bool pinned;

  const HomeFooterSection({super.key, this.pinned = false});

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
              'How does Rx Savings Watch work?',
              'Add your prescriptions to your private cabinet to see whether a lower-cost FDA-approved generic is available, '
                  'compare cash and pharmacy coupon prices, track refill dates, set daily dose reminders, and get alerts if a '
                  'medication enters an FDA supply shortage.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'How do I track when my prescriptions need a refill?',
              'When you add a prescription (or tap "Track Refill" on any card), enter your last filled date, day supply '
                  '(30, 60, or 90 days), and optionally how many refills remain. The app counts down your supply, highlights '
                  'prescriptions due soon, warns you when 0 refills are left so you can contact your prescriber, and lets you '
                  'reset the clock with one tap on "Mark Refilled."',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'How do the pharmacy coupons and cash prices work? Do I need insurance?',
              'On any medication page, you can compare transparent cash pharmacies (like Cost Plus Drugs and Amazon Pharmacy) '
                  'and free retail coupons (SingleCare, GoodRx, Optum Perks, and WellRx) with no account required. '
                  'These are cash-pay discounts—not insurance—and cannot be combined with Medicare, Medicaid, or commercial insurance, '
                  'though they are sometimes lower than an insurance copay.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'How does the optional ZIP code work? Do you track my location?',
              'No—we never ask for GPS location or use geofencing. Entering a 5-digit ZIP code on a medication page is completely '
                  'optional and is saved on your own device. To show licensed pharmacies near you, the app sends ONLY that 5-digit ZIP '
                  '(never your medication) to our server, which looks it up in the public CMS NPI Registry. The ZIP is not stored or '
                  'linked to you.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Can my pharmacist switch me to a generic automatically?',
              'For most FDA-approved small-molecule generics, your pharmacist can usually substitute the generic automatically '
                  'unless your doctor specified "Dispense as Written." Certain brand-name or biologic medications require a new '
                  'prescription from your doctor. Tap "Show Doctor / Pharmacist Card" on any drug page for a clean handout to show at your visit.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Can I manage medications for a parent, spouse, or family member?',
              'Yes. Open the Cabinets switcher in the sidebar (or tap the cabinet title on mobile) to create separate color-coded '
                  'cabinets—such as "Mom" or "Dad." Each cabinet keeps its own prescriptions, OTC supplements, dose reminders, and refill dates completely separate.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'What if my prescription or vitamin is not in the initial catalog?',
              'Just type the medication name in Search—if it is not already in the top catalog, tap "Search Public FDA Databases" '
                  'to look it up live from federal FDA and NLM RxNorm records (minor spelling typos are handled automatically). '
                  'For vitamins or over-the-counter items, tap "Add OTC / Supplement" to track them privately on your device.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Why don\'t I need an account? How do I move my list to another device?',
              'To protect your medical privacy, your medication cabinet, reminders, and refill dates are stored only on your own device—never on our servers. '
                  'Tap "Transfer" to scan a private QR code or copy a one-tap transfer link. '
                  'The link keeps medication codes strictly inside the # fragment, which browsers never send to any server.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'How do you protect my medical privacy?',
              'No accounts, no cookies, no ad SDKs, and no behavioral analytics. Your medication list is saved on your device. '
                  'To check for generic and shortage updates, the app sends public drug codes (RxCUIs) to our server without any '
                  'name, account, or device ID; these lookups use POST bodies so drug names never appear in URL logs, and update '
                  'checks add a few decoy common medications. You can erase all local data anytime in Settings.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Why might my pharmacy\'s price differ from the estimated cost shown?',
              'Estimated brand vs. generic cost gaps come from the federal CMS NADAC survey (what pharmacies pay to acquire a medication), '
                  'not your specific insurance copay or retail markup. Use the Cash & Pharmacy Price buttons on each '
                  'medication page to check live out-of-pocket prices.',
            ),
            const Divider(height: 1),
            _buildFaqTile(
              theme,
              'Is Rx Savings Watch really free? How is it supported?',
              'Yes—100% free, with no ad networks, no trackers, and no data selling (only clearly labeled sponsored local pharmacies). Rx Savings Watch is built independently by '
                  'Dangling Dice Studios™ and supported by optional referral fees on pharmacy links (at no cost to you) '
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
              'Have a question, feedback, or spot a medication entry that needs review? Reach out directly by email, or use the anonymous "See something wrong?" button on any medication page.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Link(
              uri: Uri.parse('mailto:${PartnerLinks.supportEmail}?subject=Rx%20Savings%20Watch%20Support'),
              target: LinkTarget.blank,
              builder: (context, followLink) => FilledButton.tonalIcon(
                onPressed: followLink,
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text(PartnerLinks.supportEmail),
              ),
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
                'Non-Government Disclaimer: ',
                'Rx Savings Watch is an independent application by Dangling Dice Studios™ and does NOT represent a government entity. '
                    'It is not affiliated with or endorsed by the FDA, CMS, NIH, or HHS.',
                muted,
              ),
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
                'Not Insurance & Cash-Pay Discounts: ',
                'Rx Savings Watch is not health insurance and does not operate a pharmacy or Discount Medical Plan Organization (DMPO). '
                    'Any pharmacy coupon or cash-price links apply to cash-pay transactions only and cannot be combined with Medicare, Medicaid, or commercial insurance.',
                muted,
              ),
              const SizedBox(height: 12),
              _buildDisclaimerParagraph(
                'Affiliate & Transparency Disclosure: ',
                'As an Amazon Associate I earn from qualifying purchases. Some verified pharmacy or savings links may earn Dangling Dice Studios™ '
                    'a small referral fee at zero cost to you. External pharmacy sites are governed by their own privacy policies.',
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
    // Minimum 48x48 dp touch target (Android accessibility / WCAG 2.5.5) for every legal link.
    return Semantics(
      link: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isDark = theme.brightness == Brightness.dark;

    final linksRow = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        _footerLink(context, 'FAQs', () => _showFaqsSheet(context)),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(context, 'Review', () => ReviewSheet.show(context)),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(context, 'Contact', () => _showContactSheet(context)),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(context, 'Disclaimers', () => _showDisclaimersSheet(context)),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(
          context,
          'Data Sources',
          () => LegalPolicySheet.showGovernmentDataSources(context),
        ),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(
          context,
          'Health Data Notice',
          () => PrivacyPromiseSheet.show(context),
        ),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(
          context,
          'Privacy',
          () => LegalPolicySheet.showPrivacyPolicy(context),
        ),
        Text('•', style: TextStyle(color: muted, fontSize: 12)),
        _footerLink(
          context,
          'Terms',
          () => LegalPolicySheet.showTermsOfService(context),
        ),
        // B2B partner sign-up (with Stripe checkout) is offered on the website only, never
        // inside the Android app, to keep the Play build clear of any external payment flows.
        if (kIsWeb) ...[
          Text('•', style: TextStyle(color: muted, fontSize: 12)),
          _footerLink(
            context,
            'For Pharmacies & Clinics',
            () => ExternalNavService.openUrl(
              'https://rx.dangling-dice-studios.com/partners',
              sameTab: true,
            ),
          ),
        ],
      ],
    );

    if (pinned) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131C1B) : const Color(0xFFFAFCFC),
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            linksRow,
            const SizedBox(height: 3),
            Text(
              'Independent app — not affiliated with FDA, CMS, NIH, or any government entity. Informational only. © 2026 Dangling Dice Studios™',
              textAlign: TextAlign.center,
              // Never truncate the non-government disclaimer, even at large text scales.
              softWrap: true,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          linksRow,
          const SizedBox(height: 6),
          Text(
            'Not a government app (not affiliated with FDA, CMS, or NIH). Informational only — not medical advice. '
            'As an Amazon Associate I earn from qualifying purchases.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted, height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(
            '© 2026 Dangling Dice Studios™ • Public .gov Data Sources',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}
