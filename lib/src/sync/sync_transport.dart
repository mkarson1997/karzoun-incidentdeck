import 'package:incidentdeck/src/domain/incident.dart';
import 'package:incidentdeck/src/sync/sync_protocol.dart';

abstract interface class SyncTransport {
  Future<SyncPushResult> push(SyncOperation operation);

  Future<List<Incident>> pull();
}
