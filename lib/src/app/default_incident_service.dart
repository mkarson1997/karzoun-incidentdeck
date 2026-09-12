import 'package:incidentdeck/src/app/default_incident_service_stub.dart'
    if (dart.library.io) 'package:incidentdeck/src/app/default_incident_service_io.dart'
    as platform;
import 'package:incidentdeck/src/application/incident_service.dart';

Future<IncidentService> createDefaultIncidentService() {
  return platform.createDefaultIncidentService();
}
