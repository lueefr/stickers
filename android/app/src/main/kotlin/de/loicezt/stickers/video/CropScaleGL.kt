package de.loicezt.stickers.video

import android.graphics.SurfaceTexture
import android.opengl.*
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

class CropScaleGL : SurfaceTexture.OnFrameAvailableListener {

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    private var programHandle = 0
    private var positionHandle = 0
    private var texCoordHandle = 0
    private var transformMatrixHandle = 0
    private var positionMatrixHandle = 0

    private var videoTextureHandle = 0

    private val vertexBuffer: FloatBuffer
    private val texCoordBuffer: FloatBuffer
    private val transformMatrix = FloatArray(16)
    private val positionMatrix = FloatArray(16)

    private lateinit var decoderSurfaceTexture: SurfaceTexture
    lateinit var decoderInputSurface: Surface
        private set

    private val frameSemaphore = Semaphore(0)

    private var targetWidth: Int = 0
    private var targetHeight: Int = 0

    init {
        val vertexData = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
        vertexBuffer = ByteBuffer.allocateDirect(vertexData.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        vertexBuffer.put(vertexData).position(0)

        val texCoordData = floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)
        texCoordBuffer = ByteBuffer.allocateDirect(texCoordData.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        texCoordBuffer.put(texCoordData).position(0)
        Matrix.setIdentityM(positionMatrix, 0)
    }

    override fun onFrameAvailable(st: SurfaceTexture?) {
        frameSemaphore.release()
    }

    fun setup(
        encoderSurface: Surface,
        width: Int,
        height: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        rotationDegrees: Int,
        cropToSquare: Boolean
    ) {
        this.targetWidth = width
        this.targetHeight = height
        configureTextureCoordinates(sourceWidth, sourceHeight, rotationDegrees, cropToSquare)
        Matrix.setRotateM(positionMatrix, 0, rotationDegrees.toFloat(), 0f, 0f, 1f)

        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        EGL14.eglInitialize(eglDisplay, version, 0, version, 1)
        val attribList = intArrayOf(EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_NONE)
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, 1, numConfigs, 0)
        val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], encoderSurface, surfaceAttribs, 0)
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

        programHandle = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionHandle = GLES20.glGetAttribLocation(programHandle, "aPosition")
        texCoordHandle = GLES20.glGetAttribLocation(programHandle, "aTexCoord")
        transformMatrixHandle = GLES20.glGetUniformLocation(programHandle, "uTransformMatrix")
        positionMatrixHandle = GLES20.glGetUniformLocation(programHandle, "uPositionMatrix")

        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        videoTextureHandle = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, videoTextureHandle)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

        decoderSurfaceTexture = SurfaceTexture(videoTextureHandle)
        decoderSurfaceTexture.setOnFrameAvailableListener(this)
        decoderInputSurface = Surface(decoderSurfaceTexture)
    }


    private fun configureTextureCoordinates(sourceWidth: Int, sourceHeight: Int, rotationDegrees: Int, cropToSquare: Boolean) {
        var left = 0f
        var right = 1f
        var top = 0f
        var bottom = 1f
        if (cropToSquare) {
            val normalizedRotation = ((rotationDegrees % 180) + 180) % 180
            val rotatedWidth = if (normalizedRotation == 90) sourceHeight else sourceWidth
            val rotatedHeight = if (normalizedRotation == 90) sourceWidth else sourceHeight
            val aspect = rotatedWidth.toFloat() / rotatedHeight.toFloat()
            if (aspect > 1f) {
                val inset = (1f - 1f / aspect) / 2f
                left = inset
                right = 1f - inset
            } else if (aspect < 1f) {
                val inset = (1f - aspect) / 2f
                top = inset
                bottom = 1f - inset
            }
        }
        val texCoordData = floatArrayOf(left, top, right, top, left, bottom, right, bottom)
        texCoordBuffer.position(0)
        texCoordBuffer.put(texCoordData).position(0)
    }

    fun awaitNewFrame() {
        if (!frameSemaphore.tryAcquire(2, TimeUnit.SECONDS)) {
            throw TimeoutException("Timeout waiting for new video frame")
        }
    }

    fun drawFrame(timestampNs: Long) {
        decoderSurfaceTexture.updateTexImage()
        decoderSurfaceTexture.getTransformMatrix(transformMatrix)

        GLES20.glViewport(0, 0, targetWidth, targetHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glUseProgram(programHandle)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, videoTextureHandle)
        GLES20.glUniformMatrix4fv(transformMatrixHandle, 1, false, transformMatrix, 0)
        GLES20.glUniformMatrix4fv(positionMatrixHandle, 1, false, positionMatrix, 0)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 8, vertexBuffer)
        GLES20.glEnableVertexAttribArray(texCoordHandle)
        GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 8, texCoordBuffer)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(texCoordHandle)

        EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, timestampNs)
        EGL14.eglSwapBuffers(eglDisplay, eglSurface)
    }

    fun release() {
        decoderInputSurface.release()
        decoderSurfaceTexture.release()
        EGL14.eglDestroySurface(eglDisplay, eglSurface)
        EGL14.eglDestroyContext(eglDisplay, eglContext)
        EGL14.eglReleaseThread()
        EGL14.eglTerminate(eglDisplay)
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)
        return program
    }

    private fun loadShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        return shader
    }

    private val VERTEX_SHADER = """
        uniform mat4 uTransformMatrix;
        uniform mat4 uPositionMatrix;
        attribute vec4 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
            gl_Position = uPositionMatrix * aPosition;
            vTexCoord = (uTransformMatrix * vec4(aTexCoord, 0.0, 1.0)).xy;
        }
    """.trimIndent()

    private val FRAGMENT_SHADER = """
        #extension GL_OES_EGL_image_external : require
        precision mediump float;
        varying vec2 vTexCoord;
        uniform samplerExternalOES sTexture;
        void main() {
            gl_FragColor = texture2D(sTexture, vTexCoord);
        }
    """.trimIndent()
}

