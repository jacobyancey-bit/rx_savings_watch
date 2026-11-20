class AlertEvent {
  final int? id;
  final String eventType;
  final String signalSummary;
  final Map<String, dynamic> details;
  final double confidenceScore;
  final String detectedAt;

  AlertEvent({
    this.id,
    required this.eventType,
    required this.signalSummary,
    required this.details,
    required this.confidenceScore,
    required this.detectedAt,
  });

  factory AlertEvent.fromJson(Map<String, dynamic> json) {
    return AlertEvent(
      id: json['id'] as int?,
      eventType: json['event_type'] as String? ?? 'unknown',
      signalSummary: json['signal_summary'] as String? ?? '',
      details: json['details'] is Map<String, dynamic>
          ? json['details'] as Map<String, dynamic>
          : {},
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 1.0,
      detectedAt: json['detected_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_type': eventType,
      'signal_summary': signalSummary,
      'details': details,
      'confidence_score': confidenceScore,
      'detected_at': detectedAt,
    };
  }
}
