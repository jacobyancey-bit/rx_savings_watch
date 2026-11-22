import 'drug.dart';
import 'medication_reminder.dart';
import 'otc_supplement.dart';

class PatientCabinet {
  static const String defaultId = 'default';
  static const String defaultName = 'My Cabinet';
  static const int maxNameLength = 32;
  static const int maxCabinets = 12;

  static const List<int> palette = [
    0xFF00796B, // Teal (default)
    0xFF3949AB, // Indigo
    0xFFD84315, // Deep Orange
    0xFF6A1B9A, // Purple
    0xFF1565C0, // Blue
    0xFF2E7D32, // Green
  ];

  final String id;
  final String name;
  final int colorValue;
  final List<Drug> drugs;
  final List<OtcSupplement> supplements;
  final Map<String, MedicationReminder> reminders;

  const PatientCabinet({
    required this.id,
    required this.name,
    this.colorValue = 0xFF00796B,
    this.drugs = const [],
    this.supplements = const [],
    this.reminders = const {},
  });

  bool get isDefault => id == defaultId;

  String get headerTitle {
    if (isDefault && name == defaultName) {
      return 'My Medication Cabinet';
    }
    return name.toLowerCase().endsWith('cabinet') ? name : "$name's Cabinet";
  }

  /// Strips control characters, trims whitespace, and enforces a safe max length.
  static String sanitizeName(String raw, {String fallback = defaultName}) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length > maxNameLength) {
      return cleaned.substring(0, maxNameLength).trim();
    }
    return cleaned;
  }

  static int sanitizeColor(int? value) {
    if (value != null && palette.contains(value)) return value;
    return palette.first;
  }

  factory PatientCabinet.emptyDefault({
    List<Drug> drugs = const [],
    List<OtcSupplement> supplements = const [],
    Map<String, MedicationReminder> reminders = const {},
  }) {
    return PatientCabinet(
      id: defaultId,
      name: defaultName,
      colorValue: palette.first,
      drugs: List<Drug>.from(drugs),
      supplements: List<OtcSupplement>.from(supplements),
      reminders: Map<String, MedicationReminder>.from(reminders),
    );
  }

  PatientCabinet copyWith({
    String? name,
    int? colorValue,
    List<Drug>? drugs,
    List<OtcSupplement>? supplements,
    Map<String, MedicationReminder>? reminders,
  }) {
    return PatientCabinet(
      id: id,
      name: name != null ? sanitizeName(name, fallback: this.name) : this.name,
      colorValue: colorValue != null ? sanitizeColor(colorValue) : this.colorValue,
      drugs: drugs ?? List<Drug>.from(this.drugs),
      supplements: supplements ?? List<OtcSupplement>.from(this.supplements),
      reminders: reminders ?? Map<String, MedicationReminder>.from(this.reminders),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color_value': colorValue,
        'drugs': drugs.map((d) => d.toJson()).toList(),
        'supplements': supplements.map((s) => s.toJson()).toList(),
        'reminders': reminders.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory PatientCabinet.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim() ?? '';
    final id = rawId.isEmpty ? defaultId : rawId;
    final name = sanitizeName(
      json['name']?.toString() ?? '',
      fallback: id == defaultId ? defaultName : 'Patient Cabinet',
    );
    final colorValue = sanitizeColor((json['color_value'] as num?)?.toInt());

    final rawDrugs = (json['drugs'] as List? ?? [])
        .whereType<Map>()
        .map((m) => Drug.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final rawSupplements = (json['supplements'] as List? ?? [])
        .whereType<Map>()
        .map((m) => OtcSupplement.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final rawReminders = <String, MedicationReminder>{};
    if (json['reminders'] is Map) {
      for (final entry in (json['reminders'] as Map).entries) {
        if (entry.value is Map) {
          rawReminders[entry.key.toString()] = MedicationReminder.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    return PatientCabinet(
      id: id,
      name: name,
      colorValue: colorValue,
      drugs: rawDrugs,
      supplements: rawSupplements,
      reminders: rawReminders,
    );
  }
}
