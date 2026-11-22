class ReminderTime {
  final int hour; // 0-23
  final int minute; // 0-59

  const ReminderTime({required this.hour, required this.minute});

  int get totalMinutes => hour * 60 + minute;

  String format12Hour() {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final minStr = minute.toString().padLeft(2, '0');
    return '$h12:$minStr $period';
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory ReminderTime.fromJson(Map<String, dynamic> json) {
    return ReminderTime(
      hour: (json['hour'] as num?)?.toInt().clamp(0, 23) ?? 8,
      minute: (json['minute'] as num?)?.toInt().clamp(0, 59) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

class MedicationReminder {
  final String rxcui;
  final String drugName;
  final String? dosage;
  final List<ReminderTime> times;
  final bool enabled;
  final bool discreetLockScreen;
  final String? takenDate; // YYYY-MM-DD local date

  const MedicationReminder({
    required this.rxcui,
    required this.drugName,
    this.dosage,
    required this.times,
    this.enabled = true,
    this.discreetLockScreen = false,
    this.takenDate,
  });

  static String todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  bool isTakenToday([DateTime? now]) => takenDate == todayKey(now);

  String get formattedTimesSummary {
    if (times.isEmpty) return 'No time set';
    final sorted = List<ReminderTime>.from(times)
      ..sort((a, b) => a.totalMinutes.compareTo(b.totalMinutes));
    return sorted.map((t) => t.format12Hour()).join(', ');
  }

  String get notificationTitle =>
      discreetLockScreen ? 'Medication Reminder' : 'Time for $drugName';

  String get notificationBody {
    if (discreetLockScreen) {
      return 'Time to take your scheduled medication.';
    }
    final dosePart = dosage != null && dosage!.trim().isNotEmpty ? ' ($dosage)' : '';
    return 'Scheduled reminder for $drugName$dosePart.';
  }

  MedicationReminder copyWith({
    String? drugName,
    String? dosage,
    List<ReminderTime>? times,
    bool? enabled,
    bool? discreetLockScreen,
    String? takenDate,
    bool clearTakenDate = false,
  }) {
    return MedicationReminder(
      rxcui: rxcui,
      drugName: drugName ?? this.drugName,
      dosage: dosage ?? this.dosage,
      times: times ?? this.times,
      enabled: enabled ?? this.enabled,
      discreetLockScreen: discreetLockScreen ?? this.discreetLockScreen,
      takenDate: clearTakenDate ? null : (takenDate ?? this.takenDate),
    );
  }

  /// Generates a standard RFC 5545 `.ics` file with repeating daily reminders
  /// for Apple Calendar, Google Calendar, and Outlook (100% local, zero server).
  String buildIcsContent([DateTime? now]) {
    final base = now ?? DateTime.now();
    final buf = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Dangling Dice Studios//Rx Savings Watch//EN');

    for (var i = 0; i < times.length; i++) {
      final t = times[i];
      var start = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      if (start.isBefore(base)) {
        start = start.add(const Duration(days: 1));
      }
      final end = start.add(const Duration(minutes: 15));
      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}T'
          '${d.hour.toString().padLeft(2, '0')}'
          '${d.minute.toString().padLeft(2, '0')}00';

      final summary = discreetLockScreen
          ? 'Medication Reminder'
          : 'Take $drugName${dosage != null && dosage!.isNotEmpty ? ' ($dosage)' : ''}';

      buf
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:rxsw-$rxcui-$i@dangling-dice-studios.com')
        ..writeln('DTSTART:${fmt(start)}')
        ..writeln('DTEND:${fmt(end)}')
        ..writeln('RRULE:FREQ=DAILY')
        ..writeln('SUMMARY:$summary')
        ..writeln('DESCRIPTION:Daily prescription reminder created privately by Rx Savings Watch.')
        ..writeln('BEGIN:VALARM')
        ..writeln('TRIGGER:PT0M')
        ..writeln('ACTION:DISPLAY')
        ..writeln('DESCRIPTION:$summary')
        ..writeln('END:VALARM')
        ..writeln('END:VEVENT');
    }

    buf.writeln('END:VCALENDAR');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'rxcui': rxcui,
        'drug_name': drugName,
        'dosage': dosage,
        'times': times.map((t) => t.toJson()).toList(),
        'enabled': enabled,
        'discreet_lock_screen': discreetLockScreen,
        'taken_date': takenDate,
      };

  factory MedicationReminder.fromJson(Map<String, dynamic> json) {
    final rawTimes = (json['times'] as List? ?? [])
        .whereType<Map>()
        .map((m) => ReminderTime.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return MedicationReminder(
      rxcui: json['rxcui']?.toString() ?? '',
      drugName: json['drug_name']?.toString() ?? 'Medication',
      dosage: json['dosage'] as String?,
      times: rawTimes,
      enabled: json['enabled'] as bool? ?? true,
      discreetLockScreen: json['discreet_lock_screen'] as bool? ?? false,
      takenDate: json['taken_date'] as String?,
    );
  }
}
