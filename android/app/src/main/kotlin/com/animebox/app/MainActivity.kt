package com.animebox.app

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MainActivity — canal plateforme « animebox/storage » : mesure RÉELLE de
 * l'espace disque disponible (StatFs) avant chaque téléchargement.
 * Aucune permission n'est requise pour un chemin du stockage privé.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.dartExecutor.binaryMessenger.let { messenger ->
            MethodChannel(messenger, "animebox/storage").setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFreeDiskSpace" -> {
                        val path = call.argument<String>("path")
                        try {
                            val target = if (!path.isNullOrBlank()) File(path) else filesDir
                            val dir = if (target.exists()) target else target.parentFile ?: filesDir
                            val stat = StatFs(dir.absolutePath)
                            result.success(stat.availableBytes)
                        } catch (e: Exception) {
                            result.error("STORAGE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
