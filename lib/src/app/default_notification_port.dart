import 'package:incidentdeck/src/app/default_notification_port_stub.dart'
    if (dart.library.io) 'package:incidentdeck/src/app/default_notification_port_io.dart'
    as platform;
import 'package:incidentdeck/src/application/notification_port.dart';

NotificationPort createDefaultNotificationPort() {
  return platform.createDefaultNotificationPort();
}
