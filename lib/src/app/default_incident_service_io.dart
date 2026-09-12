import 'dart:io';

import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:path_provider/path_provider.dart';

Future<IncidentService> createDefaultIncidentService() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final dataDirectory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}incidentdeck',
  );
  final snapshot = File(
    '${dataDirectory.path}${Platform.pathSeparator}incidents.json',
  );
  return IncidentService(repository: JsonIncidentRepository(snapshot));
}
