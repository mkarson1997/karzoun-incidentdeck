import 'package:flutter/services.dart';
import 'package:incidentdeck/src/application/notification_port.dart';

class MethodChannelNotificationPort implements NotificationPort {
  MethodChannelNotificationPort({
    MethodChannel channel = const MethodChannel(
      'incidentdeck/local_notifications',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    try {
      final raw = await _channel.invokeMethod<String>('permissionStatus');
      return _parsePermission(raw);
    } on MissingPluginException {
      return NotificationPermissionStatus.unsupported;
    } on PlatformException {
      return NotificationPermissionStatus.unknown;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    try {
      final raw = await _channel.invokeMethod<String>('requestPermission');
      return _parsePermission(raw);
    } on MissingPluginException {
      return NotificationPermissionStatus.unsupported;
    } on PlatformException {
      return NotificationPermissionStatus.denied;
    }
  }

  @override
  Future<NotificationDeliveryReceipt> deliver(
    NotificationMessage message,
  ) async {
    final NotificationPermissionStatus permission;
    try {
      final raw = await _channel.invokeMethod<String>('permissionStatus');
      permission = _parsePermission(raw);
    } on MissingPluginException {
      return NotificationDeliveryReceipt(
        messageId: message.id,
        status: NotificationDeliveryStatus.unsupported,
        permission: NotificationPermissionStatus.unsupported,
        error: 'No native IncidentDeck notification host is registered.',
      );
    } on PlatformException catch (error) {
      return NotificationDeliveryReceipt(
        messageId: message.id,
        status: NotificationDeliveryStatus.failed,
        permission: NotificationPermissionStatus.unknown,
        error: error.message ?? error.code,
      );
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
        break;
    }

    try {
      final delivered = await _channel
          .invokeMethod<bool>('show', <String, Object?>{
            'id': message.id,
            'title': message.title,
            'body': message.body,
            'payload': message.payload,
          });
      if (delivered == true) {
        return NotificationDeliveryReceipt(
          messageId: message.id,
          status: NotificationDeliveryStatus.delivered,
          permission: permission,
        );
      }
      return NotificationDeliveryReceipt(
        messageId: message.id,
        status: NotificationDeliveryStatus.failed,
        permission: permission,
        error: 'Native host did not confirm notification delivery.',
      );
    } on MissingPluginException {
      return NotificationDeliveryReceipt(
        messageId: message.id,
        status: NotificationDeliveryStatus.unsupported,
        permission: NotificationPermissionStatus.unsupported,
        error: 'No native IncidentDeck notification host is registered.',
      );
    } on PlatformException catch (error) {
      return NotificationDeliveryReceipt(
        messageId: message.id,
        status: NotificationDeliveryStatus.failed,
        permission: permission,
        error: error.message ?? error.code,
      );
    }
  }

  NotificationPermissionStatus _parsePermission(String? raw) {
    return switch (raw) {
      'granted' => NotificationPermissionStatus.granted,
      'denied' => NotificationPermissionStatus.denied,
      'unsupported' => NotificationPermissionStatus.unsupported,
      _ => NotificationPermissionStatus.unknown,
    };
  }
}
