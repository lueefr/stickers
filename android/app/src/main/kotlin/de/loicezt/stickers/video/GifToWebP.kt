package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Movie
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

class GifToWebP {
    companion object {
        private const val OUTPUT_DIMENSION = 512

        /** WhatsApp refuses an animated sticker longer than ten seconds. */
        const val MAX_ANIMATED_DURATION_MS = 10_000
    }

    /**
     * Converts a GIF into an animated WebP and returns the length of the
     * source GIF in milliseconds.
     *
     * The animation stops after [maxDurationMs] (WhatsApp's limit for an
     * animated sticker): together with the caller's own check this is a safety
     * net, so a longer GIF is cut instead of producing a sticker that makes
     * WhatsApp reject the whole pack. The returned length lets the caller tell
     * whether only a part of the GIF became the sticker.
     */
    fun convert(
        inputFile: File,
        outputFile: File,
        config: WebPConfig,
        fps: Int,
        maxDurationMs: Int = MAX_ANIMATED_DURATION_MS
    ): Int {
        val gifBytes = inputFile.readBytes()
        val movie = Movie.decodeByteArray(gifBytes, 0, gifBytes.size)
            ?: throw IllegalArgumentException("Could not decode GIF")

        val width = if (movie.width() > 0) movie.width() else OUTPUT_DIMENSION
        val height = if (movie.height() > 0) movie.height() else OUTPUT_DIMENSION
        val sourceDurationMs = if (movie.duration() > 0) movie.duration() else 1000
        val duration = min(sourceDurationMs, max(1, maxDurationMs))
        val frameIntervalMs = max(1, 1000 / max(1, fps))
        val scale = max(
            OUTPUT_DIMENSION.toFloat() / width.toFloat(),
            OUTPUT_DIMENSION.toFloat() / height.toFloat()
        )
        val dx = (OUTPUT_DIMENSION - width * scale) / 2f
        val dy = (OUTPUT_DIMENSION - height * scale) / 2f

        val bitmap = Bitmap.createBitmap(OUTPUT_DIMENSION, OUTPUT_DIMENSION, Bitmap.Config.ARGB_8888)
        // Whether the native encoder was initialized and still needs releasing.
        var encoderInitialized = false
        try {
            val canvas = Canvas(bitmap)
            val buffer = ByteBuffer.allocateDirect(OUTPUT_DIMENSION * OUTPUT_DIMENSION * 4)
            val encoder = LibWebP()

            if (!encoder.nativeInitEncoder(OUTPUT_DIMENSION, OUTPUT_DIMENSION, config)) {
                throw IllegalStateException("Could not initialize WebP encoder")
            }
            encoderInitialized = true

            var timestampMs = 0
            while (timestampMs < duration) {
                bitmap.eraseColor(Color.TRANSPARENT)
                canvas.save()
                canvas.translate(dx, dy)
                canvas.scale(scale, scale)
                movie.setTime(timestampMs)
                movie.draw(canvas, 0f, 0f)
                canvas.restore()

                buffer.rewind()
                bitmap.copyPixelsToBuffer(buffer)
                buffer.rewind()
                encoder.nativeAddFrame(buffer, timestampMs)
                timestampMs += frameIntervalMs
            }

            val data = encoder.nativeReleaseEncoder()
                ?: throw IllegalStateException("Could not assemble animated WebP")
            encoderInitialized = false
            outputFile.writeBytes(data)
        } finally {
            bitmap.recycle()
            // The native encoder keeps its state in a single static pointer, so a
            // failure that leaves it behind would make every later encode (of a
            // GIF or of a video) fail until the process restarts. Only the release
            // of an encoder this conversion initialized is safe: the video
            // encoder shares the same pointer.
            runCatching { if (encoderInitialized) LibWebP().nativeReleaseEncoder() }
        }
        // Reported to the caller so it can tell the user when only the first
        // seconds of a longer GIF became the sticker.
        return sourceDurationMs
    }
}
