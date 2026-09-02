import 'package:flutter/services.dart';

import 'storage_checker.dart';

/// Mesure RÉELLE de l'espace libre via le canal plateforme Android
/// (`StatFs.availableBytes` — voir MainActivity.kt).
StorageChecker createStorageChecker() => MethodChannelStorageChecker();

class MethodChannelStorageChecker implements StorageChecker {
  static const MethodChannel _channel = MethodChannel('animebox/storage');

  @override
  Future<int?> freeBytes(String? path) async {
    try {
      final int? bytes = await _channel.invokeMethod<int>('getFreeDiskSpace', {
        'path': path,
      });
      return bytes;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
