class IncidentDomainException implements Exception {
  const IncidentDomainException(this.message);

  final String message;

  @override
  String toString() => 'IncidentDomainException: $message';
}

enum IncidentSeverity { sev1, sev2, sev3, sev4 }

enum IncidentStatus { declared, acknowledged, mitigated, resolved }

enum TimelineKind {
  incidentCreated,
  statusChanged,
  noteAdded,
  responderAssigned,
  alertRaised,
  alertAcknowledged,
}

class IncidentAlert {
  const IncidentAlert({
    required this.id,
    required this.message,
    required this.raisedAt,
    this.acknowledgedAt,
  });

  final String id;
  final String message;
  final DateTime raisedAt;
  final DateTime? acknowledgedAt;

  bool get isAcknowledged => acknowledgedAt != null;

  IncidentAlert acknowledge(DateTime at) {
    if (isAcknowledged) {
      return this;
    }
    return IncidentAlert(
      id: id,
      message: message,
      raisedAt: raisedAt,
      acknowledgedAt: at.toUtc(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'message': message,
        'raisedAt': raisedAt.toUtc().toIso8601String(),
        'acknowledgedAt': acknowledgedAt?.toUtc().toIso8601String(),
      };

  factory IncidentAlert.fromJson(Map<String, Object?> json) {
    final acknowledgedAt = json['acknowledgedAt'] as String?;
    return IncidentAlert(
      id: json['id']! as String,
      message: json['message']! as String,
      raisedAt: DateTime.parse(json['raisedAt']! as String).toUtc(),
      acknowledgedAt:
          acknowledgedAt == null ? null : DateTime.parse(acknowledgedAt).toUtc(),
    );
  }
}

class IncidentTimelineEntry {
  const IncidentTimelineEntry({
    required this.kind,
    required this.at,
    required this.message,
  });

  final TimelineKind kind;
  final DateTime at;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'at': at.toUtc().toIso8601String(),
        'message': message,
      };

  factory IncidentTimelineEntry.fromJson(Map<String, Object?> json) {
    return IncidentTimelineEntry(
      kind: TimelineKind.values.byName(json['kind']! as String),
      at: DateTime.parse(json['at']! as String).toUtc(),
      message: json['message']! as String,
    );
  }
}

class Incident {
  Incident._({
    required this.id,
    required this.title,
    required this.summary,
    required this.severity,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required List<String> responders,
    required List<IncidentAlert> alerts,
    required List<IncidentTimelineEntry> timeline,
    required this.revision,
  })  : responders = List<String>.unmodifiable(responders),
        alerts = List<IncidentAlert>.unmodifiable(alerts),
        timeline = List<IncidentTimelineEntry>.unmodifiable(timeline);

  factory Incident.create({
    required String id,
    required String title,
    required String summary,
    required IncidentSeverity severity,
    required DateTime now,
  }) {
    final normalizedTitle = title.trim();
    if (id.trim().isEmpty) {
      throw const IncidentDomainException('Incident id must not be empty.');
    }
    if (normalizedTitle.isEmpty) {
      throw const IncidentDomainException('Incident title must not be empty.');
    }

    final timestamp = now.toUtc();
    return Incident._(
      id: id.trim(),
      title: normalizedTitle,
      summary: summary.trim(),
      severity: severity,
      status: IncidentStatus.declared,
      createdAt: timestamp,
      updatedAt: timestamp,
      responders: const <String>[],
      alerts: const <IncidentAlert>[],
      timeline: <IncidentTimelineEntry>[
        IncidentTimelineEntry(
          kind: TimelineKind.incidentCreated,
          at: timestamp,
          message: 'Incident declared as ${severity.name}.',
        ),
      ],
      revision: 1,
    );
  }

  final String id;
  final String title;
  final String summary;
  final IncidentSeverity severity;
  final IncidentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> responders;
  final List<IncidentAlert> alerts;
  final List<IncidentTimelineEntry> timeline;
  final int revision;

  static const Map<IncidentStatus, Set<IncidentStatus>> _allowedTransitions =
      <IncidentStatus, Set<IncidentStatus>>{
    IncidentStatus.declared: <IncidentStatus>{IncidentStatus.acknowledged},
    IncidentStatus.acknowledged: <IncidentStatus>{
      IncidentStatus.mitigated,
      IncidentStatus.resolved,
    },
    IncidentStatus.mitigated: <IncidentStatus>{IncidentStatus.resolved},
    IncidentStatus.resolved: <IncidentStatus>{},
  };

  Incident transitionTo(IncidentStatus next, DateTime at) {
    if (next == status) {
      return this;
    }
    if (!(_allowedTransitions[status]?.contains(next) ?? false)) {
      throw IncidentDomainException(
        'Invalid incident transition: ${status.name} -> ${next.name}.',
      );
    }

    return _copyWith(
      status: next,
      updatedAt: at.toUtc(),
      timeline: <IncidentTimelineEntry>[
        ...timeline,
        IncidentTimelineEntry(
          kind: TimelineKind.statusChanged,
          at: at.toUtc(),
          message: 'Status changed from ${status.name} to ${next.name}.',
        ),
      ],
      revision: revision + 1,
    );
  }

  Incident assignResponder(String responderId, DateTime at) {
    final normalized = responderId.trim();
    if (normalized.isEmpty) {
      throw const IncidentDomainException('Responder id must not be empty.');
    }
    if (responders.contains(normalized)) {
      return this;
    }

    return _copyWith(
      responders: <String>[...responders, normalized],
      updatedAt: at.toUtc(),
      timeline: <IncidentTimelineEntry>[
        ...timeline,
        IncidentTimelineEntry(
          kind: TimelineKind.responderAssigned,
          at: at.toUtc(),
          message: 'Responder assigned: $normalized.',
        ),
      ],
      revision: revision + 1,
    );
  }

  Incident addNote(String note, DateTime at) {
    final normalized = note.trim();
    if (normalized.isEmpty) {
      throw const IncidentDomainException('Timeline note must not be empty.');
    }

    return _copyWith(
      updatedAt: at.toUtc(),
      timeline: <IncidentTimelineEntry>[
        ...timeline,
        IncidentTimelineEntry(
          kind: TimelineKind.noteAdded,
          at: at.toUtc(),
          message: normalized,
        ),
      ],
      revision: revision + 1,
    );
  }

  Incident raiseAlert({
    required String alertId,
    required String message,
    required DateTime at,
  }) {
    if (alerts.any((alert) => alert.id == alertId)) {
      return this;
    }
    final normalized = message.trim();
    if (normalized.isEmpty) {
      throw const IncidentDomainException('Alert message must not be empty.');
    }

    final timestamp = at.toUtc();
    return _copyWith(
      alerts: <IncidentAlert>[
        ...alerts,
        IncidentAlert(
          id: alertId,
          message: normalized,
          raisedAt: timestamp,
        ),
      ],
      updatedAt: timestamp,
      timeline: <IncidentTimelineEntry>[
        ...timeline,
        IncidentTimelineEntry(
          kind: TimelineKind.alertRaised,
          at: timestamp,
          message: 'Alert raised: $normalized',
        ),
      ],
      revision: revision + 1,
    );
  }

  Incident acknowledgeAlert(String alertId, DateTime at) {
    final index = alerts.indexWhere((alert) => alert.id == alertId);
    if (index < 0) {
      throw IncidentDomainException('Unknown alert: $alertId.');
    }
    if (alerts[index].isAcknowledged) {
      return this;
    }

    final updatedAlerts = <IncidentAlert>[...alerts];
    updatedAlerts[index] = updatedAlerts[index].acknowledge(at);
    return _copyWith(
      alerts: updatedAlerts,
      updatedAt: at.toUtc(),
      timeline: <IncidentTimelineEntry>[
        ...timeline,
        IncidentTimelineEntry(
          kind: TimelineKind.alertAcknowledged,
          at: at.toUtc(),
          message: 'Alert acknowledged: $alertId.',
        ),
      ],
      revision: revision + 1,
    );
  }

  Incident _copyWith({
    IncidentStatus? status,
    DateTime? updatedAt,
    List<String>? responders,
    List<IncidentAlert>? alerts,
    List<IncidentTimelineEntry>? timeline,
    int? revision,
  }) {
    return Incident._(
      id: id,
      title: title,
      summary: summary,
      severity: severity,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      responders: responders ?? this.responders,
      alerts: alerts ?? this.alerts,
      timeline: timeline ?? this.timeline,
      revision: revision ?? this.revision,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'summary': summary,
        'severity': severity.name,
        'status': status.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'responders': responders,
        'alerts': alerts.map((alert) => alert.toJson()).toList(),
        'timeline': timeline.map((entry) => entry.toJson()).toList(),
        'revision': revision,
      };

  factory Incident.fromJson(Map<String, Object?> json) {
    final responders = (json['responders']! as List<Object?>).cast<String>();
    final alerts = (json['alerts']! as List<Object?>)
        .map(
          (value) => IncidentAlert.fromJson(
            Map<String, Object?>.from(value! as Map),
          ),
        )
        .toList();
    final timeline = (json['timeline']! as List<Object?>)
        .map(
          (value) => IncidentTimelineEntry.fromJson(
            Map<String, Object?>.from(value! as Map),
          ),
        )
        .toList();

    return Incident._(
      id: json['id']! as String,
      title: json['title']! as String,
      summary: json['summary']! as String,
      severity: IncidentSeverity.values.byName(json['severity']! as String),
      status: IncidentStatus.values.byName(json['status']! as String),
      createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
      responders: responders,
      alerts: alerts,
      timeline: timeline,
      revision: json['revision']! as int,
    );
  }
}
