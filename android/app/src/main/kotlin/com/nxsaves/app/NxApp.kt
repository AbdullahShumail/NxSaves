package com.nxsaves.app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns a single long-lived FlutterEngine so the download queue (Dart) keeps running when the
 * activity is closed with Back or swiped away. The foreground [DownloadService] keeps the process
 * alive while downloads are active.
 */
class NxApp : Application() {
    lateinit var platformBridge: PlatformBridge
        private set
    lateinit var ytDlpBridge: YtDlpBridge
        private set

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        val messenger = engine.dartExecutor.binaryMessenger
        ytDlpBridge = YtDlpBridge(this, messenger)
        platformBridge = PlatformBridge(this, messenger)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "nxsaves_main"
    }
}
