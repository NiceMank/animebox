/// Implémentation IO de la fabrique (jamais importée sur le web).
library;

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DatabaseFactory?> resolveFactory() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return databaseFactory; // sqflite natif
  }
  // Bureau et environnements de test : SQLite via FFI.
  sqfliteFfiInit();
  return databaseFactoryFfi;
}
