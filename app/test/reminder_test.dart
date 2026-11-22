import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/medication_reminder.dart';

void main() {
  group('MedicationReminder', () {
    test('formats 12-hour times sorted chronologically', () {
      final reminder = MedicationReminder(
        rxcui: '1364430',
        drugName: 'Eliquis',
        dosage: '5 mg',
        times: const [
          ReminderTime(hour: 20, minute: 30),
          ReminderTime(hour: 8, minute: 0),
        ],
      );
      expect(reminder.formattedTimesSummary, '8:00 AM, 8:30 PM');
      expect(reminder.notificationTitle, 'Time for Eliquis');
      expect(reminder.notificationBody, 'Scheduled reminder for Eliquis (5 mg).');
    });

    test('hides drug name when discreetLockScreen is enabled', () {
      const reminder = MedicationReminder(
        rxcui: '855333',
        drugName: 'Mydayis',
        dosage: '37.5 mg',
        times: [ReminderTime(hour: 7, minute: 30)],
        discreetLockScreen: true,
      );
      expect(reminder.notificationTitle, 'Medication Reminder');
      expect(reminder.notificationBody.contains('Mydayis'), isFalse);
    });

    test('resets Taken Today automatically on a new day', () {
      final today = DateTime(2026, 11, 22, 9, 0);
      final tomorrow = DateTime(2026, 11, 23, 7, 0);
      final reminder = MedicationReminder(
        rxcui: '1364430',
        drugName: 'Eliquis',
        times: const [ReminderTime(hour: 8, minute: 0)],
        takenDate: MedicationReminder.todayKey(today),
      );
      expect(reminder.isTakenToday(today), isTrue);
      expect(reminder.isTakenToday(tomorrow), isFalse);
    });

    test('generates valid daily repeating ICS calendar content', () {
      const reminder = MedicationReminder(
        rxcui: '1364430',
        drugName: 'Eliquis',
        dosage: '5 mg',
        times: [ReminderTime(hour: 8, minute: 0)],
      );
      final ics = reminder.buildIcsContent(DateTime(2026, 11, 22, 7, 0));
      expect(ics.contains('BEGIN:VCALENDAR'), isTrue);
      expect(ics.contains('RRULE:FREQ=DAILY'), isTrue);
      expect(ics.contains('SUMMARY:Take Eliquis (5 mg)'), isTrue);
    });
  });
}
