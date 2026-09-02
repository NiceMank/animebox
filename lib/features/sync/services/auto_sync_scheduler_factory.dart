import 'package:flutter/foundation.dart';

import 'auto_sync_scheduler.dart';
import 'in_memory_auto_sync.dart';
import 'workmanager_auto_sync.dart';

/// Planificateur adapté à la plateforme :
/// - Android → WorkManager (règles 11/26) ;
/// - autre plateforme → mémoire (les réglages restent modifiables sans
///   prétendre à une exécution d'arrière-plan).
AutoSyncScheduler createPlatformAutoSyncScheduler() {
  if (kIsWeb) return InMemoryAutoSyncScheduler();
  return defaultTargetPlatform == TargetPlatform.android
      ? WorkmanagerAutoSyncScheduler()
      : InMemoryAutoSyncScheduler();
}
