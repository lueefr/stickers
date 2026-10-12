package de.loicezt.stickers

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import de.loicezt.stickers.video.CropAndScale
import de.loicezt.stickers.video.GifToWebP
import de.loicezt.stickers.video.OverlayAndEncode
import de.loicezt.stickers.video.WebPConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL_NAME = "de.loicezt.stickers/methods"
    private val TRIM_CHANNEL_NAME = "de.loicezt.stickers/progress_trim"
    private val ECODE_CHANNEL_NAME = "de.loicezt.stickers/progress_encode"
    private val INSTALL_SOURCE_REQUEST_CODE = 62001

    private var pendingInstallFile: File? = null
    private var pendingInstallResult: MethodChannel.Result? = null

    private val createdAt = SystemClock.elapsedRealtime()
    private var homeReady = false
    private var flutterDisplayed = false
    private var startupReported = false

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterDisplayed = true
        reportStartupIfReady()
    }

    private fun reportStartupIfReady() {
        if (!homeReady || !flutterDisplayed || startupReported) return
        startupReported = true
        Log.i("StickersStartup", "home_ready_ms=${SystemClock.elapsedRealtime() - createdAt}")
        reportFullyDrawn()
    }
    private val cropAndScaleDelegate = lazy { CropAndScale() }
    private val cropAndScale by cropAndScaleDelegate
    private val overlayAndEncodeDelegate = lazy { OverlayAndEncode() }
    private val overlayAndEncode by overlayAndEncodeDelegate
    private val gifToWebP by lazy { GifToWebP() }
    private val scope = CoroutineScope(
        Dispatchers.Main + SupervisorJob()
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Setup the MethodChannel to receive commands from Flutter
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "installApk" -> {
                    installDownloadedApk(call.arguments as? String, result)
                }
                "reportReady" -> {
                    // Sent after the first real home frame, with settings and
                    // packs loaded. Visible in release logcat for CI/device runs.
                    homeReady = true
                    reportStartupIfReady()
                    result.success(null)
                }
                "startTrim" -> {
                    val args = call.arguments as Map<String, String>
                    val inputFile = File(args["inputFile"]!!)
                    val outputFile = File(args["outputFile"]!!)
                    val startTimeUs = args["startTimeUs"]!!.toLong()
                    val endTimeUs = args["endTimeUs"]!!.toLong()
                    val rotationDegrees = args["rotationDegrees"]?.toInt() ?: 0
                    val cropToSquare = args["cropToSquare"]?.toBooleanStrictOrNull() ?: true
                    cropAndScale.start(inputFile, outputFile, startTimeUs, endTimeUs, 24, rotationDegrees, cropToSquare)
                    result.success(null)
                }

                "convertGif" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
                        return@setMethodCallHandler
                    }
                    // Decoding the GIF frame by frame and encoding every frame is
                    // CPU bound work that takes seconds, so it runs off the
                    // platform thread: this handler runs on it, and blocking it
                    // would freeze the UI (and the progress dialog the caller
                    // shows) for the whole conversion. Same pattern as
                    // CropAndScale and OverlayAndEncode, which launch on
                    // Dispatchers.Default internally.
                    scope.launch(Dispatchers.Default) {
                        try {
                            val inputFile = File(args["inputFile"]!! as String)
                            val outputFile = File(args["outputFile"]!! as String)
                            val fps = args["fps"]!! as Int
                            // WhatsApp rejects an animated sticker longer than
                            // ten seconds; older Flutter builds do not send the
                            // limit, so it falls back to the same constant.
                            val maxDurationMs =
                                (args["maxDurationMs"] as? Number)?.toInt()
                                    ?: GifToWebP.MAX_ANIMATED_DURATION_MS
                            val config = WebPConfig.fromMap(args["config"]!! as Map<*, *>)
                            // The length of the source GIF is reported back, so
                            // the caller can tell the user when only a part of it
                            // became the sticker.
                            val sourceDurationMs =
                                gifToWebP.convert(inputFile, outputFile, config, fps, maxDurationMs)
                            // The method channel result has to be delivered on the
                            // platform thread.
                            withContext(Dispatchers.Main) { result.success(sourceDurationMs) }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("GIF_CONVERT_FAILED", e.message, null)
                            }
                        }
                    }
                }

                "startOverlay" -> {
                    val args = call.arguments as? Map<*, *>;
                    if (args == null) {
                        result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val videoFile = File(args["videoFile"]!! as String)
                        val overlayFile = File(args["overlayFile"]!! as String)
                        val outputFile = File(args["outputFile"]!! as String)
                        overlayAndEncode.start(
                            videoFile,
                            overlayFile,
                            outputFile,
                            WebPConfig.fromMap(args["config"]!! as Map<*, *>),
                            args["fps"]!! as Int
                        )
                        result.success(null)
                    } catch (e: NullPointerException) {
                        result.error(
                            "MISSING_ARGUMENT",
                            "Missing a required file path argument.",
                            null
                        )
                    }
                }

                "cancelOverlay" -> {
                    overlayAndEncode.cancel()
                    result.success(null)
                }

                "cancelTrim" -> {
                    cropAndScale.cancel()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // 2. Setup the EventChannel to stream updates to Flutter
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRIM_CHANNEL_NAME
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var eventScope: CoroutineScope? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    // Combine both state and progress flows into a single stream
                    eventScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    eventScope?.launch {
                        cropAndScale.status.combine(cropAndScale.progress) { status, progress ->
                            mapOf(
                                "status" to status.name,
                                "progress" to progress.progress,
                                "currentFrame" to progress.currentFrame,
                                "totalFrames" to progress.totalFrames
                            )
                        }.collect { update ->
                            events.success(update)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventScope?.cancel()
                    eventScope = null
                }
            }
        )
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ECODE_CHANNEL_NAME
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var eventScope: CoroutineScope? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return

                    eventScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    eventScope?.launch {
                        overlayAndEncode.status.combine(overlayAndEncode.progress) { status, progress ->
                            mapOf(
                                "status" to status.name,
                                "progress" to progress.progress,
                                "currentFrame" to progress.currentFrame,
                                "totalFrames" to progress.totalFrames
                            )
                        }.collect { update ->
                            events.success(update)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventScope?.cancel()
                    eventScope = null
                }
            }
        )
    }

    private fun installDownloadedApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_APK", "An APK file path is required.", null)
            return
        }

        val apkFile = try {
            File(path).canonicalFile
        } catch (error: Exception) {
            result.error("INVALID_APK", error.message, null)
            return
        }
        val updatesDirectory = File(cacheDir, "updates").canonicalFile
        val allowedPrefix = updatesDirectory.path + File.separator
        if (!apkFile.path.startsWith(allowedPrefix) ||
            !apkFile.isFile ||
            !apkFile.name.endsWith(".apk", ignoreCase = true)
        ) {
            result.error("INVALID_APK", "The downloaded APK file is unavailable.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            if (pendingInstallResult != null) {
                result.error("INSTALL_IN_PROGRESS", "An APK installation is already in progress.", null)
                return
            }
            pendingInstallFile = apkFile
            pendingInstallResult = result
            try {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
                startActivityForResult(settingsIntent, INSTALL_SOURCE_REQUEST_CODE)
            } catch (error: Exception) {
                pendingInstallFile = null
                pendingInstallResult = null
                result.error("INSTALL_SETTINGS_UNAVAILABLE", error.message, null)
            }
            return
        }

        openApkInstaller(apkFile, result)
    }

    private fun openApkInstaller(apkFile: File, result: MethodChannel.Result) {
        try {
            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile,
            )
            val installerIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(installerIntent)
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("INSTALLER_NOT_FOUND", error.message, null)
        } catch (error: Exception) {
            result.error("INSTALL_FAILED", error.message, null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != INSTALL_SOURCE_REQUEST_CODE) return

        val result = pendingInstallResult ?: return
        val apkFile = pendingInstallFile
        pendingInstallResult = null
        pendingInstallFile = null

        if (apkFile == null || !apkFile.isFile) {
            result.error("INVALID_APK", "The downloaded APK file is unavailable.", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            result.error(
                "INSTALL_PERMISSION_DENIED",
                "Permission to install unknown apps was not granted.",
                null,
            )
            return
        }
        openApkInstaller(apkFile, result)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (cropAndScaleDelegate.isInitialized()) cropAndScale.release()
        // Cancelling the encode also releases the native WebP encoder it holds:
        // the connector keeps that state in one static pointer, so leaving it
        // behind would make every later conversion fail.
        if (overlayAndEncodeDelegate.isInitialized()) overlayAndEncode.release()
        scope.cancel()
    }
}

