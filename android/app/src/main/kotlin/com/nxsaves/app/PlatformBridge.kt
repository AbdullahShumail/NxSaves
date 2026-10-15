package com.nxsaves.app

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/**
 * Android-only platform features (channel "nxsaves/platform"): saving into the shared
 * Movies/Music collections, opening/sharing/deleting saved media, runtime permissions, the
 * foreground download service, and links shared into the app from other apps.
 */
class PlatformBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "nxsaves/platform")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var activityRef: WeakReference<Activity>? = null
    private val pendingPermissions = mutableMapOf<Int, MethodChannel.Result>()
    private var nextRequestCode = 4100

    private var pendingShare: String? = null
    private var dartReady = false
    private var pendingCookies: MethodChannel.Result? = null

    companion object {
        private const val COOKIES_REQUEST = 4099
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun attachActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    fun detachActivity(activity: Activity) {
        if (activityRef?.get() === activity) activityRef = null
    }

    /** Extracts shared text (a link) from ACTION_SEND intents and forwards it to Dart. */
    fun handleIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: return
        // Consume the intent so a configuration change does not re-deliver it.
        intent.action = null
        if (dartReady) {
            channel.invokeMethod("onShared", text)
        } else {
            pendingShare = text
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingShare" -> {
                dartReady = true
                result.success(pendingShare)
                pendingShare = null
            }
            "saveToPublic" -> ioTask(result) {
                MediaSaver.save(
                    context,
                    File(call.argument<String>("path")!!),
                    call.argument<String>("kind")!!,
                    call.argument<String>("name")!!,
                )
            }
            "open" -> result.success(launch(MediaSaver.viewIntent(context, call.argument("uri"), call.argument("path"), call.argument<String>("mime")!!)))
            "share" -> result.success(launch(MediaSaver.shareIntent(context, call.argument("uri"), call.argument("path"), call.argument<String>("mime")!!)))
            "delete" -> ioTask(result) { MediaSaver.delete(context, call.argument("uri"), call.argument("path")) }
            "exists" -> ioTask(result) {
                val items = call.argument<List<Map<String, String?>>>("items") ?: emptyList()
                items.map { MediaSaver.exists(context, it["uri"], it["path"]) }
            }
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "hasNotificationPermission" -> result.success(hasNotificationPermission())
            "requestNotificationPermission" -> {
                if (hasNotificationPermission()) result.success(true)
                else requestPermission(Manifest.permission.POST_NOTIFICATIONS, result)
            }
            "requestLegacyStoragePermission" -> {
                if (Build.VERSION.SDK_INT >= 29 || granted(Manifest.permission.WRITE_EXTERNAL_STORAGE)) result.success(true)
                else requestPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE, result)
            }
            "setServiceState" -> {
                DownloadService.setState(
                    context,
                    call.argument<Int>("active") ?: 0,
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text") ?: "",
                    call.argument<Int>("progress") ?: -1,
                )
                result.success(null)
            }
            "moveToBackground" -> {
                val moved = activityRef?.get()?.moveTaskToBack(true) ?: false
                result.success(moved)
            }
            "importCookies" -> {
                val activity = activityRef?.get()
                if (activity == null || pendingCookies != null) {
                    result.success(null)
                    return
                }
                pendingCookies = result
                val pick = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                try {
                    activity.startActivityForResult(pick, COOKIES_REQUEST)
                } catch (e: ActivityNotFoundException) {
                    pendingCookies = null
                    result.error("NO_PICKER", "No file picker available", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Copies the picked cookies.txt into private storage; yt-dlp reads (and updates) that copy. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != COOKIES_REQUEST) return
        val result = pendingCookies ?: return
        pendingCookies = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        ioTask(result) {
            val dest = File(context.filesDir, "cookies.txt")
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { input.copyTo(it) }
            } ?: throw IllegalStateException("Could not read the selected file")
            val head = dest.bufferedReader().use { it.readText().take(4096) }
            if (!head.contains("\t") && !head.contains("Netscape")) {
                dest.delete()
                throw IllegalArgumentException("That file is not a Netscape-format cookies.txt")
            }
            dest.absolutePath
        }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        val result = pendingPermissions.remove(requestCode) ?: return
        result.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(permission: String, result: MethodChannel.Result) {
        val activity = activityRef?.get()
        if (activity == null) {
            result.success(false)
            return
        }
        val code = nextRequestCode++
        pendingPermissions[code] = result
        ActivityCompat.requestPermissions(activity, arrayOf(permission), code)
    }

    private fun launch(intent: Intent?): Boolean {
        if (intent == null) return false
        val activity = activityRef?.get()
        return try {
            if (activity != null) activity.startActivity(intent)
            else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun ioTask(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("PLATFORM_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }
}
