import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';

Future<IncidentService> createDefaultIncidentService() async {
  return IncidentService(repository: InMemoryIncidentRepository());
}
