import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/app/default_incident_service_stub.dart'
    if (dart.library.io) 'package:incidentdeck/src/app/default_incident_service_io.dart'
    as platform;

Future<IncidentService> createDefaultIncidentService() {
  return platform.createDefaultIncidentService();
}
