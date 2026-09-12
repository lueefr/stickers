package de.loicezt.stickers

import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
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
    private val overlayAndEncode by lazy { OverlayAndEncode() }
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
                            val config = WebPConfig.fromMap(args["config"]!! as Map<*, *>)
                            gifToWebP.convert(inputFile, outputFile, config, fps)
                            // The method channel result has to be delivered on the
                            // platform thread.
                            withContext(Dispatchers.Main) { result.success(null) }
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

    override fun onDestroy() {
        super.onDestroy()
        if (cropAndScaleDelegate.isInitialized()) cropAndScale.release()
        scope.cancel()
    }
}

