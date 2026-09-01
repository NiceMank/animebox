import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db_factory_stub.dart'
    if (dart.library.io) 'db_factory_io.dart' as db_impl;

/// Fabrique de base de données adaptée à la plateforme :
/// - Android/iOS → sqflite natif ;
/// - Linux/macOS/Windows (tests et développement) → sqflite_common_ffi ;
/// - web → null (le mode démo n'utilise pas de base locale).
Future<DatabaseFactory?> resolveDatabaseFactory() {
  if (kIsWeb) return Future<DatabaseFactory?>.value(null);
  return db_impl.resolveFactory();
}
