package com.nxsaves.app

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Copies finished downloads into shared storage so they show up in the gallery / music apps and
 * survive uninstalling NxSaves: videos go to Movies/NxSaves, audio to Music/NxSaves.
 */
object MediaSaver {
    private const val FOLDER = "NxSaves"

    fun save(context: Context, src: File, kind: String, displayName: String): Map<String, Any?> {
        if (!src.exists()) throw FileNotFoundException("Downloaded file is missing: ${src.name}")
        val mime = mimeFor(src.extension, kind)
        val name = sanitize(displayName)
        return if (Build.VERSION.SDK_INT >= 29) saveScoped(context, src, kind, name, mime)
        else saveLegacy(context, src, kind, name, mime)
    }

    @RequiresApi(29)
    private fun saveScoped(context: Context, src: File, kind: String, name: String, mime: String): Map<String, Any?> {
        val volume = MediaStore.VOLUME_EXTERNAL_PRIMARY
        val primary = if (kind == "audio") {
            MediaStore.Audio.Media.getContentUri(volume) to "${Environment.DIRECTORY_MUSIC}/$FOLDER"
        } else {
            MediaStore.Video.Media.getContentUri(volume) to "${Environment.DIRECTORY_MOVIES}/$FOLDER"
        }
        return try {
            insertAndCopy(context.contentResolver, primary.first, primary.second, name, mime, src)
        } catch (e: Exception) {
            // Unusual containers can be rejected by the media collections; Downloads accepts anything.
            insertAndCopy(
                context.contentResolver,
                MediaStore.Downloads.getContentUri(volume),
                "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER",
                name,
                mime,
                src,
            )
        }
    }

    @RequiresApi(29)
    private fun insertAndCopy(
        resolver: ContentResolver,
        collection: Uri,
        relativePath: String,
        name: String,
        mime: String,
        src: File,
    ): Map<String, Any?> {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("Could not create $name in $relativePath")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IOException("Could not open $uri for writing")
            out.use { output -> src.inputStream().use { it.copyTo(output, 1 shl 16) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return mapOf("uri" to uri.toString(), "path" to queryPath(resolver, uri), "mime" to mime)
    }

    private fun saveLegacy(context: Context, src: File, kind: String, name: String, mime: String): Map<String, Any?> {
        val base = Environment.getExternalStoragePublicDirectory(
            if (kind == "audio") Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_MOVIES,
        )
        val dir = File(base, FOLDER)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("Cannot create ${dir.absolutePath}")
        val dest = uniqueFile(dir, name)
        src.copyTo(dest, overwrite = false)
        val latch = CountDownLatch(1)
        var scanned: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(dest.absolutePath), arrayOf(mime)) { _, uri ->
            scanned = uri
            latch.countDown()
        }
        latch.await(10, TimeUnit.SECONDS)
        return mapOf("uri" to scanned?.toString(), "path" to dest.absolutePath, "mime" to mime)
    }

    fun viewIntent(context: Context, uri: String?, path: String?, mime: String): Intent? {
        val target = shareableUri(context, uri, path) ?: return null
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(target, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    fun shareIntent(context: Context, uri: String?, path: String?, mime: String): Intent? {
        val target = shareableUri(context, uri, path) ?: return null
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, target)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return Intent.createChooser(send, null)
    }

    fun delete(context: Context, uri: String?, path: String?): Boolean {
        var deleted = false
        if (uri != null) {
            deleted = try {
                context.contentResolver.delete(Uri.parse(uri), null, null) > 0
            } catch (e: SecurityException) {
                // Happens for files created by a previous install; the user must delete them in the gallery.
                false
            }
        }
        if (Build.VERSION.SDK_INT < 29 && path != null) {
            val file = File(path)
            if (file.exists()) deleted = file.delete() || deleted
        }
        return deleted || !exists(context, uri, path)
    }

    fun exists(context: Context, uri: String?, path: String?): Boolean {
        if (uri != null) {
            return try {
                context.contentResolver.openFileDescriptor(Uri.parse(uri), "r")?.close()
                true
            } catch (e: FileNotFoundException) {
                false
            } catch (e: IllegalArgumentException) {
                false
            } catch (e: SecurityException) {
                true // exists, but owned by a previous install
            }
        }
        return path != null && File(path).exists()
    }

    private fun shareableUri(context: Context, uri: String?, path: String?): Uri? {
        // Before Android 10, hand out a FileProvider URI for the real file (works with every app).
        if (Build.VERSION.SDK_INT < 29 && path != null && File(path).exists()) {
            return FileProvider.getUriForFile(context, "${context.packageName}.files", File(path))
        }
        return uri?.let(Uri::parse)
    }

    @Suppress("DEPRECATION")
    private fun queryPath(resolver: ContentResolver, uri: Uri): String? = try {
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }

    fun mimeFor(extension: String, kind: String): String {
        val ext = extension.lowercase()
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)?.let { return it }
        return when (ext) {
            "mp4", "m4v" -> "video/mp4"
            "webm" -> if (kind == "audio") "audio/webm" else "video/webm"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "opus", "ogg" -> "audio/ogg"
            "flac" -> "audio/flac"
            "wav" -> "audio/wav"
            else -> if (kind == "audio") "audio/*" else "video/*"
        }
    }

    private fun sanitize(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").trim()
        return cleaned.ifEmpty { "download" }
    }

    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val base = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "")
        var i = 1
        while (candidate.exists()) {
            candidate = File(dir, if (ext.isEmpty()) "$base ($i)" else "$base ($i).$ext")
            i++
        }
        return candidate
    }
}
