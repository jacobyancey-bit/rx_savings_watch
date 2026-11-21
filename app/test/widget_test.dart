import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/pricing_info.dart';
import 'package:rx_savings_watch/widgets/privacy_promise_sheet.dart';
import 'package:rx_savings_watch/widgets/savings_badge.dart';
import 'package:rx_savings_watch/widgets/signal_badges.dart';

void main() {
  group('Widget Tests', () {
    testWidgets('SignalBadges displays Generic Available Now when both satisfied', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalBadges(
              hasApprovedGeneric: true,
              commercialGenericAvailable: true,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Generic Available Now'), findsOneWidget);
    });

    testWidgets('SignalBadges displays Brand Name Only when neither satisfied', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalBadges(
              hasApprovedGeneric: false,
              commercialGenericAvailable: false,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Brand Name Only'), findsOneWidget);
    });

    testWidgets('SavingsBadge renders percentage savings correctly', (tester) async {
      final pricing = PricingInfo(
        brandNadacUnitPrice: 10.0,
        genericNadacUnitPrice: 1.0,
        estimatedSavingsPct: 90.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavingsBadge(pricing: pricing),
          ),
        ),
      );

      expect(find.text('Save 90%'), findsOneWidget);
    });

    testWidgets('PrivacyTrustBanner renders zero-data indicator and opens promise sheet', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrivacyTrustBanner(),
          ),
        ),
      );

      expect(find.text('No Personal Data Collected'), findsOneWidget);
      await tester.tap(find.text('No Personal Data Collected'));
      await tester.pumpAndSettle();

      expect(find.text('Our Privacy Promise'), findsOneWidget);
      expect(find.text('Stored Only on Your Phone'), findsOneWidget);
    });
  });
}
