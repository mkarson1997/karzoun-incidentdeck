import 'package:incidentdeck/src/application/notification_port.dart';

NotificationPort createDefaultNotificationPort() {
  return const UnsupportedNotificationPort(
    reason: 'Native local notifications are unavailable in the web preview.',
  );
}
