import 'drug.dart';

class OtcSupplement {
  static const int maxNameLength = 48;
  static const int maxDosageLength = 32;
  static const int maxNoteLength = 80;
  static const int maxPerCabinet = 40;

  static const List<(String, String)> commonPresets = [
    ('Vitamin D3', '2000 IU'),
    ('Magnesium', '400 mg'),
    ('Fish Oil', '1000 mg'),
    ('Multivitamin', '1 tablet'),
    ('Vitamin B12', '1000 mcg'),
    ('Calcium', '500 mg'),
    ('Melatonin', '5 mg'),
    ('Aspirin', '81 mg'),
  ];

  final String id; // Always prefixed with "otc_" — never sent to server
  final String name;
  final String? dosage;
  final String? note;

  const OtcSupplement({
    required this.id,
    required this.name,
    this.dosage,
    this.note,
  });

  static String sanitizeText(String raw, int maxLen) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > maxLen) {
      return cleaned.substring(0, maxLen).trim();
    }
    return cleaned;
  }

  String get subtitle {
    final parts = <String>[];
    if (dosage != null && dosage!.trim().isNotEmpty) parts.add(dosage!.trim());
    if (note != null && note!.trim().isNotEmpty) parts.add(note!.trim());
    return parts.join(' • ');
  }

  /// Lightweight adapter so ReminderSheet can schedule reminders for OTC items
  /// without duplicating any reminder UI or alarm code.
  Drug toReminderDrug() {
    return Drug(
      rxcui: id,
      brandName: name,
      genericName: dosage != null && dosage!.isNotEmpty ? dosage! : 'OTC / Supplement',
      drugType: 'otc_supplement',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dosage': dosage,
        'note': note,
      };

  factory OtcSupplement.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim() ?? '';
    final safeId = rawId.startsWith('otc_') ? rawId : 'otc_$rawId';
    final name = sanitizeText(json['name']?.toString() ?? '', maxNameLength);
    final rawDosage = json['dosage']?.toString() ?? '';
    final rawNote = json['note']?.toString() ?? '';
    final dosage = sanitizeText(rawDosage, maxDosageLength);
    final note = sanitizeText(rawNote, maxNoteLength);
    return OtcSupplement(
      id: safeId.length > 4 ? safeId : 'otc_${DateTime.now().microsecondsSinceEpoch}',
      name: name.isNotEmpty ? name : 'Supplement',
      dosage: dosage.isNotEmpty ? dosage : null,
      note: note.isNotEmpty ? note : null,
    );
  }
}
