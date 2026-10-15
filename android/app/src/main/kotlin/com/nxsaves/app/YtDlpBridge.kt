package com.nxsaves.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantReadWriteLock

/**
 * Runs the real yt-dlp (bundled Python + ffmpeg + QuickJS from youtubedl-android) on the device.
 *
 * Methods (channel "nxsaves/ytdlp"): init, version, update, getInfo, start, cancel.
 * Events (channel "nxsaves/ytdlp/events"): {taskId, type: line|done|error|canceled, ...}.
 */
class YtDlpBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val channel = MethodChannel(messenger, "nxsaves/ytdlp")
    private val events = EventChannel(messenger, "nxsaves/ytdlp/events")
    private val main = Handler(Looper.getMainLooper())
    private val pool = Executors.newCachedThreadPool()

    // Processes hold the read lock; replacing the yt-dlp binary (update) needs the write lock so
    // it never swaps the zipapp under a running process.
    private val binaryLock = ReentrantReadWriteLock()
    private val running = ConcurrentHashMap.newKeySet<String>()
    private var sink: EventChannel.EventSink? = null

    @Volatile private var initialized = false
    @Volatile private var cachedVersion: String? = null

    private val cacheDir: File get() = File(context.cacheDir, "yt-dlp-cache").apply { mkdirs() }

    init {
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> background(result) {
                ensureInit()
                mapOf("version" to version())
            }
            "version" -> background(result) {
                ensureInit()
                version()
            }
            "update" -> background(result) { update(call.argument<String>("channel") ?: "stable") }
            "getInfo" -> background(result) {
                getInfo(
                    call.argument<String>("url")!!,
                    call.argument<String>("requestId")!!,
                    call.argument<List<String>>("args") ?: emptyList(),
                )
            }
            "start" -> {
                val taskId = call.argument<String>("taskId")!!
                if (!running.add(taskId)) {
                    result.error("ALREADY_RUNNING", "Task $taskId is already running", null)
                    return
                }
                pool.execute {
                    runDownload(
                        taskId,
                        call.argument<String>("url")!!,
                        call.argument<List<String>>("args") ?: emptyList(),
                    )
                }
                result.success(null)
            }
            "cancel" -> {
                val id = call.argument<String>("id")!!
                result.success(YoutubeDL.getInstance().destroyProcessById(id))
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        // First launch unpacks Python and ffmpeg (a few seconds); later launches are instant.
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
        initialized = true
    }

    private fun version(): String? {
        cachedVersion?.let { return it }
        val request = YoutubeDLRequest(emptyList<String>()).addOption("--version")
        val out = withReadLock { YoutubeDL.getInstance().execute(request, null, false, null) }.out
        return out.trim().lineSequence().lastOrNull()?.trim()?.ifEmpty { null }.also { cachedVersion = it }
    }

    private fun update(channelName: String): Map<String, Any?> {
        ensureInit()
        val updateChannel = when (channelName) {
            "nightly" -> YoutubeDL.UpdateChannel.NIGHTLY
            else -> YoutubeDL.UpdateChannel.STABLE
        }
        val lock = binaryLock.writeLock()
        if (!lock.tryLock(3, TimeUnit.SECONDS)) {
            throw IllegalStateException("yt-dlp is busy. Try updating when no downloads are running.")
        }
        try {
            val status = YoutubeDL.getInstance().updateYoutubeDL(context, updateChannel)
            cachedVersion = null
            return mapOf(
                "status" to if (status == YoutubeDL.UpdateStatus.DONE) "updated" else "up_to_date",
                "version" to version(),
            )
        } finally {
            lock.unlock()
        }
    }

    private fun getInfo(url: String, requestId: String, extraArgs: List<String>): String {
        ensureInit()
        val request = YoutubeDLRequest(url)
            .addOption("-J")
            .addOption("--no-playlist")
            .addOption("--flat-playlist")
            .addOption("--cache-dir", cacheDir.absolutePath)
            .addCommands(extraArgs)
        return withReadLock { YoutubeDL.getInstance().execute(request, requestId, false, null) }.out
    }

    private fun runDownload(taskId: String, url: String, args: List<String>) {
        try {
            ensureInit()
            val request = YoutubeDLRequest(url)
                .addOption("--cache-dir", cacheDir.absolutePath)
                .addCommands(args)
            withReadLock {
                YoutubeDL.getInstance().execute(request, taskId, false) { _, _, line ->
                    emit(mapOf("taskId" to taskId, "type" to "line", "line" to line))
                }
            }
            emit(mapOf("taskId" to taskId, "type" to "done"))
        } catch (e: YoutubeDL.CanceledException) {
            emit(mapOf("taskId" to taskId, "type" to "canceled"))
        } catch (e: Throwable) {
            Log.e(TAG, "Download $taskId failed", e)
            emit(mapOf("taskId" to taskId, "type" to "error", "message" to tail(describe(e))))
        } finally {
            running.remove(taskId)
        }
    }

    private fun <T> withReadLock(block: () -> T): T {
        val lock = binaryLock.readLock()
        lock.lock()
        try {
            return block()
        } finally {
            lock.unlock()
        }
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        pool.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: YoutubeDL.CanceledException) {
                main.post { result.error("CANCELED", "Canceled", null) }
            } catch (e: Throwable) {
                Log.e(TAG, "yt-dlp call failed", e)
                main.post { result.error("YTDLP_ERROR", tail(describe(e)), null) }
            }
        }
    }

    private fun tail(text: String, max: Int = 6000): String =
        if (text.length <= max) text else text.substring(text.length - max)

    /** yt-dlp's stderr for yt-dlp failures; exception + root cause for anything else. */
    private fun describe(e: Throwable): String {
        e.message?.takeIf { it.isNotBlank() && e.cause == null }?.let { return it }
        var root: Throwable = e
        while (root.cause != null && root.cause !== root) root = root.cause!!
        return if (root === e) e.toString() else "$e\nCaused by: $root"
    }

    companion object {
        private const val TAG = "NxSaves"
    }
}
