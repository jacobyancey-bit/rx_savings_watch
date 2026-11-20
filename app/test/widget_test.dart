import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/pricing_info.dart';
import 'package:rx_savings_watch/widgets/savings_badge.dart';
import 'package:rx_savings_watch/widgets/signal_badges.dart';

void main() {
  group('Widget Tests', () {
    testWidgets('SignalBadges displays 2-Signal Verified when both satisfied', (tester) async {
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

      expect(find.text('2-Signal Verified'), findsOneWidget);
    });

    testWidgets('SignalBadges displays Brand Only when neither satisfied', (tester) async {
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

      expect(find.text('Brand Only'), findsOneWidget);
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
  });
}
