import '../models/sync_frequency.dart';
import 'auto_sync_scheduler.dart';

/// Planificateur EN MÉMOIRE — tests et mode démonstration : il ne
/// planifie rien de réel mais mémorise exactement ce qu'on lui demande.
class InMemoryAutoSyncScheduler implements AutoSyncScheduler {
  bool initialized = false;
  SyncFrequency applied = SyncFrequency.disabled;
  bool appliedWifiOnly = false;
  int applyCount = 0;
  int cancelCount = 0;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> applyFrequency(SyncFrequency frequency, {bool wifiOnly = false}) async {
    initialized = true;
    applied = frequency;
    appliedWifiOnly = wifiOnly;
    applyCount += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    applied = SyncFrequency.disabled;
  }
}
