enum NotificationPermissionStatus { unknown, granted, denied, unsupported }

enum NotificationDeliveryStatus {
  delivered,
  permissionRequired,
  denied,
  unsupported,
  failed,
}

class NotificationMessage {
  const NotificationMessage({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  final String id;
  final String title;
  final String body;
  final String? payload;
}

class NotificationDeliveryReceipt {
  const NotificationDeliveryReceipt({
    required this.messageId,
    required this.status,
    required this.permission,
    this.error,
  });

  final String messageId;
  final NotificationDeliveryStatus status;
  final NotificationPermissionStatus permission;
  final String? error;

  bool get isDelivered => status == NotificationDeliveryStatus.delivered;
}

abstract interface class NotificationPort {
  Future<NotificationPermissionStatus> permissionStatus();

  Future<NotificationPermissionStatus> requestPermission();

  Future<NotificationDeliveryReceipt> deliver(NotificationMessage message);
}

class UnsupportedNotificationPort implements NotificationPort {
  const UnsupportedNotificationPort({
    this.reason = 'Local notifications are unsupported by this host.',
  });

  final String reason;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    return NotificationPermissionStatus.unsupported;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    return NotificationPermissionStatus.unsupported;
  }

  @override
  Future<NotificationDeliveryReceipt> deliver(
    NotificationMessage message,
  ) async {
    return NotificationDeliveryReceipt(
      messageId: message.id,
      status: NotificationDeliveryStatus.unsupported,
      permission: NotificationPermissionStatus.unsupported,
      error: reason,
    );
  }
}
