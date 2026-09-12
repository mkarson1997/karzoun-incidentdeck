import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/application/notification_port.dart';
import 'package:incidentdeck/src/notifications/method_channel_notification_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('permission bridge failure becomes a failed delivery receipt', () async {
    const channel = MethodChannel('incidentdeck/test_local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'permissionStatus') {
        throw PlatformException(
          code: 'bridge-failed',
          message: 'permission bridge unavailable',
        );
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final port = MethodChannelNotificationPort(channel: channel);
    final receipt = await port.deliver(
      const NotificationMessage(
        id: 'alert-1',
        title: 'SEV1 Payments degraded',
        body: 'Page incident commander',
      ),
    );

    expect(receipt.status, NotificationDeliveryStatus.failed);
    expect(receipt.permission, NotificationPermissionStatus.unknown);
    expect(receipt.error, 'permission bridge unavailable');
  });
}
