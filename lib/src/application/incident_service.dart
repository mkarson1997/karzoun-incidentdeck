import 'dart:collection';

import 'package:incidentdeck/src/application/notification_port.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/data/incident_snapshot_codec.dart';
import 'package:incidentdeck/src/domain/incident.dart';

typedef Clock = DateTime Function();
typedef IncidentIdGenerator = String Function(DateTime now);

class MonotonicIncidentIdGenerator {
  int _sequence = 0;

  String call(DateTime now) {
    final sequence = _sequence++;
    return 'inc-${now.toUtc().microsecondsSinceEpoch}-$sequence';
  }
}

class AlertDeliveryResult {
  const AlertDeliveryResult({
    required this.incident,
    required this.alert,
    required this.delivery,
  });

  final Incident incident;
  final IncidentAlert alert;
  final NotificationDeliveryReceipt delivery;
}

class IncidentService {
  IncidentService({
    required this.repository,
    Clock? clock,
    IncidentIdGenerator? idGenerator,
    IncidentSnapshotCodec snapshotCodec = const IncidentSnapshotCodec(),
    NotificationPort? notificationPort,
  }) : _clock = clock ?? _systemClock,
       _idGenerator = idGenerator ?? MonotonicIncidentIdGenerator().call,
       _snapshotCodec = snapshotCodec,
       _notificationPort = notificationPort ?? const UnsupportedNotificationPort();

  final IncidentRepository repository;
  final Clock _clock;
  final IncidentIdGenerator _idGenerator;
  final IncidentSnapshotCodec _snapshotCodec;
  final NotificationPort _notificationPort;
  final Map<String, NotificationDeliveryReceipt> _notificationDeliveries =
      <String, NotificationDeliveryReceipt>{};

  static DateTime _systemClock() => DateTime.now().toUtc();

  UnmodifiableMapView<String, NotificationDeliveryReceipt>
  get notificationDeliveries => UnmodifiableMapView(_notificationDeliveries);

  NotificationDeliveryReceipt? notificationDeliveryForAlert(String alertId) {
    return _notificationDeliveries[alertId];
  }

  Future<NotificationPermissionStatus> notificationPermissionStatus() {
    return _notificationPort.permissionStatus();
  }

  Future<NotificationPermissionStatus> requestNotificationPermission() {
    return _notificationPort.requestPermission();
  }

  Future<Incident> declareIncident({
    required String title,
    required String summary,
    required IncidentSeverity severity,
  }) async {
    final now = _clock().toUtc();
    final incident = Incident.create(
      id: _idGenerator(now),
      title: title,
      summary: summary,
      severity: severity,
      now: now,
    );
    await repository.save(incident);
    return incident;
  }

  Future<List<Incident>> listIncidents() => repository.list();

  Future<Incident?> getIncident(String id) => repository.find(id);

  Future<String> exportSnapshot() async {
    return _snapshotCodec.encode(await repository.list());
  }

  Future<List<Incident>> importSnapshot(String raw) async {
    final incidents = _snapshotCodec.decode(raw);
    await repository.replaceAll(incidents);
    return repository.list();
  }

  Future<Incident> transition(String id, IncidentStatus next) {
    final now = _clock().toUtc();
    return repository.update(
      id,
      (incident) => incident.transitionTo(next, now),
    );
  }

  Future<Incident> assignResponder(String id, String responderId) {
    final now = _clock().toUtc();
    return repository.update(
      id,
      (incident) => incident.assignResponder(responderId, now),
    );
  }

  Future<Incident> addNote(String id, String note) {
    final now = _clock().toUtc();
    return repository.update(id, (incident) => incident.addNote(note, now));
  }

  Future<Incident> raiseAlert(String id, String message) {
    final now = _clock().toUtc();
    return repository.update(id, (incident) {
      final alertId = 'alert-${incident.id}-${incident.revision + 1}';
      return incident.raiseAlert(alertId: alertId, message: message, at: now);
    });
  }

  Future<AlertDeliveryResult> raiseAlertAndNotify(
    String id,
    String message,
  ) async {
    final incident = await raiseAlert(id, message);
    final alert = incident.alerts.last;
    NotificationDeliveryReceipt delivery;

    try {
      delivery = await _notificationPort.deliver(
        NotificationMessage(
          id: alert.id,
          title: '${incident.severity.name.toUpperCase()} ${incident.title}',
          body: alert.message,
          payload: incident.id,
        ),
      );
    } on Object catch (error) {
      delivery = NotificationDeliveryReceipt(
        messageId: alert.id,
        status: NotificationDeliveryStatus.failed,
        permission: NotificationPermissionStatus.unknown,
        error: error.toString(),
      );
    }

    _notificationDeliveries[alert.id] = delivery;
    return AlertDeliveryResult(
      incident: incident,
      alert: alert,
      delivery: delivery,
    );
  }

  Future<Incident> acknowledgeAlert(String id, String alertId) {
    final now = _clock().toUtc();
    return repository.update(
      id,
      (incident) => incident.acknowledgeAlert(alertId, now),
    );
  }
}
