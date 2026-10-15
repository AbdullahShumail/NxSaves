package com.nxsaves.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val bridge get() = (application as NxApp).platformBridge

    // Attach to the engine created in NxApp instead of creating (and later destroying) our own.
    override fun getCachedEngineId(): String = NxApp.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bridge.attachActivity(this)
        if (savedInstanceState == null) bridge.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bridge.handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        bridge.attachActivity(this)
    }

    override fun onDestroy() {
        bridge.detachActivity(this)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        bridge.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge.onPermissionResult(requestCode, grantResults)
    }
}
