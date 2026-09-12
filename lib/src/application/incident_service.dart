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

class IncidentService {
  IncidentService({
    required this.repository,
    Clock? clock,
    IncidentIdGenerator? idGenerator,
    IncidentSnapshotCodec snapshotCodec = const IncidentSnapshotCodec(),
  }) : _clock = clock ?? _systemClock,
       _idGenerator = idGenerator ?? MonotonicIncidentIdGenerator().call,
       _snapshotCodec = snapshotCodec;

  final IncidentRepository repository;
  final Clock _clock;
  final IncidentIdGenerator _idGenerator;
  final IncidentSnapshotCodec _snapshotCodec;

  static DateTime _systemClock() => DateTime.now().toUtc();

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

  Future<Incident> acknowledgeAlert(String id, String alertId) {
    final now = _clock().toUtc();
    return repository.update(
      id,
      (incident) => incident.acknowledgeAlert(alertId, now),
    );
  }
}
