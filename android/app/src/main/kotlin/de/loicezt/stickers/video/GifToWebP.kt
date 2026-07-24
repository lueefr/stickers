package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Movie
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max

class GifToWebP {
    companion object {
        private const val OUTPUT_DIMENSION = 512
    }

    fun convert(inputFile: File, outputFile: File, config: WebPConfig, fps: Int) {
        val gifBytes = inputFile.readBytes()
        val movie = Movie.decodeByteArray(gifBytes, 0, gifBytes.size)
            ?: throw IllegalArgumentException("Could not decode GIF")

        val width = if (movie.width() > 0) movie.width() else OUTPUT_DIMENSION
        val height = if (movie.height() > 0) movie.height() else OUTPUT_DIMENSION
        val duration = if (movie.duration() > 0) movie.duration() else 1000
        val frameIntervalMs = max(1, 1000 / max(1, fps))
        val scale = max(
            OUTPUT_DIMENSION.toFloat() / width.toFloat(),
            OUTPUT_DIMENSION.toFloat() / height.toFloat()
        )
        val dx = (OUTPUT_DIMENSION - width * scale) / 2f
        val dy = (OUTPUT_DIMENSION - height * scale) / 2f

        val bitmap = Bitmap.createBitmap(OUTPUT_DIMENSION, OUTPUT_DIMENSION, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val buffer = ByteBuffer.allocateDirect(OUTPUT_DIMENSION * OUTPUT_DIMENSION * 4)
        val encoder = LibWebP()

        if (!encoder.nativeInitEncoder(OUTPUT_DIMENSION, OUTPUT_DIMENSION, config)) {
            throw IllegalStateException("Could not initialize WebP encoder")
        }

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
        outputFile.writeBytes(data)
        bitmap.recycle()
    }
}
