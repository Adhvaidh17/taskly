package com.example.taskly_mobile

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val mediaChannel = "taskly/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "prepareOutgoing" -> result.success(prepareOutgoing(call))
                        "saveIncoming" -> result.success(saveIncoming(call))
                        "prepareTaskAttachmentOutgoing" -> result.success(prepareTaskAttachmentOutgoing(call))
                        "saveTaskAttachmentIncoming" -> result.success(saveTaskAttachmentIncoming(call))
                        "openFile" -> {
                            openLocalFile(call)
                            result.success(null)
                        }
                        "mediaRoot" -> result.success(mediaRoot().absolutePath)
                        "cacheRoot" -> result.success(cacheRoot().absolutePath)
                        "deleteLocalFile" -> {
                            deleteLocalFile(call)
                            result.success(null)
                        }
                        "clearMedia" -> {
                            val media = mediaRoot()
                            val tasklyRoot = media.parentFile ?: media
                            if (tasklyRoot.exists()) tasklyRoot.deleteRecursively()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("TASKLY_MEDIA", error.message ?: error.javaClass.simpleName, null)
                }
            }
    }

    private fun mediaRoot(): File {
        val external = externalMediaDirs.firstOrNull { it != null }
        val base = external ?: filesDir
        return File(base, "Taskly/Media").also { it.mkdirs() }
    }

    private fun cacheRoot(): File {
        val tasklyRoot = mediaRoot().parentFile ?: mediaRoot()
        return File(tasklyRoot, ".cache").also { it.mkdirs() }
    }

    private fun category(mimeType: String): String = when {
        mimeType.startsWith("image/") -> "Taskly Images"
        mimeType.startsWith("video/") -> "Taskly Video"
        mimeType.startsWith("audio/") -> "Taskly Audio"
        else -> "Taskly Documents"
    }

    private fun destinationDir(mimeType: String, sent: Boolean): File {
        val base = File(mediaRoot(), category(mimeType)).also { it.mkdirs() }
        return if (sent) File(base, "Sent").also { it.mkdirs() } else base
    }

    private fun safeName(value: String): String {
        val cleaned = value
            .replace(Regex("[\\/:*?\"<>|\\u0000-\\u001F]"), "_")
            .trim()
        return cleaned.ifEmpty { "Taskly_${System.currentTimeMillis()}" }
    }

    private fun uniqueFile(dir: File, requestedName: String): File {
        val safe = safeName(requestedName)
        var candidate = File(dir, safe)
        if (!candidate.exists()) return candidate
        val dot = safe.lastIndexOf('.')
        val stem = if (dot > 0) safe.substring(0, dot) else safe
        val ext = if (dot > 0) safe.substring(dot) else ""
        candidate = File(dir, "${stem}_${System.currentTimeMillis()}$ext")
        return candidate
    }

    private fun prepareOutgoing(call: MethodCall): Map<String, Any> {
        val sourcePath = call.argument<String>("path")?.trim().orEmpty()
        val mime = call.argument<String>("mimeType")?.trim().orEmpty()
            .ifEmpty { "application/octet-stream" }
        val maxDimension = call.argument<Int>("maxDimension") ?: 1600
        val quality = (call.argument<Int>("jpegQuality") ?: 78).coerceIn(55, 92)
        val source = File(sourcePath)
        require(source.exists() && source.isFile) { "Source file is unavailable" }

        val isCompressibleImage = mime.startsWith("image/") &&
            !mime.equals("image/gif", ignoreCase = true)
        val dir = destinationDir(mime, sent = true)

        if (isCompressibleImage) {
            val output = uniqueFile(dir, source.nameWithoutExtension + ".jpg")
            if (compressImage(source, output, maxDimension, quality)) {
                scanMedia(output, "image/jpeg")
                return mapOf(
                    "path" to output.absolutePath,
                    "name" to output.name,
                    "mimeType" to "image/jpeg",
                    "sizeBytes" to output.length(),
                )
            }
        }

        val output = uniqueFile(dir, source.name)
        source.inputStream().use { input ->
            output.outputStream().use { outputStream -> input.copyTo(outputStream) }
        }
        scanMedia(output, mime)
        return mapOf(
            "path" to output.absolutePath,
            "name" to output.name,
            "mimeType" to mime,
            "sizeBytes" to output.length(),
        )
    }

    private fun taskAttachmentDir(sent: Boolean): File {
        val base = File(mediaRoot().parentFile ?: mediaRoot(), "Attachments").also { it.mkdirs() }
        return if (sent) File(base, "Sent").also { it.mkdirs() } else base
    }

    private fun prepareTaskAttachmentOutgoing(call: MethodCall): Map<String, Any> {
        val sourcePath = call.argument<String>("path")?.trim().orEmpty()
        val mime = call.argument<String>("mimeType")?.trim().orEmpty()
            .ifEmpty { "application/octet-stream" }
        val source = File(sourcePath)
        require(source.exists() && source.isFile) { "Source file is unavailable" }
        val output = uniqueFile(taskAttachmentDir(sent = true), source.name)
        source.inputStream().use { input ->
            output.outputStream().use { outputStream -> input.copyTo(outputStream) }
        }
        scanMedia(output, mime)
        return mapOf(
            "path" to output.absolutePath,
            "name" to output.name,
            "mimeType" to mime,
            "sizeBytes" to output.length(),
        )
    }

    private fun saveTaskAttachmentIncoming(call: MethodCall): Map<String, Any> {
        val bytes = call.argument<ByteArray>("bytes") ?: error("Missing attachment bytes")
        val requestedName = call.argument<String>("name")?.trim().orEmpty()
        val mime = call.argument<String>("mimeType")?.trim().orEmpty()
            .ifEmpty { "application/octet-stream" }
        val output = uniqueFile(
            taskAttachmentDir(sent = false),
            requestedName.ifEmpty { "Taskly_${System.currentTimeMillis()}" },
        )
        FileOutputStream(output).use { it.write(bytes) }
        scanMedia(output, mime)
        return mapOf(
            "path" to output.absolutePath,
            "name" to output.name,
            "mimeType" to mime,
            "sizeBytes" to output.length(),
        )
    }

    private fun saveIncoming(call: MethodCall): Map<String, Any> {
        val bytes = call.argument<ByteArray>("bytes") ?: error("Missing media bytes")
        val requestedName = call.argument<String>("name")?.trim().orEmpty()
        val mime = call.argument<String>("mimeType")?.trim().orEmpty()
            .ifEmpty { "application/octet-stream" }
        val sent = call.argument<Boolean>("sent") ?: false
        val dir = destinationDir(mime, sent)
        val output = uniqueFile(
            dir,
            requestedName.ifEmpty { "Taskly_${System.currentTimeMillis()}" },
        )
        FileOutputStream(output).use { it.write(bytes) }
        scanMedia(output, mime)
        return mapOf(
            "path" to output.absolutePath,
            "name" to output.name,
            "mimeType" to mime,
            "sizeBytes" to output.length(),
        )
    }

    private fun compressImage(
        source: File,
        destination: File,
        maxDimension: Int,
        quality: Int,
    ): Boolean {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false

        var sample = 1
        while (bounds.outWidth / sample > maxDimension * 2 ||
            bounds.outHeight / sample > maxDimension * 2
        ) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeFile(source.absolutePath, options) ?: return false
        bitmap = applyExifRotation(source, bitmap)

        val largest = maxOf(bitmap.width, bitmap.height)
        val scaled = if (largest > maxDimension) {
            val ratio = maxDimension.toFloat() / largest.toFloat()
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * ratio).toInt().coerceAtLeast(1),
                (bitmap.height * ratio).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            bitmap
        }

        FileOutputStream(destination).use { stream ->
            if (!scaled.compress(Bitmap.CompressFormat.JPEG, quality, stream)) return false
        }
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        return destination.exists() && destination.length() > 0
    }

    private fun applyExifRotation(source: File, bitmap: Bitmap): Bitmap {
        return try {
            val orientation = ExifInterface(source.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
            val degrees = when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            if (degrees == 0f) return bitmap
            val matrix = android.graphics.Matrix().apply { postRotate(degrees) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                .also { if (it !== bitmap) bitmap.recycle() }
        } catch (_: Throwable) {
            bitmap
        }
    }

    private fun scanMedia(file: File, mimeType: String) {
        try {
            MediaScannerConnection.scanFile(
                this,
                arrayOf(file.absolutePath),
                arrayOf(mimeType),
                null,
            )
        } catch (_: Throwable) {
            // Indexing is best-effort; saving/sending must still succeed.
        }
    }

    private fun deleteLocalFile(call: MethodCall) {
        val path = call.argument<String>("path")?.trim().orEmpty()
        if (path.isEmpty()) return
        val target = File(path)
        val tasklyRoot = mediaRoot().parentFile ?: mediaRoot()
        val safeRoot = tasklyRoot.canonicalFile
        val safeTarget = target.canonicalFile
        require(safeTarget.path.startsWith(safeRoot.path + File.separator)) {
            "Refusing to delete a file outside Taskly storage"
        }
        if (safeTarget.exists() && safeTarget.isFile) safeTarget.delete()
    }

    private fun openLocalFile(call: MethodCall) {
        val path = call.argument<String>("path")?.trim().orEmpty()
        val mime = call.argument<String>("mimeType")?.trim().orEmpty()
            .ifEmpty { "application/octet-stream" }
        val file = File(path)
        require(file.exists() && file.isFile) { "File is not available on this device" }
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.taskly.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime.lowercase(Locale.US))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent.createChooser(intent, "Open with"))
        }
    }
}
