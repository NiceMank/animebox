import 'package:flutter/foundation.dart';

import 'in_memory_notification_service.dart';
import 'local_notification_service.dart';
import 'notification_service.dart';

/// Service adapté à la plateforme :
/// - Android → notifications réelles (`flutter_local_notifications`) ;
/// - autre plateforme / web → service en mémoire (aucun plantage : le mode
///   démonstration et les tests restent pleinement fonctionnels).
NotificationService createPlatformNotificationService() {
  if (kIsWeb) return InMemoryNotificationService();
  final bool isAndroid = defaultTargetPlatform == TargetPlatform.android;
  return isAndroid ? LocalNotificationService() : InMemoryNotificationService();
}
