enum ReminderFrequency {
  daily,
  specificDays,
  monthly,
}

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
  final String? cabinetLabel;
  final ReminderFrequency frequency;
  final List<int> weekdays; // ISO 1=Mon .. 7=Sun (used when frequency == specificDays)
  final int dayOfMonth; // 1..28 (used when frequency == monthly)
  final List<ReminderTime> times;
  final bool enabled;
  final bool discreetLockScreen;
  final String? takenDate; // YYYY-MM-DD local date

  const MedicationReminder({
    required this.rxcui,
    required this.drugName,
    this.dosage,
    this.cabinetLabel,
    this.frequency = ReminderFrequency.daily,
    this.weekdays = const [DateTime.sunday],
    this.dayOfMonth = 1,
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

  static const Map<int, String> _shortDayNames = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  static const Map<int, String> _icsDayCodes = {
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };

  static String ordinalDay(int day) {
    final d = day.clamp(1, 28);
    if (d >= 11 && d <= 13) return '${d}th';
    switch (d % 10) {
      case 1:
        return '${d}st';
      case 2:
        return '${d}nd';
      case 3:
        return '${d}rd';
      default:
        return '${d}th';
    }
  }

  List<int> get normalizedWeekdays {
    final clean = weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
    return clean.isEmpty ? const [DateTime.sunday] : clean;
  }

  String get frequencySummary {
    switch (frequency) {
      case ReminderFrequency.daily:
        return 'Daily';
      case ReminderFrequency.specificDays:
        final days = normalizedWeekdays;
        if (days.length == 7) return 'Daily';
        if (days.length == 5 &&
            days.contains(DateTime.monday) &&
            days.contains(DateTime.tuesday) &&
            days.contains(DateTime.wednesday) &&
            days.contains(DateTime.thursday) &&
            days.contains(DateTime.friday)) {
          return 'Weekdays';
        }
        if (days.length == 2 &&
            days.contains(DateTime.saturday) &&
            days.contains(DateTime.sunday)) {
          return 'Weekends';
        }
        return days.map((d) => _shortDayNames[d] ?? 'Sun').join(', ');
      case ReminderFrequency.monthly:
        return 'Monthly (${ordinalDay(dayOfMonth)})';
    }
  }

  String get formattedTimesSummary {
    if (times.isEmpty) return 'No time set';
    final sorted = List<ReminderTime>.from(times)
      ..sort((a, b) => a.totalMinutes.compareTo(b.totalMinutes));
    return sorted.map((t) => t.format12Hour()).join(', ');
  }

  String get scheduleSummary {
    if (times.isEmpty) return 'No time set';
    if (frequency == ReminderFrequency.daily) return formattedTimesSummary;
    return '$frequencySummary • $formattedTimesSummary';
  }

  String get notificationTitle {
    if (discreetLockScreen) return 'Medication Reminder';
    final prefix = cabinetLabel != null && cabinetLabel!.trim().isNotEmpty
        ? "${cabinetLabel!.trim()}'s "
        : '';
    return 'Time for $prefix$drugName';
  }

  String get notificationBody {
    if (discreetLockScreen) {
      return 'Time to take your scheduled medication.';
    }
    final prefix = cabinetLabel != null && cabinetLabel!.trim().isNotEmpty
        ? "${cabinetLabel!.trim()}'s "
        : '';
    final dosePart = dosage != null && dosage!.trim().isNotEmpty ? ' ($dosage)' : '';
    return 'Scheduled reminder for $prefix$drugName$dosePart.';
  }

  MedicationReminder copyWith({
    String? drugName,
    String? dosage,
    String? cabinetLabel,
    bool clearCabinetLabel = false,
    ReminderFrequency? frequency,
    List<int>? weekdays,
    int? dayOfMonth,
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
      cabinetLabel: clearCabinetLabel ? null : (cabinetLabel ?? this.cabinetLabel),
      frequency: frequency ?? this.frequency,
      weekdays: weekdays ?? this.weekdays,
      dayOfMonth: (dayOfMonth ?? this.dayOfMonth).clamp(1, 28),
      times: times ?? this.times,
      enabled: enabled ?? this.enabled,
      discreetLockScreen: discreetLockScreen ?? this.discreetLockScreen,
      takenDate: clearTakenDate ? null : (takenDate ?? this.takenDate),
    );
  }

  /// Generates a standard RFC 5545 `.ics` file with repeating daily, weekly/specific-days,
  /// or monthly reminders for Apple Calendar, Google Calendar, and Outlook (100% local).
  String buildIcsContent([DateTime? now]) {
    final base = now ?? DateTime.now();
    final buf = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Dangling Dice Studios//Rx Savings Watch//EN');

    String rrule;
    switch (frequency) {
      case ReminderFrequency.daily:
        rrule = 'FREQ=DAILY';
        break;
      case ReminderFrequency.specificDays:
        final byDay = normalizedWeekdays.map((d) => _icsDayCodes[d] ?? 'SU').join(',');
        rrule = 'FREQ=WEEKLY;BYDAY=$byDay';
        break;
      case ReminderFrequency.monthly:
        rrule = 'FREQ=MONTHLY;BYMONTHDAY=${dayOfMonth.clamp(1, 28)}';
        break;
    }

    for (var i = 0; i < times.length; i++) {
      final t = times[i];
      DateTime start;
      if (frequency == ReminderFrequency.monthly) {
        final dom = dayOfMonth.clamp(1, 28);
        start = DateTime(base.year, base.month, dom, t.hour, t.minute);
        if (start.isBefore(base)) {
          final nextMonth = base.month == 12 ? 1 : base.month + 1;
          final nextYear = base.month == 12 ? base.year + 1 : base.year;
          start = DateTime(nextYear, nextMonth, dom, t.hour, t.minute);
        }
      } else if (frequency == ReminderFrequency.specificDays) {
        final targetDays = normalizedWeekdays;
        start = DateTime(base.year, base.month, base.day, t.hour, t.minute);
        for (var offset = 0; offset <= 7; offset++) {
          final candidate = start.add(Duration(days: offset));
          if (targetDays.contains(candidate.weekday) && !candidate.isBefore(base)) {
            start = candidate;
            break;
          }
        }
      } else {
        start = DateTime(base.year, base.month, base.day, t.hour, t.minute);
        if (start.isBefore(base)) {
          start = start.add(const Duration(days: 1));
        }
      }

      final end = start.add(const Duration(minutes: 15));
      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}T'
          '${d.hour.toString().padLeft(2, '0')}'
          '${d.minute.toString().padLeft(2, '0')}00';

      final prefix = cabinetLabel != null && cabinetLabel!.trim().isNotEmpty
          ? "${cabinetLabel!.trim()}'s "
          : '';
      final summary = discreetLockScreen
          ? 'Medication Reminder'
          : 'Take $prefix$drugName${dosage != null && dosage!.isNotEmpty ? ' ($dosage)' : ''}';

      buf
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:rxsw-$rxcui-$i@dangling-dice-studios.com')
        ..writeln('DTSTART:${fmt(start)}')
        ..writeln('DTEND:${fmt(end)}')
        ..writeln('RRULE:$rrule')
        ..writeln('SUMMARY:$summary')
        ..writeln('DESCRIPTION:Scheduled prescription reminder created privately by Rx Savings Watch.')
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
        'cabinet_label': cabinetLabel,
        'frequency': frequency.name,
        'weekdays': normalizedWeekdays,
        'day_of_month': dayOfMonth.clamp(1, 28),
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

    final freqName = json['frequency']?.toString();
    final frequency = ReminderFrequency.values.firstWhere(
      (f) => f.name == freqName,
      orElse: () => ReminderFrequency.daily,
    );

    final rawWeekdays = (json['weekdays'] as List? ?? const [DateTime.sunday])
        .whereType<num>()
        .map((n) => n.toInt())
        .where((d) => d >= 1 && d <= 7)
        .toList();

    final dom = ((json['day_of_month'] as num?)?.toInt() ?? 1).clamp(1, 28);

    return MedicationReminder(
      rxcui: json['rxcui']?.toString() ?? '',
      drugName: json['drug_name']?.toString() ?? 'Medication',
      dosage: json['dosage'] as String?,
      cabinetLabel: json['cabinet_label'] as String?,
      frequency: frequency,
      weekdays: rawWeekdays.isEmpty ? const [DateTime.sunday] : rawWeekdays,
      dayOfMonth: dom,
      times: rawTimes,
      enabled: json['enabled'] as bool? ?? true,
      discreetLockScreen: json['discreet_lock_screen'] as bool? ?? false,
      takenDate: json['taken_date'] as String?,
    );
  }
}
