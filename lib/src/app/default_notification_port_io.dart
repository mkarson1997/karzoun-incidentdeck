import 'package:incidentdeck/src/application/notification_port.dart';
import 'package:incidentdeck/src/notifications/method_channel_notification_port.dart';

NotificationPort createDefaultNotificationPort() {
  return MethodChannelNotificationPort();
}
