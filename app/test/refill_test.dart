import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/patient_cabinet.dart';
import 'package:rx_savings_watch/models/refill_info.dart';

void main() {
  group('RefillInfo model', () {
    test('calculates nextRefillDate, reminderDate, daysRemaining, and urgency accurately', () {
      final now = DateTime(2026, 11, 23);

      // Filled 10 days ago on a 30-day supply -> 20 days left -> ok
      final okRefill = RefillInfo(
        rxcui: '855333',
        drugName: 'Vyvanse',
        lastFilledDate: '2026-11-13',
        daySupply: 30,
        remindDaysBefore: 5,
        refillsRemaining: 2,
      );
      expect(okRefill.daysRemaining(now), 20);
      expect(okRefill.daysElapsed(now), 10);
      expect(okRefill.urgency(now), RefillUrgency.ok);
      expect(okRefill.statusLabel(now), 'Refill in 20d');
      expect(okRefill.nextRefillFormatted, 'Dec 13');
      expect(okRefill.needsDoctorRenewal, isFalse);

      // Filled 26 days ago on a 30-day supply -> 4 days left (<= 5 lead) -> dueSoon
      final dueSoon = okRefill.copyWith(lastFilledDate: '2026-10-28');
      expect(dueSoon.daysRemaining(now), 4);
      expect(dueSoon.urgency(now), RefillUrgency.dueSoon);
      expect(dueSoon.isDueOrOverdue(now), isTrue);
      expect(dueSoon.statusLabel(now), 'Refill in 4d');

      // Filled 32 days ago on a 30-day supply -> -2 days -> overdue
      final overdue = okRefill.copyWith(lastFilledDate: '2026-10-22');
      expect(overdue.daysRemaining(now), -2);
      expect(overdue.urgency(now), RefillUrgency.overdue);
      expect(overdue.statusLabel(now), 'Refill overdue (2d)');
    });

    test('markRefilledToday resets supply clock and decrements refillsRemaining to 0', () {
      final today = DateTime(2026, 11, 23);
      final initial = RefillInfo(
        rxcui: '1364430',
        drugName: 'Eliquis',
        lastFilledDate: '2026-10-25',
        daySupply: 30,
        remindDaysBefore: 5,
        refillsRemaining: 1,
      );

      final refilled = initial.markRefilledToday(today);
      expect(refilled.lastFilledDate, '2026-11-23');
      expect(refilled.daysRemaining(today), 30);
      expect(refilled.refillsRemaining, 0);
      expect(refilled.needsDoctorRenewal, isTrue);
      expect(refilled.notificationBody, contains('contact your prescriber'));
    });

    test('buildIcsContent generates valid RFC 5545 calendar event and round-trips JSON in PatientCabinet', () {
      final info = RefillInfo(
        rxcui: '855333',
        drugName: 'Vyvanse',
        cabinetLabel: 'Mom',
        lastFilledDate: '2026-11-01',
        daySupply: 30,
        remindDaysBefore: 5,
        refillsRemaining: 3,
      );

      final ics = info.buildIcsContent();
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('SUMMARY:Refill Reminder: Mom\'s Vyvanse'));
      expect(ics, contains('DTSTART:20261126T090000'));
      expect(ics, contains('BEGIN:VALARM'));

      final cabinet = PatientCabinet.emptyDefault(refills: {'855333': info});
      final decoded = PatientCabinet.fromJson(cabinet.toJson());
      expect(decoded.refills['855333']?.daySupply, 30);
      expect(decoded.refills['855333']?.refillsRemaining, 3);
      expect(decoded.refills['855333']?.cabinetLabel, 'Mom');
    });
  });
}
