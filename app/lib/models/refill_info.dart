enum RefillUrgency {
  ok,
  dueSoon,
  overdue,
}

/// Strictly on-device prescription refill tracker (zero PHI ever leaves the device).
class RefillInfo {
  final String rxcui;
  final String drugName;
  final String? cabinetLabel;
  final String lastFilledDate; // YYYY-MM-DD local date
  final int daySupply; // 1..365 (typically 30, 60, or 90)
  final int remindDaysBefore; // 0..30 (default 5)
  final int? refillsRemaining; // Optional 0..99
  final bool enabled;

  const RefillInfo({
    required this.rxcui,
    required this.drugName,
    this.cabinetLabel,
    required this.lastFilledDate,
    this.daySupply = 30,
    this.remindDaysBefore = 5,
    this.refillsRemaining,
    this.enabled = true,
  });

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String todayKey([DateTime? now]) => dateKey(now ?? DateTime.now());

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime parseDate(String yyyyMmDd) {
    final parts = yyyyMmDd.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
    }
    return _midnight(DateTime.now());
  }

  static String formatShortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  DateTime get lastFilled => parseDate(lastFilledDate);

  /// Uses calendar-day arithmetic so Daylight Saving Time transitions never shift dates by 1 day.
  DateTime get nextRefillDate => DateTime(
        lastFilled.year,
        lastFilled.month,
        lastFilled.day + daySupply.clamp(1, 365),
      );

  DateTime get reminderDate => DateTime(
        nextRefillDate.year,
        nextRefillDate.month,
        nextRefillDate.day - remindDaysBefore.clamp(0, 30),
      );

  int daysRemaining([DateTime? now]) {
    final d = now ?? DateTime.now();
    final todayUtc = DateTime.utc(d.year, d.month, d.day);
    final next = nextRefillDate;
    final nextUtc = DateTime.utc(next.year, next.month, next.day);
    return nextUtc.difference(todayUtc).inDays;
  }

  int daysElapsed([DateTime? now]) {
    final d = now ?? DateTime.now();
    final todayUtc = DateTime.utc(d.year, d.month, d.day);
    final last = lastFilled;
    final lastUtc = DateTime.utc(last.year, last.month, last.day);
    final supply = daySupply.clamp(1, 365);
    return todayUtc.difference(lastUtc).inDays.clamp(0, supply);
  }

  double supplyProgress([DateTime? now]) {
    final supply = daySupply.clamp(1, 365);
    return (daysElapsed(now) / supply).clamp(0.0, 1.0);
  }

  RefillUrgency urgency([DateTime? now]) {
    final rem = daysRemaining(now);
    if (rem <= 0) return RefillUrgency.overdue;
    if (rem <= remindDaysBefore.clamp(0, 30)) return RefillUrgency.dueSoon;
    return RefillUrgency.ok;
  }

  bool isDueOrOverdue([DateTime? now]) => urgency(now) != RefillUrgency.ok;

  bool get needsDoctorRenewal => refillsRemaining != null && refillsRemaining! <= 0;

  String statusLabel([DateTime? now]) {
    final rem = daysRemaining(now);
    if (rem < 0) return 'Refill overdue (${-rem}d)';
    if (rem == 0) return 'Refill due today';
    if (rem == 1) return 'Refill tomorrow';
    return 'Refill in ${rem}d';
  }

  String get nextRefillFormatted => formatShortDate(nextRefillDate);

  String get lastFilledFormatted => formatShortDate(lastFilled);

  String get notificationTitle {
    final prefix = cabinetLabel != null && cabinetLabel!.trim().isNotEmpty
        ? "${cabinetLabel!.trim()}'s "
        : '';
    return 'Refill Reminder: $prefix$drugName';
  }

  String get notificationBody {
    if (needsDoctorRenewal) {
      return 'Supply runs out on $nextRefillFormatted with 0 refills left — contact your prescriber to renew.';
    }
    final leftText = refillsRemaining != null ? ' ($refillsRemaining refills left)' : '';
    return 'Your $daySupply-day supply runs out on $nextRefillFormatted$leftText. Request a pharmacy refill soon.';
  }

  RefillInfo markRefilledToday([DateTime? now]) {
    final nextRemaining = refillsRemaining == null
        ? null
        : (refillsRemaining! > 0 ? refillsRemaining! - 1 : 0);
    return copyWith(
      lastFilledDate: todayKey(now),
      refillsRemaining: nextRemaining,
    );
  }

  String buildIcsContent() {
    final target = reminderDate;
    final y = target.year.toString().padLeft(4, '0');
    final m = target.month.toString().padLeft(2, '0');
    final d = target.day.toString().padLeft(2, '0');
    final dtStart = '${y}${m}${d}T090000';
    final dtEnd = '${y}${m}${d}T091500';
    final safeName = _escapeIcs(notificationTitle);
    final safeDesc = _escapeIcs(notificationBody);
    final uid = 'rxsw-refill-$rxcui-$y$m$d@rxsavingswatch.local';

    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Rx Savings Watch//Refill Tracker//EN',
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTART:$dtStart',
      'DTEND:$dtEnd',
      'SUMMARY:$safeName',
      'DESCRIPTION:$safeDesc',
      'BEGIN:VALARM',
      'TRIGGER:-PT0M',
      'ACTION:DISPLAY',
      'DESCRIPTION:$safeName',
      'END:VALARM',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');
  }

  static String _escapeIcs(String raw) => raw
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  RefillInfo copyWith({
    String? drugName,
    String? cabinetLabel,
    bool clearCabinetLabel = false,
    String? lastFilledDate,
    int? daySupply,
    int? remindDaysBefore,
    int? refillsRemaining,
    bool clearRefillsRemaining = false,
    bool? enabled,
  }) {
    return RefillInfo(
      rxcui: rxcui,
      drugName: drugName ?? this.drugName,
      cabinetLabel: clearCabinetLabel ? null : (cabinetLabel ?? this.cabinetLabel),
      lastFilledDate: lastFilledDate ?? this.lastFilledDate,
      daySupply: (daySupply ?? this.daySupply).clamp(1, 365),
      remindDaysBefore: (remindDaysBefore ?? this.remindDaysBefore).clamp(0, 30),
      refillsRemaining: clearRefillsRemaining
          ? null
          : (refillsRemaining ?? this.refillsRemaining)?.clamp(0, 99),
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'rxcui': rxcui,
        'drug_name': drugName,
        if (cabinetLabel != null) 'cabinet_label': cabinetLabel,
        'last_filled_date': lastFilledDate,
        'day_supply': daySupply,
        'remind_days_before': remindDaysBefore,
        if (refillsRemaining != null) 'refills_remaining': refillsRemaining,
        'enabled': enabled,
      };

  factory RefillInfo.fromJson(Map<String, dynamic> json) {
    return RefillInfo(
      rxcui: json['rxcui']?.toString() ?? '',
      drugName: json['drug_name']?.toString() ?? 'Medication',
      cabinetLabel: json['cabinet_label']?.toString(),
      lastFilledDate: json['last_filled_date']?.toString() ?? todayKey(),
      daySupply: (json['day_supply'] as num?)?.toInt().clamp(1, 365) ?? 30,
      remindDaysBefore: (json['remind_days_before'] as num?)?.toInt().clamp(0, 30) ?? 5,
      refillsRemaining: (json['refills_remaining'] as num?)?.toInt().clamp(0, 99),
      enabled: json['enabled'] != false,
    );
  }
}
