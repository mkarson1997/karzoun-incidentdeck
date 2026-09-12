import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/application/notification_port.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';

class _FakeNotificationPort implements NotificationPort {
  _FakeNotificationPort({
    this.permission = NotificationPermissionStatus.unknown,
    this.throwOnDeliver = false,
  });

  NotificationPermissionStatus permission;
  final bool throwOnDeliver;
  final List<NotificationMessage> delivered = <NotificationMessage>[];

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => permission;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (permission == NotificationPermissionStatus.unknown) {
      permission = NotificationPermissionStatus.granted;
    }
    return permission;
  }

  @override
  Future<NotificationDeliveryReceipt> deliver(
    NotificationMessage message,
  ) async {
    if (throwOnDeliver) {
      throw StateError('native bridge failed');
    }
    switch (permission) {
      case NotificationPermissionStatus.unknown:
        return NotificationDeliveryReceipt(
          messageId: message.id,
          status: NotificationDeliveryStatus.permissionRequired,
          permission: permission,
        );
      case NotificationPermissionStatus.denied:
        return NotificationDeliveryReceipt(
          messageId: message.id,
          status: NotificationDeliveryStatus.denied,
          permission: permission,
        );
      case NotificationPermissionStatus.unsupported:
        return NotificationDeliveryReceipt(
          messageId: message.id,
          status: NotificationDeliveryStatus.unsupported,
          permission: permission,
        );
      case NotificationPermissionStatus.granted:
        delivered.add(message);
        return NotificationDeliveryReceipt(
          messageId: message.id,
          status: NotificationDeliveryStatus.delivered,
          permission: permission,
        );
    }
  }
}

IncidentService _service(_FakeNotificationPort notifications) {
  return IncidentService(
    repository: InMemoryIncidentRepository(),
    notificationPort: notifications,
    clock: () => DateTime.utc(2026, 9, 12, 16),
    idGenerator: (_) => 'inc-notify',
  );
}

Future<Incident> _declare(IncidentService service) {
  return service.declareIncident(
    title: 'Payments degraded',
    summary: 'Checkout latency is elevated',
    severity: IncidentSeverity.sev1,
  );
}

void main() {
  test(
    'unknown permission never triggers an implicit permission request',
    () async {
      final notifications = _FakeNotificationPort();
      final service = _service(notifications);
      await _declare(service);

      final result = await service.raiseAlertAndNotify(
        'inc-notify',
        'Page incident commander',
      );

      expect(
        result.delivery.status,
        NotificationDeliveryStatus.permissionRequired,
      );
      expect(notifications.delivered, isEmpty);
      expect(result.incident.alerts.single.message, 'Page incident commander');
      expect(
        service.notificationDeliveryForAlert(result.alert.id)?.status,
        NotificationDeliveryStatus.permissionRequired,
      );
    },
  );

  test('explicit permission request enables local delivery', () async {
    final notifications = _FakeNotificationPort();
    final service = _service(notifications);
    await _declare(service);

    expect(
      await service.requestNotificationPermission(),
      NotificationPermissionStatus.granted,
    );
    final result = await service.raiseAlertAndNotify(
      'inc-notify',
      'Page incident commander',
    );

    expect(result.delivery.isDelivered, isTrue);
    expect(notifications.delivered, hasLength(1));
    expect(notifications.delivered.single.payload, 'inc-notify');
    expect(notifications.delivered.single.body, 'Page incident commander');
  });

  test(
    'denied notification delivery does not roll back the domain alert',
    () async {
      final notifications = _FakeNotificationPort(
        permission: NotificationPermissionStatus.denied,
      );
      final service = _service(notifications);
      await _declare(service);

      final result = await service.raiseAlertAndNotify(
        'inc-notify',
        'Escalate to responder',
      );
      final persisted = await service.getIncident('inc-notify');

      expect(result.delivery.status, NotificationDeliveryStatus.denied);
      expect(persisted?.alerts, hasLength(1));
      expect(persisted?.alerts.single.message, 'Escalate to responder');
      expect(
        persisted?.toJson().containsKey('notificationDeliveries'),
        isFalse,
      );
    },
  );

  test(
    'native delivery failure is isolated from alert acknowledgement state',
    () async {
      final notifications = _FakeNotificationPort(
        permission: NotificationPermissionStatus.granted,
        throwOnDeliver: true,
      );
      final service = _service(notifications);
      await _declare(service);

      final result = await service.raiseAlertAndNotify(
        'inc-notify',
        'Escalate to responder',
      );
      expect(result.delivery.status, NotificationDeliveryStatus.failed);
      expect(result.incident.alerts.single.isAcknowledged, isFalse);

      await service.acknowledgeAlert('inc-notify', result.alert.id);
      final persisted = await service.getIncident('inc-notify');
      expect(persisted?.alerts.single.isAcknowledged, isTrue);
      expect(
        service.notificationDeliveryForAlert(result.alert.id)?.status,
        NotificationDeliveryStatus.failed,
      );
    },
  );
}
